import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let env = AppEnvironment()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        env.openSettings = { [weak self] in self?.showSettings() }
        installPlaceholder()

        // First launch (no keys yet): ask for the API keys.
        if !env.credentials.isConfigured {
            showOnboarding()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    private func installPlaceholder() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "TossBar.placeholder"
        item.button?.image = NSImage(
            systemSymbolName: "chart.line.uptrend.xyaxis",
            accessibilityDescription: "TossBar"
        )
        let menu = NSMenu()
        menu.addItem(withTitle: "설정…", action: #selector(openSettingsFromMenu), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "TossBar 종료",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        item.menu = menu
        statusItem = item
    }

    @objc private func openSettingsFromMenu() { showSettings() }

    private func makeWindow<V: View>(title: String, rootView: V) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: rootView))
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            onboardingWindow = makeWindow(
                title: "TossBar",
                rootView: OnboardingView(env: env) { [weak self] in
                    self?.onboardingWindow?.close()
                }
            )
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    func showSettings() {
        if !env.credentials.isConfigured {
            showOnboarding()
            return
        }
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "TossBar 설정", rootView: SettingsView(env: env))
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === onboardingWindow { onboardingWindow = nil }
        if window === settingsWindow { settingsWindow = nil }
    }
}
