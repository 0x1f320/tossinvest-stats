import Foundation

extension String {
    /// The trimmed string, or nil when it is empty or whitespace only.
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
