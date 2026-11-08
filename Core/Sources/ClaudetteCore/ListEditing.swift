import Foundation

/// What Return, Tab and Shift-Tab do on a list item: continue the list with the next bullet,
/// number or checkbox, end it on an empty item, and nest or un-nest items.
public enum ListEditing {
    /// A list item's line, taken apart.
    struct Item {
        var line: NSRange
        var contentEnd: Int
        var indent: String
        var bullet: Character?
        var number: Int?
        var delimiter: Character?
        var numberRange: NSRange
        var hasBox: Bool
        var contentStart: Int

        /// A bullet, or a number's digits and its "." or ")".
        var markerWidth: Int { bullet != nil ? 1 : numberRange.length + 1 }
        /// How far a nested item sits in: past this item's marker and its space.
        var nestWidth: Int { markerWidth + 1 }
    }

    static func item(at location: Int, in ns: NSString) -> Item? {
        let line = ns.lineRange(for: NSRange(location: min(location, ns.length), length: 0))
        var contentEnd = NSMaxRange(line)
        while contentEnd > line.location, [0x0A, 0x0D].contains(ns.character(at: contentEnd - 1)) { contentEnd -= 1 }
        let text = ns.substring(with: NSRange(location: line.location, length: contentEnd - line.location)) as NSString
        var index = 0
        while index < text.length, [0x20, 0x09].contains(text.character(at: index)) { index += 1 }
        let indent = text.substring(to: index)
        guard index < text.length else { return nil }
        var bullet: Character?
        var number: Int?
        var delimiter: Character?
        let markerStart = index
        let first = Character(UnicodeScalar(text.character(at: index))!)
        if "-*+".contains(first) {
            bullet = first
            index += 1
        } else {
            while index < text.length, index - markerStart < 9, (0x30...0x39).contains(text.character(at: index)) { index += 1 }
            guard index > markerStart, index < text.length,
                  let mark = UnicodeScalar(text.character(at: index)).map(Character.init), mark == "." || mark == ")" else { return nil }
            number = Int(text.substring(with: NSRange(location: markerStart, length: index - markerStart)))
            delimiter = mark
            index += 1
        }
        // The marker must end the line or be followed by a space: "-a" and "---" aren't items.
        guard index == text.length || text.character(at: index) == 0x20 else { return nil }
        while index < text.length, text.character(at: index) == 0x20 { index += 1 }
        var hasBox = false
        if index + 3 <= text.length {
            let box = text.substring(with: NSRange(location: index, length: 3))
            if ["[ ]", "[x]", "[X]"].contains(box), index + 3 == text.length || text.character(at: index + 3) == 0x20 {
                hasBox = true
                index += 3
                while index < text.length, text.character(at: index) == 0x20 { index += 1 }
            }
        }
        // A bullet's range is the bullet itself; a number's is its digits.
        let numberRange = NSRange(location: line.location + markerStart, length: number == nil ? 1 : numberLength(text, from: markerStart))
        return Item(line: line, contentEnd: contentEnd, indent: indent, bullet: bullet, number: number, delimiter: delimiter,
                    numberRange: numberRange, hasBox: hasBox, contentStart: line.location + index)
    }

    private static func numberLength(_ text: NSString, from start: Int) -> Int {
        var end = start
        while end < text.length, (0x30...0x39).contains(text.character(at: end)) { end += 1 }
        return end - start
    }

    /// Return on a list item: the next item, or the end of the list if this one is empty.
    /// Nil when the caret isn't in a list item's text.
    public static func returnEdits(in text: String, selection: NSRange) -> (edits: [TextEdit], selection: NSRange)? {
        guard selection.length == 0 else { return nil }
        let ns = text as NSString
        guard let item = item(at: selection.location, in: ns), selection.location >= item.contentStart else { return nil }
        let newline = text.contains("\r\n") ? "\r\n" : "\n"
        let content = ns.substring(with: NSRange(location: item.contentStart, length: item.contentEnd - item.contentStart))

        if content.allSatisfy(\.isWhitespace) {
            if !item.indent.isEmpty {
                // An empty nested item moves out a level.
                let removed = min((item.indent as NSString).length, item.nestWidth)
                return ([TextEdit(range: NSRange(location: item.line.location, length: removed), replacement: "")],
                        NSRange(location: selection.location - removed, length: 0))
            }
            // An empty top-level item ends the list, and what follows is a new paragraph.
            let lineText = NSRange(location: item.line.location, length: item.contentEnd - item.line.location)
            return ([TextEdit(range: lineText, replacement: newline)],
                    NSRange(location: item.line.location + (newline as NSString).length, length: 0))
        }

        let marker: String
        if let bullet = item.bullet {
            marker = String(bullet)
        } else {
            marker = "\((item.number ?? 0) + 1)\(item.delimiter ?? ".")"
        }
        let insertion = newline + item.indent + marker + " " + (item.hasBox ? "[ ] " : "")
        var edits = [TextEdit(range: NSRange(location: selection.location, length: 0), replacement: insertion)]
        if let number = item.number {
            edits += renumbering(after: item, startingAt: number + 2, in: ns)
        }
        return (edits, NSRange(location: selection.location + (insertion as NSString).length, length: 0))
    }

    /// Numbers the rest of a numbered list on from `next`, skipping nested lines.
    private static func renumbering(after item: Item, startingAt next: Int, in ns: NSString) -> [TextEdit] {
        var edits: [TextEdit] = []
        var expected = next
        var location = NSMaxRange(item.line)
        let indentLength = (item.indent as NSString).length
        while location < ns.length {
            let line = ns.lineRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(line)
            let lineText = ns.substring(with: line)
            if lineText.allSatisfy(\.isWhitespace) { continue }
            let leading = lineText.prefix { $0 == " " || $0 == "\t" }.count
            if leading > indentLength { continue }
            guard leading == indentLength, let sibling = self.item(at: line.location, in: ns),
                  sibling.number != nil, sibling.delimiter == item.delimiter else { break }
            if sibling.number != expected {
                edits.append(TextEdit(range: sibling.numberRange, replacement: String(expected)))
            }
            expected += 1
        }
        return edits
    }

    /// Tab nests a list item one level; Shift-Tab (`outdent`) brings it back out.
    /// Nil when the caret isn't on a list item, or it can't move further out.
    public static func indentEdits(in text: String, selection: NSRange, outdent: Bool) -> (edits: [TextEdit], selection: NSRange)? {
        let ns = text as NSString
        guard let item = item(at: selection.location, in: ns) else { return nil }
        if outdent {
            let removed = min((item.indent as NSString).length, item.nestWidth)
            guard removed > 0 else { return nil }
            return ([TextEdit(range: NSRange(location: item.line.location, length: removed), replacement: "")],
                    NSRange(location: max(item.line.location, selection.location - removed), length: selection.length))
        }
        let spaces = String(repeating: " ", count: item.nestWidth)
        return ([TextEdit(range: NSRange(location: item.line.location, length: 0), replacement: spaces)],
                NSRange(location: selection.location + item.nestWidth, length: selection.length))
    }
}
