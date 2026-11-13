import AppKit
import Foundation
import ServiceManagement

/// App-wide dependencies, shared by the menu bar items and the windows.
@MainActor
final class AppEnvironment: ObservableObject {
    let client = TossAPIClient.shared
    let settings: AppSettings
    let store: ItemStore
    let credentials: CredentialStore
    let data: MarketDataService
    let universe: StockUniverse

    var openSettings: () -> Void = {}

    /// Set by "편집…" in a menu or popover. The settings window opens the editor for it.
    @Published var pendingEdit: UUID?

    init() {
        settings = AppSettings()
        store = ItemStore()
        credentials = CredentialStore(client: client)
        data = MarketDataService(client: client, store: store, settings: settings)
        universe = StockUniverse(client: client)
        credentials.onChange = { [weak self] in self?.data.reset() }
    }

    func editItem(_ id: UUID) {
        UserDefaults.standard.set("items", forKey: "settingsTab")
        openSettings()
        pendingEdit = id
    }

    func quit() {
        NSApp.terminate(nil)
    }
}

@MainActor
final class CredentialStore: ObservableObject {
    @Published private(set) var clientId: String
    @Published private(set) var hasSecret: Bool

    /// Called when the saved keys change, so cached data from the old keys can be dropped.
    var onChange: () -> Void = {}
    private let client: TossAPIClient

    init(client: TossAPIClient) {
        self.client = client
        let stored = Credentials.load()
        clientId = stored?.clientId ?? ""
        hasSecret = !(stored?.clientSecret.isEmpty ?? true)
    }

    var isConfigured: Bool { !clientId.isEmpty && hasSecret }

    /// Saves the keys, then checks them by issuing a token and listing the accounts.
    /// An empty secret keeps the one already saved, so the ID can be edited alone.
    func saveAndTest(clientId: String, clientSecret: String?) async throws -> [Account] {
        let trimmedId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = clientSecret?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSecret: String
        if let secret, !secret.isEmpty {
            resolvedSecret = secret
        } else if let existing = Credentials.load()?.clientSecret, !existing.isEmpty {
            resolvedSecret = existing
        } else {
            throw TossAPIError.missingCredentials
        }
        let credentials = Credentials(clientId: trimmedId, clientSecret: resolvedSecret)
        let changed = credentials != Credentials.load()
        Credentials.save(credentials)
        self.clientId = trimmedId
        self.hasSecret = true
        // Hand the new keys to the client before anyone refreshes with the old token.
        await client.updateCredentials(credentials)
        if changed { onChange() }
        return try await client.accounts()
    }

    func clear() async {
        Credentials.clear()
        CachedToken.clear()
        clientId = ""
        hasSecret = false
        await client.updateCredentials(nil)
        onChange()
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
