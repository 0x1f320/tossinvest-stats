import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Placeholder icon so the app is reachable until real items exist.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "TossBar.placeholder"
        item.button?.image = NSImage(
            systemSymbolName: "chart.line.uptrend.xyaxis",
            accessibilityDescription: "TossBar"
        )
        let menu = NSMenu()
        menu.addItem(
            withTitle: "TossBar 종료",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        item.menu = menu
        statusItem = item
    }
}
