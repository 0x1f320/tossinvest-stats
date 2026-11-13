import Foundation

// MARK: - Primitive helpers

/// The Toss Securities API sends amounts and quantities as decimal strings such as `"72000"`.
/// Decoding them into `Decimal` keeps money math exact.
struct Dec: Decodable, Hashable, Sendable {
    let value: Decimal

    init(_ value: Decimal) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            guard let decimal = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid decimal: \(string)")
            }
            value = decimal
        } else {
            value = Decimal(try container.decode(Double.self))
        }
    }

    var double: Double { NSDecimalNumber(decimal: value).doubleValue }
}

enum Currency: String, Decodable, Hashable, Sendable {
    case krw = "KRW"
    case usd = "USD"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Currency(rawValue: raw) ?? .unknown
    }
}

// MARK: - Envelopes

struct ApiEnvelope<T: Decodable>: Decodable {
    let result: T
}

struct ApiErrorEnvelope: Decodable {
    struct Body: Decodable {
        let requestId: String?
        let code: String
        let message: String?
    }
    let error: Body
}

struct OAuthErrorResponse: Decodable {
    let error: String
    let error_description: String?
}

struct OAuthTokenResponse: Decodable {
    let access_token: String
    let token_type: String?
    let expires_in: Int64
}

// MARK: - Market data

struct PriceQuote: Decodable, Hashable, Sendable {
    let symbol: String
    let timestamp: Date?
    let lastPrice: Dec
    let currency: Currency
}

struct Candle: Decodable, Hashable, Sendable {
    let timestamp: Date
    let openPrice: Dec
    let highPrice: Dec
    let lowPrice: Dec
    let closePrice: Dec
    let volume: Dec
    let currency: Currency
}

struct CandlePage: Decodable, Sendable {
    let candles: [Candle]
    /// Passed back verbatim as `before` on the next request, so it stays a string.
    let nextBefore: String?
}

struct StockInfo: Decodable, Hashable, Sendable {
    let symbol: String
    let name: String
    let englishName: String?
    let market: String
    let securityType: String?
    let currency: Currency
    let status: String?
}

struct StockListItem: Decodable, Hashable, Sendable {
    let symbol: String
    let name: String
    let securityType: String?
}

struct ExchangeRate: Decodable, Hashable, Sendable {
    let rate: Dec
    /// The base rate (매매기준율), used for every USD to KRW conversion in the app.
    let midRate: Dec
    let rateChangeType: String?
    let validFrom: Date?
}

// MARK: - Account / Asset

struct Account: Decodable, Hashable, Identifiable, Sendable {
    let accountNo: String
    let accountSeq: Int64
    let accountType: String

    var id: Int64 { accountSeq }

    /// The account number with its middle digits masked, e.g. `123••••5678`.
    var maskedNumber: String {
        guard accountNo.count > 4 else { return accountNo }
        return String(accountNo.prefix(3))
            + String(repeating: "•", count: max(accountNo.count - 7, 2))
            + String(accountNo.suffix(4))
    }
}

/// Totals split by currency: `krw` sums domestic holdings only, `usd` sums US holdings only.
struct CurrencyAmounts: Decodable, Hashable, Sendable {
    let krw: Dec
    let usd: Dec?
}

struct HoldingsOverview: Decodable, Hashable, Sendable {
    struct MarketValue: Decodable, Hashable, Sendable {
        let amount: CurrencyAmounts
        let amountAfterCost: CurrencyAmounts
    }
    struct ProfitLoss: Decodable, Hashable, Sendable {
        let amount: CurrencyAmounts
        let amountAfterCost: CurrencyAmounts
        /// A ratio (0.1516 = 15.16%), computed on the whole portfolio converted to KRW.
        let rate: Dec
        let rateAfterCost: Dec
    }
    struct DailyProfitLoss: Decodable, Hashable, Sendable {
        let amount: CurrencyAmounts
        let rate: Dec
    }

    let totalPurchaseAmount: CurrencyAmounts
    let marketValue: MarketValue
    let profitLoss: ProfitLoss
    let dailyProfitLoss: DailyProfitLoss
    let items: [HoldingItem]
}

struct HoldingItem: Decodable, Hashable, Identifiable, Sendable {
    struct MarketValue: Decodable, Hashable, Sendable {
        let purchaseAmount: Dec
        let amount: Dec
        let amountAfterCost: Dec
    }
    struct ProfitLoss: Decodable, Hashable, Sendable {
        let amount: Dec
        let amountAfterCost: Dec
        let rate: Dec
        let rateAfterCost: Dec
    }
    struct DailyProfitLoss: Decodable, Hashable, Sendable {
        let amount: Dec
        let rate: Dec
    }
    struct Cost: Decodable, Hashable, Sendable {
        let commission: Dec
        let tax: Dec?
    }

    let symbol: String
    let name: String
    let marketCountry: String
    let currency: Currency
    let quantity: Dec
    let lastPrice: Dec
    let averagePurchasePrice: Dec
    let marketValue: MarketValue
    let profitLoss: ProfitLoss
    let dailyProfitLoss: DailyProfitLoss
    let cost: Cost

    var id: String { symbol }
}
