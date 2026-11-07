import Foundation

public struct TableCell: Equatable, Sendable {
    public var textRange: NSRange
    public var text: String
}

public enum TableAlignment: Equatable, Sendable {
    case left, center, right
}

public struct TableBlock: Equatable, Sendable {
    public var range: NSRange
    public var header: [TableCell]
    public var rows: [[TableCell]]
    public var alignments: [TableAlignment]
}
