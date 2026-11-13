import Foundation

struct StockItemConfig: Codable, Hashable {
    var symbol: String
    /// Name shown in the menu bar. nil uses the stock's name.
    var displayName: String?
    var showName: Bool = true
    var showChange: Bool = true
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

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
