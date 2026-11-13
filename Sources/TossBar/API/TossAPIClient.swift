import Foundation

enum TossAPIError: LocalizedError {
    case missingCredentials
    case http(status: Int, code: String, message: String?)
    case oauth(code: String, description: String?)
    case decoding(String)
    case transport(String)

    var code: String? {
        switch self {
        case .http(_, let code, _): return code
        case .oauth(let code, _): return code
        default: return nil
        }
    }

    /// Shown in the UI, so the messages are Korean.
    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "API 키가 설정되지 않았습니다. 설정에서 Client ID/Secret 을 입력하세요."
        case .oauth(let code, let description):
            switch code {
            case "invalid_client": return "Client ID 또는 Secret 이 올바르지 않습니다."
            case "access_denied": return "허용되지 않은 IP 입니다. 토스증권 WTS > 설정 > Open API 에서 현재 IP 를 등록하세요."
            default: return "토큰 발급 실패 (\(code))" + (description.map { ": \($0)" } ?? "")
            }
        case .http(let status, let code, let message):
            switch code {
            case "ip-not-allowed": return "허용되지 않은 IP 입니다. 토스증권 WTS > 설정 > Open API 에서 현재 IP 를 등록하세요."
            case "token-revoked": return "다른 곳에서 같은 Client 로 토큰을 재발급해 현재 토큰이 무효화되었습니다."
            case "stock-not-found": return "종목을 찾을 수 없습니다."
            case "account-not-found": return "계좌를 찾을 수 없습니다."
            case "rate-limit-exceeded", "edge-rate-limit-exceeded": return "요청 한도를 초과했습니다. 잠시 후 다시 시도합니다."
            case "maintenance": return "토스증권 시스템 점검 중입니다."
            default:
                if let message, !message.isEmpty { return message }
                return "요청 실패 (HTTP \(status), \(code))"
            }
        case .decoding(let detail):
            return "응답을 해석하지 못했습니다: \(detail)"
        case .transport(let detail):
            return "네트워크 오류: \(detail)"
        }
    }
}

/// Requests per second allowed for each rate limit group, from the official docs.
enum RateGroup: Hashable {
    case auth, account, asset, stock, stockAll, marketInfo, marketData, marketDataChart

    var tps: Double {
        switch self {
        case .auth: return 5
        case .account: return 1
        case .asset: return 5
        case .stock: return 5
        case .stockAll: return 1
        case .marketInfo: return 3
        case .marketData: return 15
        case .marketDataChart: return 20
        }
    }
}

enum CandleInterval: String {
    case minute = "1m"
    case day = "1d"
}

/// Client for the Toss Securities OpenAPI.
///
/// - Only one access token per client is valid at a time, so the token is cached in a
///   user-only file and reused across launches instead of being reissued.
/// - Requests are spaced per rate limit group to avoid 429s up front. On a 429 the client
///   waits for `Retry-After` and retries. On a 401 it drops the token and retries once.
actor TossAPIClient {
    static let shared = TossAPIClient()

    private let baseURL = "https://openapi.tossinvest.com"
    private let session: URLSession
    private let decoder = TossAPIClient.makeDecoder()

    private var credentialsLoaded = false
    private var credentials: Credentials?
    private var token: CachedToken?
    private var tokenTask: Task<CachedToken, Error>?
    private var nextSlot: [RateGroup: Date] = [:]

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    /// JSON decoder for API responses. Dates are ISO 8601 with or without fractional seconds.
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = DateParsing.parse(string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
        }
        return decoder
    }

    // MARK: Credentials

    func hasCredentials() -> Bool {
        loadCredentialsIfNeeded()
        return credentials != nil
    }

    func updateCredentials(_ newValue: Credentials?) {
        credentialsLoaded = true
        if newValue != credentials {
            token = nil
            CachedToken.clear()
        }
        credentials = newValue
    }

    private func loadCredentialsIfNeeded() {
        guard !credentialsLoaded else { return }
        credentialsLoaded = true
        credentials = Credentials.load()
        if let cached = CachedToken.load(), cached.clientId == credentials?.clientId {
            token = cached
        }
    }

    // MARK: Token

    private func accessToken() async throws -> String {
        loadCredentialsIfNeeded()
        guard let credentials else { throw TossAPIError.missingCredentials }
        if let token, token.clientId == credentials.clientId, token.expiresAt > Date().addingTimeInterval(60) {
            return token.accessToken
        }
        // Concurrent callers share one in-flight token request.
        if let tokenTask {
            return try await tokenTask.value.accessToken
        }
        let task = Task { try await self.issueToken(credentials) }
        tokenTask = task
        defer { tokenTask = nil }
        let issued = try await task.value
        token = issued
        CachedToken.save(issued)
        return issued.accessToken
    }

    /// Drops the token only if it is still the one that failed, so a token that another
    /// request has already refreshed is kept.
    private func invalidateToken(_ used: String) {
        guard token?.accessToken == used else { return }
        token = nil
        CachedToken.clear()
    }

    private func issueToken(_ credentials: Credentials) async throws -> CachedToken {
        await throttle(.auth)
        var request = URLRequest(url: URL(string: baseURL + "/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = FormEncoding.encode([
            ("grant_type", "client_credentials"),
            ("client_id", credentials.clientId),
            ("client_secret", credentials.clientSecret),
        ]).data(using: .utf8)

        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else {
            if let error = try? decoder.decode(OAuthErrorResponse.self, from: data) {
                throw TossAPIError.oauth(code: error.error, description: error.error_description)
            }
            if let error = try? decoder.decode(ApiErrorEnvelope.self, from: data) {
                throw TossAPIError.http(status: response.statusCode, code: error.error.code, message: error.error.message)
            }
            throw TossAPIError.http(status: response.statusCode, code: "unknown", message: nil)
        }
        do {
            let body = try decoder.decode(OAuthTokenResponse.self, from: data)
            return CachedToken(
                clientId: credentials.clientId,
                accessToken: body.access_token,
                expiresAt: Date().addingTimeInterval(TimeInterval(body.expires_in))
            )
        } catch {
            throw TossAPIError.decoding(String(describing: error))
        }
    }

    // MARK: Request plumbing

    /// Reserves the next free slot for the group and sleeps until it arrives.
    private func throttle(_ group: RateGroup) async {
        let now = Date()
        let slot = max(now, nextSlot[group] ?? now)
        nextSlot[group] = slot.addingTimeInterval(1.05 / group.tps)
        let wait = slot.timeIntervalSince(now)
        if wait > 0 {
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw TossAPIError.transport("잘못된 응답")
            }
            return (data, http)
        } catch let error as TossAPIError {
            throw error
        } catch {
            throw TossAPIError.transport(error.localizedDescription)
        }
    }

    private func get<T: Decodable>(
        _ path: String,
        query: [URLQueryItem] = [],
        group: RateGroup,
        account: Int64? = nil
    ) async throws -> T {
        var attempt = 0
        var retriedAuth = false
        while true {
            attempt += 1
            let accessToken = try await accessToken()

            var request = URLRequest(url: Self.url(baseURL + path, query: query))
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let account {
                request.setValue(String(account), forHTTPHeaderField: "X-Tossinvest-Account")
            }

            await throttle(group)
            let (data, response) = try await send(request)
            let status = response.statusCode

            if (200..<300).contains(status) {
                do {
                    return try decoder.decode(ApiEnvelope<T>.self, from: data).result
                } catch {
                    throw TossAPIError.decoding(String(describing: error))
                }
            }

            let apiError = try? decoder.decode(ApiErrorEnvelope.self, from: data)
            let code = apiError?.error.code ?? "unknown"

            if status == 401, !retriedAuth {
                retriedAuth = true
                invalidateToken(accessToken)
                continue
            }
            if status == 429, attempt < 4 {
                let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
                let delay = retryAfter ?? pow(2, Double(attempt - 1))
                try? await Task.sleep(nanoseconds: UInt64((delay + Double.random(in: 0...0.3)) * 1_000_000_000))
                continue
            }
            throw TossAPIError.http(status: status, code: code, message: apiError?.error.message)
        }
    }

    /// Builds a request URL. `+` in values (time zone offsets in `before`) must be sent as
    /// `%2B`, but `URLComponents` leaves it as is, where the server would read it as a space.
    static func url(_ base: String, query: [URLQueryItem]) -> URL {
        var components = URLComponents(string: base)!
        if !query.isEmpty {
            components.queryItems = query
            components.percentEncodedQuery = components.percentEncodedQuery?
                .replacingOccurrences(of: "+", with: "%2B")
        }
        return components.url!
    }

    // MARK: Endpoints

    func accounts() async throws -> [Account] {
        try await get("/api/v1/accounts", group: .account)
    }

    func holdings(account: Int64) async throws -> HoldingsOverview {
        try await get("/api/v1/holdings", group: .asset, account: account)
    }

    func prices(_ symbols: [String]) async throws -> [PriceQuote] {
        var result: [PriceQuote] = []
        for chunk in symbols.chunked(into: 200) {
            let page: [PriceQuote] = try await get(
                "/api/v1/prices",
                query: [URLQueryItem(name: "symbols", value: chunk.joined(separator: ","))],
                group: .marketData
            )
            result += page
        }
        return result
    }

    func stocks(_ symbols: [String]) async throws -> [StockInfo] {
        var result: [StockInfo] = []
        for chunk in symbols.chunked(into: 200) {
            let page: [StockInfo] = try await get(
                "/api/v1/stocks",
                query: [URLQueryItem(name: "symbols", value: chunk.joined(separator: ","))],
                group: .stock
            )
            result += page
        }
        return result
    }

    func allStocks(market: String) async throws -> [StockListItem] {
        try await get(
            "/api/v1/stocks/all",
            query: [URLQueryItem(name: "market", value: market)],
            group: .stockAll
        )
    }

    /// Candles come back newest first. `count` is clamped to the API maximum of 200.
    func candles(symbol: String, interval: CandleInterval, count: Int, before: String? = nil) async throws -> CandlePage {
        var query = [
            URLQueryItem(name: "symbol", value: symbol),
            URLQueryItem(name: "interval", value: interval.rawValue),
            URLQueryItem(name: "count", value: String(min(max(count, 1), 200))),
        ]
        if let before { query.append(URLQueryItem(name: "before", value: before)) }
        return try await get("/api/v1/candles", query: query, group: .marketDataChart)
    }

    func usdKrwRate() async throws -> ExchangeRate {
        try await get(
            "/api/v1/exchange-rate",
            query: [
                URLQueryItem(name: "baseCurrency", value: "USD"),
                URLQueryItem(name: "quoteCurrency", value: "KRW"),
            ],
            group: .marketInfo
        )
    }
}

// MARK: - Helpers

enum DateParsing {
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    // ISO8601DateFormatter is not documented as thread safe.
    private static let lock = NSLock()

    static func parse(_ string: String) -> Date? {
        lock.lock(); defer { lock.unlock() }
        return fractional.date(from: string) ?? plain.date(from: string)
    }
}

enum FormEncoding {
    private static let allowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    /// `application/x-www-form-urlencoded` body. Everything outside the unreserved set is escaped.
    static func encode(_ pairs: [(String, String)]) -> String {
        pairs.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
