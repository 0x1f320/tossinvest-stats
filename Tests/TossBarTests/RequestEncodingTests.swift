import Foundation
import Testing
@testable import TossBar

@Suite("Request encoding")
struct RequestEncodingTests {
    @Test func formEncodingEscapesReservedCharacters() {
        let body = FormEncoding.encode([("client_id", "a b"), ("client_secret", "x+y/z=&")])
        #expect(body == "client_id=a%20b&client_secret=x%2By%2Fz%3D%26")
    }

    @Test func plusInQueryIsPercentEncoded() {
        let url = TossAPIClient.url("https://example.com/api", query: [
            URLQueryItem(name: "before", value: "2026-11-13T09:00:00+09:00"),
        ])
        #expect(url.absoluteString == "https://example.com/api?before=2026-11-13T09:00:00%2B09:00")
    }

    @Test func chunked() {
        #expect(Array(1...5).chunked(into: 2) == [[1, 2], [3, 4], [5]])
        #expect([Int]().chunked(into: 3).isEmpty)
    }
}
