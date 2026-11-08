import Foundation

/// One example in the Markdown guide. Its text is `before + placeholder + after`, and the
/// placeholder is what gets selected after inserting, ready to type over.
public struct GuideEntry: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    /// Block entries start on a line of their own; inline ones go at the caret.
    public let isBlock: Bool
    public let before: String
    public let placeholder: String
    public let after: String
    public let shortcut: String?

    public var markdown: String { before + placeholder + after }

    init(_ id: String, _ title: String, block: Bool = false, _ before: String, _ placeholder: String, _ after: String = "", shortcut: String? = nil) {
        self.id = id
        self.title = title
        self.isBlock = block
        self.before = before
        self.placeholder = placeholder
        self.after = after
        self.shortcut = shortcut
    }
}

public struct GuideSection: Equatable, Sendable, Identifiable {
    public let title: String
    public let entries: [GuideEntry]
    public var id: String { title }
}

/// A cheat sheet of Markdown syntax, and how to insert each example into a document.
public enum MarkdownGuide {
    public static let sections: [GuideSection] = [
        GuideSection(title: "Headings", entries: [
            GuideEntry("heading1", "Heading 1", block: true, "# ", "Heading"),
            GuideEntry("heading2", "Heading 2", block: true, "## ", "Heading"),
            GuideEntry("heading3", "Heading 3", block: true, "### ", "Heading"),
        ]),
        GuideSection(title: "Text", entries: [
            GuideEntry("bold", "Bold", "**", "bold", "**", shortcut: "⌘B"),
            GuideEntry("italic", "Italic", "*", "italic", "*", shortcut: "⌘I"),
            GuideEntry("strikethrough", "Strikethrough", "~~", "struck", "~~"),
            GuideEntry("inlineCode", "Code", "`", "code", "`"),
        ]),
        GuideSection(title: "Links and images", entries: [
            GuideEntry("link", "Link", "[", "link text", "](https://example.com)", shortcut: "⌘K"),
            GuideEntry("image", "Image", block: true, "![", "description", "](picture.png)"),
        ]),
        GuideSection(title: "Lists", entries: [
            GuideEntry("bullet", "Bullet list", block: true, "- ", "Item"),
            GuideEntry("numbered", "Numbered list", block: true, "1. ", "Item"),
            GuideEntry("task", "Checkbox", block: true, "- [ ] ", "Task"),
        ]),
        GuideSection(title: "Blocks", entries: [
            GuideEntry("quote", "Quote", block: true, "> ", "Quote"),
            GuideEntry("callout", "Callout", block: true, "> [!NOTE]\n> ", "Note text"),
            GuideEntry("codeBlock", "Code block", block: true, "```js\n", "code", "\n```"),
            GuideEntry("table", "Table", block: true, "| ", "Column", " | Column |\n|---|---|\n| Cell | Cell |"),
            GuideEntry("rule", "Divider", block: true, "---", ""),
        ]),
    ]

    /// The edit that inserts an entry, and what to select afterwards.
    public static func insertion(of entry: GuideEntry, in text: String, selection: NSRange) -> (edit: TextEdit, selection: NSRange) {
        let ns = text as NSString
        let newline = text.contains("\r\n") ? "\r\n" : "\n"
        func lines(_ part: String) -> String { part.replacingOccurrences(of: "\n", with: newline) }
        let before = lines(entry.before)
        let after = lines(entry.after)
        let selected = selection.length > 0 ? ns.substring(with: selection) : ""

        guard entry.isBlock else {
            let wraps = !selected.isEmpty && !selected.contains(where: \.isNewline)
            let middle = wraps ? selected : entry.placeholder
            let edit = TextEdit(range: wraps ? selection : NSRange(location: selection.location, length: 0), replacement: before + middle + after)
            return (edit, NSRange(location: selection.location + (before as NSString).length, length: (middle as NSString).length))
        }

        // A block goes on its own line: right here on an empty line, or as a new paragraph below.
        let line = ns.lineRange(for: NSRange(location: selection.location, length: 0))
        var contentEnd = NSMaxRange(line)
        while contentEnd > line.location, [0x0A, 0x0D].contains(ns.character(at: contentEnd - 1)) { contentEnd -= 1 }
        let lineIsEmpty = ns.substring(with: NSRange(location: line.location, length: contentEnd - line.location))
            .allSatisfy(\.isWhitespace)
        let location = lineIsEmpty ? line.location : contentEnd
        let lead = lineIsEmpty ? "" : newline + newline
        let removed = lineIsEmpty ? contentEnd - line.location : 0
        let edit = TextEdit(range: NSRange(location: location, length: removed), replacement: lead + before + entry.placeholder + after)
        let start = location + (lead as NSString).length + (before as NSString).length
        return (edit, NSRange(location: start, length: (entry.placeholder as NSString).length))
    }
}
