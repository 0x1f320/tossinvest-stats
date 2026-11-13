import Foundation

/// Currency for a US stock's price. Domestic stocks are always in KRW.
enum PriceDisplayCurrency: String, Codable, CaseIterable, Identifiable {
    /// The trading currency (USD for US stocks).
    case native
    /// Converted to KRW at the USD/KRW base rate.
    case krw

    var id: String { rawValue }
    var title: String {
        switch self {
        case .native: return "달러 ($)"
        case .krw: return "원화 (₩)"
        }
    }
}

struct StockItemConfig: Codable, Hashable {
    var symbol: String
    /// Name shown in the menu bar. nil uses the stock's name.
    var displayName: String?
    var showName: Bool = true
    var showChange: Bool = true
    /// Price currency for US stocks, set per item.
    var displayCurrency: PriceDisplayCurrency = .native
}

extension StockItemConfig {
    private enum CodingKeys: String, CodingKey {
        case symbol, displayName, showName, showChange, displayCurrency
    }

    /// Fills defaults for keys that older saved configs don't have.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try c.decode(String.self, forKey: .symbol)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        showName = try c.decodeIfPresent(Bool.self, forKey: .showName) ?? true
        showChange = try c.decodeIfPresent(Bool.self, forKey: .showChange) ?? true
        displayCurrency = try c.decodeIfPresent(PriceDisplayCurrency.self, forKey: .displayCurrency) ?? .native
    }
}

enum ItemKind: Codable, Hashable {
    case stock(StockItemConfig)
}

/// One menu bar item. Each config becomes its own `NSStatusItem`.
struct MenuItemConfig: Codable, Hashable, Identifiable {
    var id = UUID()
    var kind: ItemKind

    var typeTitle: String {
        switch kind {
        case .stock: return "주가"
        }
    }
}

/// The list of menu bar items, persisted in UserDefaults.
/// Their order in the menu bar is managed by macOS (⌘-drag) or a menu bar manager, not here.
@MainActor
final class ItemStore: ObservableObject {
    private static let defaultsKey = "menuItems.v1"

    @Published var items: [MenuItemConfig] {
        didSet { persist() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([MenuItemConfig].self, from: data) {
            items = decoded
        } else {
            items = []
        }
    }

    func item(_ id: UUID) -> MenuItemConfig? {
        items.first { $0.id == id }
    }

    func upsert(_ item: MenuItemConfig) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    /// Symbols used by stock items, without duplicates.
    var stockSymbols: [String] {
        var seen = Set<String>()
        return items.compactMap {
            if case .stock(let config) = $0.kind, seen.insert(config.symbol).inserted { return config.symbol }
            return nil
        }
    }

    /// Whether any stock item shows prices in KRW, which needs the USD/KRW rate.
    var needsUsdKrwForStocks: Bool {
        items.contains {
            if case .stock(let config) = $0.kind { return config.displayCurrency == .krw }
            return false
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
