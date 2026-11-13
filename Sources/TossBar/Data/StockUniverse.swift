import Foundation

/// Every listed stock, for the stock search in the item editor.
/// `GET /api/v1/stocks/all` is limited to 1 request per second, so each market is
/// fetched once and the result is cached on disk for a day.
@MainActor
final class StockUniverse: ObservableObject {
    struct Entry: Codable, Hashable, Identifiable {
        let symbol: String
        let name: String
        let market: String
        let securityType: String?
        var id: String { market + ":" + symbol }
    }

    private struct DiskCache: Codable {
        let savedAt: Date
        let entries: [Entry]
    }

    static let markets = ["KOSPI", "KOSDAQ", "KR_ETC", "NASDAQ", "NYSE", "AMEX", "US_ETC"]

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var loadedMarkets = 0
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let client: TossAPIClient
    private var loadTask: Task<Void, Never>?

    private var cacheURL: URL {
        SecretStore.directory.appendingPathComponent("stock-universe.json")
    }

    init(client: TossAPIClient) {
        self.client = client
    }

    func ensureLoaded() {
        guard entries.isEmpty, loadTask == nil else { return }
        if let data = try? Data(contentsOf: cacheURL),
           let cache = try? JSONDecoder().decode(DiskCache.self, from: data),
           Date().timeIntervalSince(cache.savedAt) < 86_400, !cache.entries.isEmpty {
            entries = cache.entries
            loadedMarkets = Self.markets.count
            return
        }
        loadTask = Task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        loadedMarkets = 0
        var collected: [Entry] = []
        var failed = false
        for market in Self.markets {
            do {
                let items = try await client.allStocks(market: market)
                collected += items.map { Entry(symbol: $0.symbol, name: $0.name, market: market, securityType: $0.securityType) }
                entries = collected
            } catch {
                failed = true
                errorMessage = error.localizedDescription
            }
            loadedMarkets += 1
        }
        isLoading = false
        loadTask = nil
        // Only cache a complete list, so a partial failure is retried next time.
        if !failed, let data = try? JSONEncoder().encode(DiskCache(savedAt: Date(), entries: collected)) {
            try? data.write(to: cacheURL)
        }
    }

    func search(_ query: String, limit: Int = 60) -> [Entry] {
        Self.search(query, in: entries, limit: limit)
    }

    /// Ranks matches: exact symbol or name, then symbol prefix, name prefix, name substring.
    /// Ties go to the shorter name, which is usually the main listing.
    nonisolated static func search(_ rawQuery: String, in entries: [Entry], limit: Int = 60) -> [Entry] {
        let query = rawQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }
        var scored: [(Int, Entry)] = []
        for entry in entries {
            let symbol = entry.symbol.lowercased()
            let name = entry.name.lowercased()
            let score: Int
            if symbol == query || name == query { score = 0 }
            else if symbol.hasPrefix(query) { score = 1 }
            else if name.hasPrefix(query) { score = 2 }
            else if name.contains(query) { score = 3 }
            else { continue }
            scored.append((score, entry))
        }
        scored.sort { lhs, rhs in
            if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
            return lhs.1.name.count < rhs.1.name.count
        }
        return scored.prefix(limit).map(\.1)
    }
}
