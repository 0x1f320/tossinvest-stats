import Testing
@testable import TossBar

@Suite("String helpers")
struct ExtensionsTests {
    @Test func nilIfBlank() {
        #expect("".nilIfBlank == nil)
        #expect("  \n".nilIfBlank == nil)
        #expect("  abc ".nilIfBlank == "abc")
    }
}
