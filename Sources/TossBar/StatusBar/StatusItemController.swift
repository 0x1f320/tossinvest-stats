import AppKit
import SwiftUI

/// One menu bar item: one `NSStatusItem` and its popover.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    let id: UUID
    private(set) var config: MenuItemConfig
    private let env: AppEnvironment
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    /// Padding added to the text width for the fixed item length. macOS adds 16pt to a
    /// fixed-length item's window, so text + 4pt matches a variable-length item
    /// (text + 20pt). Measured on macOS 26.
    private static let horizontalPadding: CGFloat = 4
    /// Current item width. It only grows, so the item doesn't jitter as digits change.
    private var reservedWidth: CGFloat = 0

    init(config: MenuItemConfig, env: AppEnvironment) {
        self.id = config.id
        self.config = config
        self.env = env
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        // A stable autosaveName lets macOS and menu bar managers (Thaw, Ice, …) recognize
        // the same item across launches and remember where it was placed.
        statusItem.autosaveName = Self.autosaveName(for: config.id)
        // Don't let ⌘-drag remove the item. Menu bar managers move icons by simulating ⌘-drag.
        statusItem.behavior = []
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        render()
    }

    static func autosaveName(for id: UUID) -> String {
        "TossBar.\(id.uuidString)"
    }

    func update(_ config: MenuItemConfig) {
        guard config != self.config else { return }
        let formatChanged = config.kind != self.config.kind
        self.config = config
        // A different format (name shown, currency, …) needs a fresh width.
        if formatChanged { reservedWidth = 0 }
        render()
    }

    func tearDown() {
        popover.performClose(nil)
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    /// Forgets the saved menu bar position once an item is deleted for good.
    static func forgetPosition(of id: UUID) {
        let name = autosaveName(for: id)
        UserDefaults.standard.removeObject(forKey: "NSStatusItem Preferred Position \(name)")
        UserDefaults.standard.removeObject(forKey: "NSStatusItem Visible \(name)")
    }

    func render() {
        guard let button = statusItem.button else { return }
        let title = TitleRenderer.title(for: config, env: env)
        let tooltip = TitleRenderer.tooltip(for: config, env: env)
        if button.toolTip != tooltip { button.toolTip = tooltip }
        // Leave an unchanged title alone. Setting it again re-lays out the menu bar,
        // which throws off menu bar managers.
        guard !button.attributedTitle.isEqual(to: title) else { return }
        button.attributedTitle = title

        // The width only grows, except when the text shrinks a lot (a loading
        // placeholder replaced by the value). `fittingSize` is meaningless for a
        // fixed-length item, so measure the text instead.
        let needed = ceil(title.size().width) + Self.horizontalPadding
        if needed > reservedWidth || needed < reservedWidth * 0.75 {
            reservedWidth = needed
            statusItem.length = needed
        }
    }

    // MARK: Click handling

    /// Left click opens the popover; right click or control-click opens the menu.
    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        let root: AnyView
        switch config.kind {
        case .stock:
            root = AnyView(StockPopoverView(itemID: id, env: env))
        case .asset:
            root = AnyView(AssetPopoverView(itemID: id, env: env))
        }
        let host = NSHostingController(rootView: root)
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        env.data.refreshSoon()
    }

    func popoverDidClose(_ notification: Notification) {
        // Drop the content so the SwiftUI tasks (chart refresh) stop.
        popover.contentViewController = nil
    }

    private func showContextMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "지금 새로고침", action: #selector(refreshNow), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "이 항목 편집…", action: #selector(editItem), keyEquivalent: "e").target = self
        menu.addItem(withTitle: "설정…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "이 항목 삭제", action: #selector(deleteItem), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "TossBar 종료", action: #selector(quit), keyEquivalent: "q").target = self
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    @objc private func refreshNow() { env.data.refreshSoon() }
    @objc private func openSettings() { env.openSettings() }
    @objc private func editItem() { env.editItem(id) }
    @objc private func quit() { env.quit() }

    @objc private func deleteItem() {
        let alert = NSAlert()
        alert.messageText = "이 메뉴바 항목을 삭제할까요?"
        alert.informativeText = TitleRenderer.tooltip(for: config, env: env)
        alert.addButton(withTitle: "삭제")
        alert.addButton(withTitle: "취소")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            env.store.remove(id)
        }
    }
}

/// Builds the menu bar text.
@MainActor
enum TitleRenderer {
    static var font: NSFont { NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular) }

    static func title(for config: MenuItemConfig, env: AppEnvironment) -> NSAttributedString {
        switch config.kind {
        case .stock(let stock): return stockTitle(stock, env: env)
        case .asset(let asset): return assetTitle(asset, env: env)
        }
    }

    static func tooltip(for config: MenuItemConfig, env: AppEnvironment) -> String {
        switch config.kind {
        case .stock(let stock):
            let name = env.data.stockInfo[stock.symbol]?.name ?? stock.symbol
            return "주가 · \(name) (\(stock.symbol))"
        case .asset(let asset):
            let seq = env.data.accountSeq(for: asset)
            let account = env.data.accounts.first { $0.accountSeq == seq }?.maskedNumber ?? "기본 계좌"
            return "자산 · \(account) · \(asset.mode.title) · \(asset.usesAfterCost ? "수수료·세금 제외" : "원본 수익")"
        }
    }

    /// Menu bar text is always white, whatever the trend or loading state.
    private static func attributed(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.white])
    }

    private static func stockTitle(_ config: StockItemConfig, env: AppEnvironment) -> NSAttributedString {
        let data = env.data
        let result = NSMutableAttributedString()
        if config.showName {
            var name = config.displayName?.nilIfBlank ?? data.stockInfo[config.symbol]?.name ?? config.symbol
            if name.count > 12 { name = String(name.prefix(11)) + "…" }
            result.append(attributed(name + " "))
        }
        guard let quote = data.quotes[config.symbol] else {
            let failed = data.symbolErrors[config.symbol] != nil || (data.errorMessage != nil && !data.isRefreshing)
            let placeholder = failed ? "⚠︎" : "…"
            result.append(attributed(config.showName ? placeholder : "\(config.symbol) \(placeholder)"))
            return result
        }
        let conversion = data.priceConversion(symbol: config.symbol, display: config.displayCurrency)
        if conversion.isConverted {
            // Add 원 so a converted price can't be mistaken for a domestic one.
            result.append(attributed(Fmt.priceWithUnit(conversion.apply(quote.lastPrice.value), .krw)))
        } else {
            result.append(attributed(Fmt.price(quote.lastPrice.value, quote.currency)))
        }
        if config.showChange, let change = data.change(for: config.symbol) {
            result.append(attributed(" " + Fmt.percent(ratio: change.rate)))
        }
        return result
    }

    /// Format from the spec: `{profit}₩ ({rate}%)`, e.g. `+1,019,000₩ (+11.79%)`.
    private static func assetTitle(_ config: AssetItemConfig, env: AppEnvironment) -> NSAttributedString {
        let data = env.data
        let result = NSMutableAttributedString()
        if let label = config.label.nilIfBlank {
            result.append(attributed(label + " "))
        }
        guard let seq = data.accountSeq(for: config), let overview = data.holdings[seq] else {
            let fallback = config.label.nilIfBlank == nil ? "자산 " : ""
            result.append(attributed(fallback + (data.errorMessage != nil && !data.isRefreshing ? "⚠︎" : "…")))
            return result
        }
        let summary = AssetSummary(overview: overview, usdKrw: data.usdKrwRate)
        let headline = summary.headline(for: config)
        let amountText = headline.amount.map(Fmt.krwProfit) ?? "…₩"
        result.append(attributed("\(amountText) (\(Fmt.percent(ratio: headline.rate)))"))
        return result
    }
}
