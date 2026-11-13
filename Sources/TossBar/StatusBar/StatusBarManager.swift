import AppKit
import Combine

/// Keeps one `NSStatusItem` per configured item in sync with `ItemStore`.
@MainActor
final class StatusBarManager {
    private let env: AppEnvironment
    private var controllers: [UUID: StatusItemController] = [:]
    private var placeholder: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    init(env: AppEnvironment) {
        self.env = env

        env.store.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] items in self?.sync(items) }
            .store(in: &cancellables)

        // Redraw the menu bar text when data or settings change, batched.
        Publishers.Merge3(
            env.data.objectWillChange,
            env.settings.objectWillChange,
            env.credentials.objectWillChange
        )
        .debounce(for: .milliseconds(80), scheduler: RunLoop.main)
        .sink { [weak self] _ in self?.renderAll() }
        .store(in: &cancellables)

        // TOSSBAR_DIAG=1 prints every item's state every 3 seconds.
        if ProcessInfo.processInfo.environment["TOSSBAR_DIAG"] == "1" {
            Timer.publish(every: 3, on: .main, in: .common).autoconnect()
                .sink { [weak self] _ in self?.dumpDiagnostics() }
                .store(in: &cancellables)
        }
    }

    private var didWarnBlocked = false

    /// A few seconds after the items are created, warns once per launch if macOS
    /// placed none of them in the menu bar.
    private func scheduleBlockedCheck() {
        guard !didWarnBlocked else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, !self.didWarnBlocked, !self.controllers.isEmpty else { return }
            let blocked = self.controllers.values.allSatisfy(\.isNotPlacedBySystem)
                && (self.placeholderNotPlaced ?? true)
            guard blocked else { return }
            self.didWarnBlocked = true
            Self.showMenuBarBlockedAlert()
        }
    }

    private var placeholderNotPlaced: Bool? {
        guard let window = placeholder?.button?.window else { return nil }
        return window.frame.maxY <= 0
    }

    static func showMenuBarBlockedAlert() {
        let alert = NSAlert()
        alert.messageText = "TossBar 가 메뉴 막대에 표시되지 않고 있습니다"
        alert.informativeText = "macOS 의 '메뉴 막대에서 허용' 설정에서 TossBar 가 꺼져 있습니다.\n시스템 설정 > 메뉴 막대 > '메뉴 막대에서 허용' 목록에서 TossBar 를 켜 주세요. 켜면 바로 나타납니다."
        alert.addButton(withTitle: "시스템 설정 열기")
        alert.addButton(withTitle: "닫기")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            // The Menu Bar pane, falling back to System Settings itself.
            let candidates = [
                "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension",
                "x-apple.systempreferences:",
            ]
            for string in candidates {
                if let url = URL(string: string), NSWorkspace.shared.open(url) { break }
            }
        }
    }

    private func dumpDiagnostics() {
        print("[diag] \(Date()) items=\(controllers.count) placeholder=\(placeholder != nil)")
        if let error = env.data.errorMessage { print("[diag]   error=\(error)") }
        for (symbol, error) in env.data.symbolErrors { print("[diag]   \(symbol) error=\(error)") }
        for controller in controllers.values {
            print("[diag]   " + controller.diagnostics)
        }
        fflush(stdout)
    }

    /// Applies only what changed. Existing status items are never recreated: recreating one
    /// makes macOS and menu bar managers (Thaw, Ice, …) lose track of its position.
    private func sync(_ items: [MenuItemConfig]) {
        let ids = Set(items.map(\.id))

        // Deleted items: remove that status item and forget its position.
        for (id, controller) in controllers where !ids.contains(id) {
            controller.tearDown()
            controllers[id] = nil
            StatusItemController.forgetPosition(of: id)
        }
        // New items get a status item; existing ones only get the new config.
        for item in items {
            if let controller = controllers[item.id] {
                controller.update(item)
            } else {
                controllers[item.id] = StatusItemController(config: item, env: env)
            }
        }
        updatePlaceholder(isEmpty: items.isEmpty)
        scheduleBlockedCheck()
        if !items.isEmpty { env.data.refreshSoon() }
    }

    private func renderAll() {
        controllers.values.forEach { $0.render() }
    }

    /// With no items, show an icon that leads to the settings.
    private func updatePlaceholder(isEmpty: Bool) {
        if isEmpty, placeholder == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.autosaveName = "TossBar.placeholder"
            item.button?.image = NSImage(systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: "TossBar")
            let menu = NSMenu()
            let add = NSMenuItem(title: "항목 추가 / 설정…", action: #selector(PlaceholderTarget.openSettings), keyEquivalent: ",")
            add.target = PlaceholderTarget.shared
            menu.addItem(add)
            menu.addItem(.separator())
            let quit = NSMenuItem(title: "TossBar 종료", action: #selector(PlaceholderTarget.quit), keyEquivalent: "q")
            quit.target = PlaceholderTarget.shared
            menu.addItem(quit)
            item.menu = menu
            PlaceholderTarget.shared.env = env
            placeholder = item
        } else if !isEmpty, let item = placeholder {
            NSStatusBar.system.removeStatusItem(item)
            placeholder = nil
        }
    }
}

@MainActor
private final class PlaceholderTarget: NSObject {
    static let shared = PlaceholderTarget()
    weak var env: AppEnvironment?

    @objc func openSettings() { env?.openSettings() }
    @objc func quit() { env?.quit() }
}
