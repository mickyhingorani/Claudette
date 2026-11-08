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

/// An image. A block image is alone on its line, and the formatted view shows the picture.
public struct ImageInfo: Equatable, Sendable {
    public var range: NSRange
    public var source: String
    public var alt: String
    public var isBlock: Bool
}

public enum CalloutKind: String, Equatable, Sendable, CaseIterable {
    case note, tip, important, warning, caution
}

/// A quote that starts with a marker like `[!NOTE]`. `title` is any text after the marker.
public struct Callout: Equatable, Sendable {
    public var range: NSRange
    public var kind: CalloutKind
    public var marker: NSRange
    public var title: NSRange?
}

/// A code block. `contentRange` is the code without its fences.
public struct CodeBlockInfo: Equatable, Sendable {
    public var range: NSRange
    public var contentRange: NSRange
    public var language: String?
    /// False when a fenced block has no closing fence, so it runs on to the end of the document.
    public var isClosed: Bool
}

public struct StyleMap: Equatable, Sendable {
    public var spans: [StyledSpan] = []
    public var hidden: [HiddenRange] = []
    public var substitutions: [Substitution] = []
    public var taskBoxes: [TaskBox] = []
    public var tables: [TableBlock] = []
    public var codeBlocks: [CodeBlockInfo] = []
    /// Newlines that end a paragraph because a blank line follows. The formatted view hides
    /// them, and the blank line after, and shows a gap in their place.
    public var paragraphBreaks: [NSRange] = []
    public var images: [ImageInfo] = []
    public var callouts: [Callout] = []

    /// Adds another map's results. Every field is listed here, so a new one can't be missed.
    mutating func merge(_ other: StyleMap) {
        spans += other.spans
        hidden += other.hidden
        substitutions += other.substitutions
        taskBoxes += other.taskBoxes
        tables += other.tables
        codeBlocks += other.codeBlocks
        paragraphBreaks += other.paragraphBreaks
        images += other.images
        callouts += other.callouts
    }

    public init() {}
}
