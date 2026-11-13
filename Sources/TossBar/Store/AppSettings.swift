import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let refreshInterval = "refreshInterval"
        static let koreanColors = "koreanColorConvention"
    }

    /// How often prices and holdings are refreshed, in seconds.
    @Published var refreshInterval: Double {
        didSet { UserDefaults.standard.set(refreshInterval, forKey: Key.refreshInterval) }
    }
    /// Colors in popovers. true: up red, down blue (Korean). false: up green, down red.
    /// The menu bar text itself is always white.
    @Published var koreanColorConvention: Bool {
        didSet {
            UserDefaults.standard.set(koreanColorConvention, forKey: Key.koreanColors)
            Palette.koreanConvention = koreanColorConvention
        }
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Key.refreshInterval: 10.0,
            Key.koreanColors: true,
        ])
        refreshInterval = defaults.double(forKey: Key.refreshInterval)
        koreanColorConvention = defaults.bool(forKey: Key.koreanColors)
        Palette.koreanConvention = koreanColorConvention
    }
}
