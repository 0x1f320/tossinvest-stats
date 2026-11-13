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

enum AssetMode: String, Codable, CaseIterable, Identifiable {
    /// Profit on the holdings since purchase.
    case total
    /// Profit since the previous close.
    case daily

    var id: String { rawValue }
    var title: String {
        switch self {
        case .total: return "전체 손익"
        case .daily: return "일간 손익"
        }
    }
}

struct AssetItemConfig: Codable, Hashable {
    /// Prefix in the menu bar. Empty means none.
    var label: String = ""
    /// nil means the first account.
    var accountSeq: Int64?
    var mode: AssetMode = .total
    /// Profit basis. false: raw profit. true: after fees and taxes. Applies to the total
    /// mode only; the API reports daily profit before costs only.
    var afterCost: Bool = false
    /// Colors the menu bar profit and rate by their sign, following the app's color
    /// convention. Off keeps the text white.
    var colorByTrend: Bool = false

    /// True when the after-cost basis is actually in effect.
    var usesAfterCost: Bool { mode == .total && afterCost }
}

extension AssetItemConfig {
    private enum CodingKeys: String, CodingKey {
        case label, accountSeq, mode, afterCost, colorByTrend
    }

    /// Fills defaults for keys that older saved configs don't have.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        accountSeq = try c.decodeIfPresent(Int64.self, forKey: .accountSeq)
        mode = try c.decodeIfPresent(AssetMode.self, forKey: .mode) ?? .total
        afterCost = try c.decodeIfPresent(Bool.self, forKey: .afterCost) ?? false
        colorByTrend = try c.decodeIfPresent(Bool.self, forKey: .colorByTrend) ?? false
    }
}

enum ItemKind: Codable, Hashable {
    case stock(StockItemConfig)
    case asset(AssetItemConfig)
}

/// One menu bar item. Each config becomes its own `NSStatusItem`.
struct MenuItemConfig: Codable, Hashable, Identifiable {
    var id = UUID()
    var kind: ItemKind

    var typeTitle: String {
        switch kind {
        case .stock: return "주가"
        case .asset: return "자산"
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

    var assetConfigs: [AssetItemConfig] {
        items.compactMap {
            if case .asset(let config) = $0.kind { return config }
            return nil
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
