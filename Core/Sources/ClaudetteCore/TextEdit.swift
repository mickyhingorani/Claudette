import Foundation

/// One replacement in the document text. Ranges are UTF-16 offsets.
public struct TextEdit: Equatable, Sendable {
    public var range: NSRange
    public var replacement: String

    public init(range: NSRange, replacement: String) {
        self.range = range
        self.replacement = replacement
    }
}
