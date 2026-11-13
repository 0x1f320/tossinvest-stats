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
