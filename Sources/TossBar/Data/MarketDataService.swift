import Foundation

/// The two latest daily candles. Used for the change against the previous close.
struct DailySnapshot {
    let latest: Candle
    let previous: Candle?
    let fetchedAt: Date
}

/// Data shared by every menu bar item, plus the polling loop that refreshes it.
/// When several items show the same stock, the API is still called once per refresh.
@MainActor
final class MarketDataService: ObservableObject {
    @Published private(set) var quotes: [String: PriceQuote] = [:]
    @Published private(set) var daily: [String: DailySnapshot] = [:]
    @Published private(set) var stockInfo: [String: StockInfo] = [:]
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var symbolErrors: [String: String] = [:]
    @Published private(set) var isRefreshing = false

    private let client: TossAPIClient
    private let store: ItemStore
    private let settings: AppSettings

    private var loopTask: Task<Void, Never>?
    private var lastStockInfoAttempt: [String: Date] = [:]

    init(client: TossAPIClient, store: ItemStore, settings: AppSettings) {
        self.client = client
        self.store = store
        self.settings = settings
    }

    // MARK: Lifecycle

    func start() {
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let interval = self?.settings.refreshInterval ?? 10
                try? await Task.sleep(nanoseconds: UInt64(max(interval, 3) * 1_000_000_000))
            }
        }
    }

    /// Drops everything cached and restarts. Called when the API keys change.
    func reset() {
        quotes = [:]
        daily = [:]
        errorMessage = nil
        symbolErrors = [:]
        start()
    }

    func refreshSoon() {
        Task { await refresh() }
    }

    // MARK: Accessors

    func currency(for symbol: String) -> Currency {
        quotes[symbol]?.currency ?? stockInfo[symbol]?.currency ?? daily[symbol]?.latest.currency ?? .krw
    }

    /// Change against the previous close, as (amount, ratio).
    func change(for symbol: String) -> (amount: Decimal, rate: Decimal)? {
        guard let quote = quotes[symbol], let previous = daily[symbol]?.previous else { return nil }
        let base = previous.closePrice.value
        guard base != 0 else { return nil }
        let amount = quote.lastPrice.value - base
        return (amount, amount / base)
    }

    // MARK: Polling

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard await client.hasCredentials() else {
            errorMessage = TossAPIError.missingCredentials.errorDescription
            return
        }

        var errors: [String] = []
        let symbols = store.stockSymbols

        // 1) Stock info (name, market, currency). Fetched once, retried at most every 5 minutes.
        let missingInfo = symbols.filter { symbol in
            stockInfo[symbol] == nil &&
                (lastStockInfoAttempt[symbol].map { Date().timeIntervalSince($0) > 300 } ?? true)
        }
        if !missingInfo.isEmpty {
            missingInfo.forEach { lastStockInfoAttempt[$0] = Date() }
            do {
                for info in try await client.stocks(missingInfo) {
                    stockInfo[info.symbol] = info
                }
            } catch {
                errors.append(error.localizedDescription)
            }
        }

        // 2) Current prices, up to 200 symbols per request.
        if !symbols.isEmpty {
            do {
                for quote in try await client.prices(symbols) {
                    quotes[quote.symbol] = quote
                }
                symbols.forEach { symbolErrors[$0] = nil }
            } catch {
                // A failed batch doesn't say which symbol is bad, so retry one by one.
                for symbol in symbols {
                    do {
                        if let quote = try await client.prices([symbol]).first {
                            quotes[symbol] = quote
                            symbolErrors[symbol] = nil
                        }
                    } catch {
                        symbolErrors[symbol] = error.localizedDescription
                    }
                }
                errors.append(error.localizedDescription)
            }
        }

        // 3) The two latest daily candles (previous close), cached for 2 minutes.
        for symbol in symbols {
            if let snapshot = daily[symbol], Date().timeIntervalSince(snapshot.fetchedAt) < 120 { continue }
            do {
                let page = try await client.candles(symbol: symbol, interval: .day, count: 2)
                if let latest = page.candles.first {
                    daily[symbol] = DailySnapshot(latest: latest, previous: page.candles.dropFirst().first, fetchedAt: Date())
                }
            } catch {
                symbolErrors[symbol] = symbolErrors[symbol] ?? error.localizedDescription
            }
        }

        errorMessage = errors.first
        if errors.isEmpty || !quotes.isEmpty {
            lastUpdated = Date()
        }
    }
}
