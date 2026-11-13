import Foundation

enum ChartRange: String, CaseIterable, Identifiable {
    case day = "1D"
    case month = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case year = "1Y"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "1일"
        case .month: return "1개월"
        case .threeMonths: return "3개월"
        case .sixMonths: return "6개월"
        case .year: return "1년"
        }
    }

    var interval: CandleInterval { self == .day ? .minute : .day }

    /// Number of candles to fetch (trading days for daily ranges).
    var candleCount: Int {
        switch self {
        case .day: return 1000 // Pages back until the session day ends.
        case .month: return 22
        case .threeMonths: return 66
        case .sixMonths: return 130
        case .year: return 250
        }
    }

    var cacheTTL: TimeInterval { self == .day ? 20 : 300 }
}

struct ChartPoint: Identifiable, Hashable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// How to show a price: the factor to multiply by and the resulting currency.
struct PriceConversion {
    let factor: Decimal
    /// Currency to display.
    let currency: Currency
    /// The USD/KRW rate applied when converting to KRW, otherwise nil.
    let rate: Decimal?

    var isConverted: Bool { rate != nil }
    func apply(_ value: Decimal) -> Decimal { value * factor }
    func apply(_ value: Double) -> Double { value * factor.double }

    /// A US stock shown in KRW is converted once the rate is known. Until then, and for
    /// everything else, the price stays in its trading currency.
    static func make(native: Currency, display: PriceDisplayCurrency, usdKrw: Decimal?) -> PriceConversion {
        if display == .krw, native == .usd, let rate = usdKrw {
            return PriceConversion(factor: rate, currency: .krw, rate: rate)
        }
        return PriceConversion(factor: 1, currency: native, rate: nil)
    }
}

extension Currency {
    /// Time zone of the exchange, used to find the session day for intraday charts.
    var marketTimeZone: TimeZone {
        switch self {
        case .usd: return TimeZone(identifier: "America/New_York")!
        default: return TimeZone(identifier: "Asia/Seoul")!
        }
    }
}

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
    @Published private(set) var holdings: [Int64: HoldingsOverview] = [:]
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var usdKrw: ExchangeRate?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var symbolErrors: [String: String] = [:]
    @Published private(set) var isRefreshing = false

    private let client: TossAPIClient
    private let store: ItemStore
    private let settings: AppSettings

    private var loopTask: Task<Void, Never>?
    private var lastFxFetch: Date?
    private var lastAccountsFetch: Date?
    private var lastStockInfoAttempt: [String: Date] = [:]
    private var chartCache: [String: (fetchedAt: Date, points: [Candle])] = [:]
    private var sparkCache: [String: (fetchedAt: Date, values: [Double])] = [:]
    private var sparkInFlight: [String: Task<[Double]?, Never>] = [:]

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
        holdings = [:]
        accounts = []
        usdKrw = nil
        lastFxFetch = nil
        lastAccountsFetch = nil
        errorMessage = nil
        symbolErrors = [:]
        chartCache = [:]
        sparkCache = [:]
        start()
    }

    func refreshSoon() {
        Task { await refresh() }
    }

    // MARK: Accessors

    func accountSeq(for config: AssetItemConfig) -> Int64? {
        config.accountSeq ?? accounts.first?.accountSeq
    }

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

    /// USD/KRW base rate (매매기준율).
    var usdKrwRate: Decimal? { usdKrw?.midRate.value }

    func priceConversion(symbol: String, display: PriceDisplayCurrency) -> PriceConversion {
        PriceConversion.make(native: currency(for: symbol), display: display, usdKrw: usdKrwRate)
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
        let assetConfigs = store.assetConfigs

        // 0) Accounts. ACCOUNT allows 1 request per second, so cache for 10 minutes.
        if !assetConfigs.isEmpty,
           accounts.isEmpty || (lastAccountsFetch.map { Date().timeIntervalSince($0) > 600 } ?? true) {
            do {
                accounts = try await client.accounts()
                lastAccountsFetch = Date()
            } catch {
                errors.append(error.localizedDescription)
            }
        }

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

        // 4) USD/KRW rate for US holdings and stock items shown in KRW, cached for a minute.
        if !assetConfigs.isEmpty || store.needsUsdKrwForStocks,
           lastFxFetch.map({ Date().timeIntervalSince($0) > 60 }) ?? true {
            do {
                usdKrw = try await client.usdKrwRate()
                lastFxFetch = Date()
            } catch {
                errors.append(error.localizedDescription)
            }
        }

        // 5) Holdings, once per account even if several items show it.
        let seqs = Set(assetConfigs.compactMap { accountSeq(for: $0) })
        for seq in seqs.sorted() {
            do {
                holdings[seq] = try await client.holdings(account: seq)
            } catch {
                errors.append(error.localizedDescription)
            }
        }

        errorMessage = errors.first
        if errors.isEmpty || !quotes.isEmpty || !holdings.isEmpty {
            lastUpdated = Date()
        }
    }

    /// For the account picker in the asset item editor.
    func loadAccounts() async throws -> [Account] {
        let result = try await client.accounts()
        accounts = result
        lastAccountsFetch = Date()
        return result
    }

    // MARK: Charts

    /// Candles for the chart, oldest first.
    func chartCandles(symbol: String, range: ChartRange) async throws -> [Candle] {
        let key = "\(symbol)|\(range.rawValue)"
        if let cached = chartCache[key], Date().timeIntervalSince(cached.fetchedAt) < range.cacheTTL {
            return cached.points
        }

        var collected: [Candle] = []
        var seen = Set<Date>()
        var before: String?
        var remaining = range.candleCount
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = currency(for: symbol).marketTimeZone

        while remaining > 0 {
            let page = try await client.candles(
                symbol: symbol,
                interval: range.interval,
                count: min(remaining, 200),
                before: before
            )
            for candle in page.candles where seen.insert(candle.timestamp).inserted {
                collected.append(candle)
            }
            remaining = range.candleCount - collected.count
            guard let next = page.nextBefore, !page.candles.isEmpty else { break }
            before = next

            // 1D: stop once the pages reach the session before the latest one.
            if range == .day, let first = collected.first, let last = collected.last,
               !calendar.isDate(Self.sessionTime(first), inSameDayAs: Self.sessionTime(last)) {
                break
            }
        }

        if range == .day, let newest = collected.first {
            let sessionDay = Self.sessionTime(newest)
            collected = collected.filter { calendar.isDate(Self.sessionTime($0), inSameDayAs: sessionDay) }
        }

        let ascending = Array(collected.reversed())
        chartCache[key] = (Date(), ascending)
        return ascending
    }

    /// Closing prices of the last 30 trading days, for the mini charts in the holdings list.
    /// Cached for 10 minutes; concurrent callers share one request.
    func sparkline(symbol: String) async -> [Double]? {
        if let cached = sparkCache[symbol], Date().timeIntervalSince(cached.fetchedAt) < 600 {
            return cached.values
        }
        if let task = sparkInFlight[symbol] { return await task.value }
        let task = Task<[Double]?, Never> { [client] in
            guard let page = try? await client.candles(symbol: symbol, interval: .day, count: 30) else { return nil }
            return page.candles.reversed().map { $0.closePrice.double }
        }
        sparkInFlight[symbol] = task
        let values = await task.value
        sparkInFlight[symbol] = nil
        if let values { sparkCache[symbol] = (Date(), values) }
        return values
    }

    func cachedSparkline(symbol: String) -> [Double]? {
        sparkCache[symbol]?.values
    }

    /// A minute candle's timestamp is the end of the bar, so step back a minute to get
    /// the session day it belongs to.
    private static func sessionTime(_ candle: Candle) -> Date {
        candle.timestamp.addingTimeInterval(-60)
    }
}
