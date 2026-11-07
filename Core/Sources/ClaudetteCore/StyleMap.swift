import Foundation

public enum SpanKind: Equatable, Sendable {
    case heading(level: Int)
    case strong
    case emphasis
    case strikethrough
    case inlineCode
    case codeBlock
    case link(url: String)
    case blockquote
    case listItem
    case thematicBreak
    case frontmatter
    case syntax
    case image
}

public struct StyledSpan: Equatable, Sendable {
    public var range: NSRange
    public var kind: SpanKind
}

public enum HiddenKind: Equatable, Sendable {
    case inline
    case headingMark
    case fenceLine
}

/// Syntax hidden in the formatted view. `owner` is the text whose cursor presence reveals it.
public struct HiddenRange: Equatable, Sendable {
    public var range: NSRange
    public var owner: NSRange
    public var kind: HiddenKind
}

/// Syntax drawn as a different glyph in the formatted view, such as a bullet.
public struct Substitution: Equatable, Sendable {
    public var range: NSRange
    public var glyph: String
    public var owner: NSRange
}

/// `range` is the `[ ]` text. `owner` is the whole marker, including the list dash.
public struct TaskBox: Equatable, Sendable {
    public var range: NSRange
    public var isChecked: Bool
    public var owner: NSRange
}

public struct StyleMap: Equatable, Sendable {
    public var spans: [StyledSpan] = []
    public var hidden: [HiddenRange] = []
    public var substitutions: [Substitution] = []
    public var taskBoxes: [TaskBox] = []
    public var tables: [TableBlock] = []

    public init() {}
}
