import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let refreshInterval = "refreshInterval"
    }

    /// How often prices and holdings are refreshed, in seconds.
    @Published var refreshInterval: Double {
        didSet { UserDefaults.standard.set(refreshInterval, forKey: Key.refreshInterval) }
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Key.refreshInterval: 10.0,
        ])
        refreshInterval = defaults.double(forKey: Key.refreshInterval)
    }
}
