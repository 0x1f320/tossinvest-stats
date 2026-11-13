import Testing
@testable import TossBar

@Suite("Stock search")
struct StockSearchTests {
    private let entries = [
        StockUniverse.Entry(symbol: "005930", name: "삼성전자", market: "KOSPI", securityType: nil),
        StockUniverse.Entry(symbol: "005935", name: "삼성전자우", market: "KOSPI", securityType: nil),
        StockUniverse.Entry(symbol: "AAPL", name: "애플", market: "NASDAQ", securityType: nil),
        StockUniverse.Entry(symbol: "AAP", name: "어드밴스 오토 파츠", market: "NYSE", securityType: nil),
        StockUniverse.Entry(symbol: "207940", name: "삼성바이오로직스", market: "KOSPI", securityType: nil),
    ]

    @Test func exactSymbolComesFirst() {
        let result = StockUniverse.search("aap", in: entries)
        #expect(result.map(\.symbol) == ["AAP", "AAPL"])
    }

    @Test func namePrefixPrefersShorterName() {
        let result = StockUniverse.search("삼성", in: entries)
        #expect(result.map(\.symbol) == ["005930", "005935", "207940"])
    }

    @Test func substringMatchesName() {
        #expect(StockUniverse.search("바이오", in: entries).map(\.symbol) == ["207940"])
    }

    @Test func blankQueryReturnsNothing() {
        #expect(StockUniverse.search("  ", in: entries).isEmpty)
    }

    @Test func respectsLimit() {
        #expect(StockUniverse.search("삼성", in: entries, limit: 1).count == 1)
    }
}
