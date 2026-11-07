import Foundation
import Markdown

/// Turns document text into a `StyleMap`. All ranges are UTF-16 offsets into `text`.
public enum MarkdownScanner {
    public static func scan(_ text: String) -> StyleMap {
        var source = text
        var base = 0
        if source.unicodeScalars.first?.value == 0xFEFF {
            source = String(String.UnicodeScalarView(source.unicodeScalars.dropFirst()))
            base = 1
        }
        let ns = source as NSString
        var map = StyleMap()
        var parseText = source
        if let frontmatter = frontmatterLines(in: ns) {
            map.spans.append(StyledSpan(range: frontmatter.range, kind: .frontmatter))
            // Blank the frontmatter so the parser skips it and line numbers still match.
            parseText = String(repeating: "\n", count: frontmatter.lineCount)
                + ns.substring(from: frontmatter.endOfLastLine)
        }
        var walker = Walker(ns: ns, lines: LineIndex(source), map: map)
        walker.visit(Document(parsing: parseText))
        return walker.map.sorted().shifted(by: base)
    }

    private static func frontmatterLines(in ns: NSString) -> (range: NSRange, lineCount: Int, endOfLastLine: Int)? {
        var location = 0
        var lineCount = 0
        while location < ns.length {
            let line = ns.lineRange(for: NSRange(location: location, length: 0))
            let content = ns.substring(with: line).trimmingCharacters(in: .newlines)
            lineCount += 1
            if lineCount == 1 {
                guard content == "---" else { return nil }
            } else if content == "---" || content == "..." {
                let contentEnd = line.location + (content as NSString).length
                return (NSRange(location: 0, length: contentEnd), lineCount, NSMaxRange(line))
            }
            location = NSMaxRange(line)
        }
        return nil
    }
}

private struct Walker: MarkupWalker {
    let ns: NSString
    let lines: LineIndex
    var map: StyleMap
    var quoteDepth = 0

    private func nsRange(_ markup: Markup) -> NSRange? {
        guard let range = markup.range else { return nil }
        let start = lines.offset(line: range.lowerBound.line, utf8Column: range.lowerBound.column)
        var end = lines.offset(line: range.upperBound.line, utf8Column: range.upperBound.column)
        while end > start, isNewline(ns.character(at: end - 1)) { end -= 1 }
        return end >= start ? NSRange(location: start, length: end - start) : nil
    }

    private func isNewline(_ unit: unichar) -> Bool { unit == 0x0A || unit == 0x0D }

    private func char(_ offset: Int) -> Character? {
        guard offset >= 0, offset < ns.length, let scalar = Unicode.Scalar(ns.character(at: offset)) else { return nil }
        return Character(scalar)
    }

    private func run(of character: Character, at offset: Int) -> Int {
        var length = 0
        while char(offset + length) == character { length += 1 }
        return length
    }

    private mutating func hide(_ range: NSRange, owner: NSRange, kind: HiddenKind = .inline) {
        guard range.length > 0 else { return }
        map.hidden.append(HiddenRange(range: range, owner: owner, kind: kind))
    }

    /// Hides matching opening and closing delimiters, if the text there is what's expected.
    private mutating func hideDelimiters(_ range: NSRange, length: Int, kind: SpanKind, marks: Set<Character>) {
        map.spans.append(StyledSpan(range: range, kind: kind))
        guard range.length >= length * 2,
              let open = char(range.location), marks.contains(open),
              let close = char(NSMaxRange(range) - 1), marks.contains(close) else { return }
        hide(NSRange(location: range.location, length: length), owner: range)
        hide(NSRange(location: NSMaxRange(range) - length, length: length), owner: range)
    }

    mutating func visitStrong(_ strong: Strong) {
        if let range = nsRange(strong) {
            hideDelimiters(range, length: 2, kind: .strong, marks: ["*", "_"])
        }
        descendInto(strong)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        if let range = nsRange(emphasis) {
            hideDelimiters(range, length: 1, kind: .emphasis, marks: ["*", "_"])
        }
        descendInto(emphasis)
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        if let range = nsRange(strikethrough) {
            hideDelimiters(range, length: run(of: "~", at: range.location), kind: .strikethrough, marks: ["~"])
        }
        descendInto(strikethrough)
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        guard let range = nsRange(inlineCode) else { return }
        hideDelimiters(range, length: run(of: "`", at: range.location), kind: .inlineCode, marks: ["`"])
    }

    mutating func visitHeading(_ heading: Heading) {
        if let range = nsRange(heading) {
            map.spans.append(StyledSpan(range: range, kind: .heading(level: heading.level)))
            let hashes = run(of: "#", at: range.location)
            if hashes > 0 {
                let spaces = run(of: " ", at: range.location + hashes)
                let length = min(hashes + spaces, range.length)
                hide(NSRange(location: range.location, length: length), owner: range, kind: .headingMark)
            }
        }
        descendInto(heading)
    }

    mutating func visitLink(_ link: Link) {
        if let range = nsRange(link) {
            map.spans.append(StyledSpan(range: range, kind: .link(url: link.destination ?? "")))
            if char(range.location) == "[", let close = closingBracket(from: range.location, in: range) {
                hide(NSRange(location: range.location, length: 1), owner: range)
                hide(NSRange(location: close, length: NSMaxRange(range) - close), owner: range)
            }
        }
        descendInto(link)
    }

    private func closingBracket(from start: Int, in range: NSRange) -> Int? {
        var depth = 0
        var offset = start
        while offset < NSMaxRange(range) {
            switch char(offset) {
            case "\\": offset += 1
            case "[": depth += 1
            case "]":
                depth -= 1
                if depth == 0 { return offset }
            default: break
            }
            offset += 1
        }
        return nil
    }

    mutating func visitImage(_ image: Image) {
        if let range = nsRange(image) {
            map.spans.append(StyledSpan(range: range, kind: .image))
        }
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        guard let range = nsRange(thematicBreak) else { return }
        map.spans.append(StyledSpan(range: range, kind: .thematicBreak))
        hide(range, owner: range)
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        guard let range = nsRange(codeBlock) else { return }
        map.spans.append(StyledSpan(range: range, kind: .codeBlock))
        let firstLine = ns.lineRange(for: NSRange(location: range.location, length: 0))
        guard let fence = fenceCharacter(onLine: firstLine) else { return }
        let open = NSRange(location: range.location, length: min(NSMaxRange(firstLine), NSMaxRange(range)) - range.location)
        hide(open, owner: range, kind: .fenceLine)

        let lastLine = ns.lineRange(for: NSRange(location: NSMaxRange(range) - 1, length: 0))
        guard lastLine.location >= NSMaxRange(firstLine), fenceCharacter(onLine: lastLine) == fence else { return }
        var closeStart = lastLine.location
        // Take the newline before the fence too, so no empty line is left behind.
        if closeStart > NSMaxRange(open) {
            closeStart -= 1
            if closeStart > NSMaxRange(open), ns.character(at: closeStart) == 0x0A, ns.character(at: closeStart - 1) == 0x0D {
                closeStart -= 1
            }
        }
        hide(NSRange(location: closeStart, length: NSMaxRange(range) - closeStart), owner: range, kind: .fenceLine)
    }

    private func fenceCharacter(onLine line: NSRange) -> Character? {
        let trimmed = ns.substring(with: line).drop { $0 == " " || $0 == ">" }
        if trimmed.hasPrefix("```") { return "`" }
        if trimmed.hasPrefix("~~~") { return "~" }
        return nil
    }

    mutating func visitListItem(_ listItem: ListItem) {
        if let range = nsRange(listItem) {
            scanMarker(of: listItem, in: range)
        }
        descendInto(listItem)
    }

    private mutating func scanMarker(of listItem: ListItem, in range: NSRange) {
        let start = range.location
        var markerLength = 0
        var isBullet = false
        if let first = char(start), "-*+".contains(first) {
            markerLength = 1
            isBullet = true
        } else {
            let digits = (0..<10).prefix { char(start + $0)?.isNumber == true }.count
            guard digits > 0, let delimiter = char(start + digits), ".)".contains(delimiter) else { return }
            markerLength = digits + 1
        }

        if let checkbox = listItem.checkbox {
            let boxStart = start + markerLength + run(of: " ", at: start + markerLength)
            guard char(boxStart) == "[" else { return }
            let box = NSRange(location: boxStart, length: 3)
            let owner = NSRange(location: start, length: NSMaxRange(box) - start)
            map.spans.append(StyledSpan(range: owner, kind: .listItem))
            map.taskBoxes.append(TaskBox(range: box, isChecked: checkbox == .checked))
            hide(NSRange(location: start, length: boxStart - start), owner: owner)
            map.substitutions.append(Substitution(range: box, glyph: checkbox == .checked ? "☑" : "☐", owner: owner))
            return
        }

        let marker = NSRange(location: start, length: markerLength)
        map.spans.append(StyledSpan(range: marker, kind: .listItem))
        if isBullet {
            map.substitutions.append(Substitution(range: marker, glyph: "•", owner: marker))
        }
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        if quoteDepth == 0, let range = nsRange(blockQuote) {
            map.spans.append(StyledSpan(range: range, kind: .blockquote))
            hideQuotePrefixes(in: range)
        }
        quoteDepth += 1
        descendInto(blockQuote)
        quoteDepth -= 1
    }

    private mutating func hideQuotePrefixes(in range: NSRange) {
        var lineStart = range.location
        while lineStart < NSMaxRange(range) {
            let line = ns.lineRange(for: NSRange(location: lineStart, length: 0))
            var offset = lineStart
            var prefixEnd = lineStart
            while true {
                offset += run(of: " ", at: offset)
                guard char(offset) == ">" else { break }
                offset += 1
                if char(offset) == " " { offset += 1 }
                prefixEnd = offset
            }
            var contentEnd = NSMaxRange(line)
            while contentEnd > line.location, isNewline(ns.character(at: contentEnd - 1)) { contentEnd -= 1 }
            let owner = NSRange(location: lineStart, length: contentEnd - lineStart)
            hide(NSRange(location: lineStart, length: prefixEnd - lineStart), owner: owner)
            lineStart = NSMaxRange(line)
        }
    }

    mutating func visitTable(_ table: Markdown.Table) {}
}

private extension StyleMap {
    func sorted() -> StyleMap {
        var map = self
        map.hidden.sort { $0.range.location < $1.range.location }
        map.substitutions.sort { $0.range.location < $1.range.location }
        return map
    }

    func shifted(by base: Int) -> StyleMap {
        guard base != 0 else { return self }
        func shift(_ range: NSRange) -> NSRange { NSRange(location: range.location + base, length: range.length) }
        var map = self
        map.spans = spans.map { StyledSpan(range: shift($0.range), kind: $0.kind) }
        map.hidden = hidden.map { HiddenRange(range: shift($0.range), owner: shift($0.owner), kind: $0.kind) }
        map.substitutions = substitutions.map { Substitution(range: shift($0.range), glyph: $0.glyph, owner: shift($0.owner)) }
        map.taskBoxes = taskBoxes.map { TaskBox(range: shift($0.range), isChecked: $0.isChecked) }
        map.tables = tables.map { table in
            func shiftCell(_ cell: TableCell) -> TableCell { TableCell(textRange: shift(cell.textRange), text: cell.text) }
            return TableBlock(range: shift(table.range), header: table.header.map(shiftCell),
                              rows: table.rows.map { $0.map(shiftCell) }, alignments: table.alignments)
        }
        return map
    }
}
