import Foundation
import Testing
@testable import TossBar

@Suite("API model decoding")
struct ModelDecodingTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try TossAPIClient.makeDecoder().decode(type, from: Data(json.utf8))
    }

    @Test func decimalFromString() throws {
        let value = try decode([Dec].self, #"["72000", "185.7", "-0.0123"]"#)
        #expect(value.map(\.value) == [72000, Decimal(string: "185.7")!, Decimal(string: "-0.0123")!])
    }

    @Test func decimalFromNumber() throws {
        let value = try decode([Dec].self, "[1375, 0.5]")
        #expect(value.map(\.value) == [1375, Decimal(string: "0.5")!])
    }

    @Test func invalidDecimalThrows() {
        #expect(throws: DecodingError.self) { try decode(Dec.self, #""abc""#) }
    }

    @Test func unknownCurrencyFallsBack() throws {
        let value = try decode([Currency].self, #"["KRW", "USD", "JPY"]"#)
        #expect(value == [.krw, .usd, .unknown])
    }

    @Test func priceEnvelopeWithFractionalDate() throws {
        let json = #"""
        {"result": [
          {"symbol": "005930", "timestamp": "2026-11-13T15:30:00.123+09:00", "lastPrice": "72000", "currency": "KRW"},
          {"symbol": "AAPL", "timestamp": "2026-11-13T21:00:00Z", "lastPrice": "178.5", "currency": "USD"}
        ]}
        """#
        let quotes = try decode(ApiEnvelope<[PriceQuote]>.self, json).result
        #expect(quotes.count == 2)
        #expect(quotes[0].lastPrice.value == 72000)
        let expected = ISO8601DateFormatter().date(from: "2026-11-13T06:30:00Z")!.addingTimeInterval(0.123)
        #expect(abs(quotes[0].timestamp!.timeIntervalSince(expected)) < 0.001)
        #expect(quotes[1].currency == .usd)
    }

    @Test func candlePageKeepsNextBeforeVerbatim() throws {
        let json = #"""
        {"candles": [{"timestamp": "2026-11-13T09:01:00+09:00", "openPrice": "1", "highPrice": "2",
                      "lowPrice": "1", "closePrice": "2", "volume": "10", "currency": "KRW"}],
         "nextBefore": "2026-11-13T09:00:00+09:00"}
        """#
        let page = try decode(CandlePage.self, json)
        #expect(page.nextBefore == "2026-11-13T09:00:00+09:00")
        #expect(page.candles.first?.closePrice.value == 2)
    }

    @Test func holdingsOverview() throws {
        let overview = try decode(HoldingsOverview.self, Fixtures.holdingsJSON)
        #expect(overview.items.count == 2)
        #expect(overview.profitLoss.amount.krw.value == 700_000)
        #expect(overview.profitLoss.amount.usd?.value == 232)
        #expect(overview.items[1].currency == .usd)
        #expect(overview.items[0].cost.tax == nil)
    }

    @Test func errorEnvelope() throws {
        let error = try decode(ApiErrorEnvelope.self, #"{"error": {"requestId": "r1", "code": "ip-not-allowed", "message": "nope"}}"#)
        #expect(error.error.code == "ip-not-allowed")
        #expect(TossAPIError.http(status: 403, code: error.error.code, message: error.error.message).errorDescription?.contains("IP") == true)
    }

    @Test func maskedAccountNumber() {
        let account = Account(accountNo: "12345678901", accountSeq: 1, accountType: "BROKERAGE")
        #expect(account.maskedNumber == "123••••8901")
        #expect(Account(accountNo: "1234", accountSeq: 2, accountType: "X").maskedNumber == "1234")
    }
}
