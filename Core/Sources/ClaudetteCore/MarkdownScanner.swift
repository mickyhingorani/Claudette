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
        walker.map.paragraphBreaks = paragraphBreaks(in: ns, map: walker.map)
        return walker.map.sorted().shifted(by: base)
    }

    /// The newline ending each line of text that's followed by a blank line, outside code and frontmatter.
    private static func paragraphBreaks(in ns: NSString, map: StyleMap) -> [NSRange] {
        let verbatim = map.spans.filter {
            if case .codeBlock = $0.kind { return true }
            return $0.kind == .frontmatter
        }.map(\.range)
        func isVerbatim(_ location: Int) -> Bool { verbatim.contains { NSLocationInRange(location, $0) } }
        func isBlank(_ line: NSRange) -> Bool {
            (0..<line.length).allSatisfy { [0x0A, 0x0D].contains(ns.character(at: line.location + $0)) }
        }
        var breaks: [NSRange] = []
        var previous: NSRange?
        var location = 0
        while location < ns.length {
            let line = ns.lineRange(for: NSRange(location: location, length: 0))
            if isBlank(line), let previous, !isBlank(previous), !isVerbatim(line.location) {
                let end = NSMaxRange(previous)
                var start = end - 1
                if start > previous.location, ns.character(at: start) == 0x0A, ns.character(at: start - 1) == 0x0D { start -= 1 }
                breaks.append(NSRange(location: start, length: end - start))
            }
            previous = line
            location = NSMaxRange(line)
        }
        return breaks
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
            let spaces = run(of: " ", at: range.location + hashes)
            // A lone # stays visible until a space makes it a heading in the writer's eyes.
            if hashes > 0, spaces > 0 {
                let length = min(hashes + spaces, range.length)
                hide(NSRange(location: range.location, length: length), owner: range, kind: .headingMark)
            }
            if hashes == 0 { hideSetextUnderline(of: range) }
        }
        descendInto(heading)
    }

    /// A heading written as a line of text underlined with === or ---: the underline,
    /// with the line break before it, shows only while the caret is in the heading.
    private mutating func hideSetextUnderline(of range: NSRange) {
        let lastLine = ns.lineRange(for: NSRange(location: NSMaxRange(range) - 1, length: 0))
        guard lastLine.location > range.location else { return }
        let underline = ns.substring(with: lastLine).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let mark = underline.first, mark == "=" || mark == "-", underline.allSatisfy({ $0 == mark }) else { return }
        var start = lastLine.location - 1
        if start > range.location, ns.character(at: start) == 0x0A, ns.character(at: start - 1) == 0x0D { start -= 1 }
        hide(NSRange(location: start, length: NSMaxRange(range) - start), owner: range)
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
        guard let range = nsRange(image) else { return }
        map.spans.append(StyledSpan(range: range, kind: .image))
        let line = ns.lineRange(for: NSRange(location: range.location, length: 0))
        let before = ns.substring(with: NSRange(location: line.location, length: range.location - line.location))
        let after = ns.substring(with: NSRange(location: NSMaxRange(range), length: NSMaxRange(line) - NSMaxRange(range)))
        let isBlock = before.allSatisfy(\.isWhitespace) && after.allSatisfy(\.isWhitespace) && quoteDepth == 0
        let alt = image.children.compactMap { ($0 as? Text)?.string }.joined()
        map.images.append(ImageInfo(range: range, source: image.source ?? "", alt: alt, isBlock: isBlock))
        if isBlock { hide(range, owner: range) }
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        guard let range = nsRange(thematicBreak) else { return }
        map.spans.append(StyledSpan(range: range, kind: .thematicBreak))
        hide(range, owner: range)
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        guard let range = nsRange(codeBlock) else { return }
        map.spans.append(StyledSpan(range: range, kind: .codeBlock))
        let (content, isClosed) = hideFences(of: range)
        map.codeBlocks.append(CodeBlockInfo(range: range, contentRange: content, language: codeBlock.language, isClosed: isClosed))
    }

    /// Hides a block's fence lines and returns the range of the code between them.
    /// A block with no closing fence keeps its opening fence visible, to show it's still open.
    private mutating func hideFences(of range: NSRange) -> (content: NSRange, isClosed: Bool) {
        let firstLine = ns.lineRange(for: NSRange(location: range.location, length: 0))
        guard let fence = fenceCharacter(onLine: firstLine) else { return (range, true) }
        let open = NSRange(location: range.location, length: min(NSMaxRange(firstLine), NSMaxRange(range)) - range.location)
        let contentStart = NSMaxRange(open)

        let lastLine = ns.lineRange(for: NSRange(location: NSMaxRange(range) - 1, length: 0))
        guard lastLine.location >= NSMaxRange(firstLine), fenceCharacter(onLine: lastLine) == fence else {
            return (NSRange(location: contentStart, length: NSMaxRange(range) - contentStart), false)
        }
        hide(open, owner: range, kind: .fenceLine)
        var closeStart = lastLine.location
        // Take the newline before the fence too, so no empty line is left behind.
        if closeStart > contentStart {
            closeStart -= 1
            if closeStart > contentStart, ns.character(at: closeStart) == 0x0A, ns.character(at: closeStart - 1) == 0x0D {
                closeStart -= 1
            }
        }
        hide(NSRange(location: closeStart, length: NSMaxRange(range) - closeStart), owner: range, kind: .fenceLine)
        return (NSRange(location: contentStart, length: closeStart - contentStart), true)
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
            map.taskBoxes.append(TaskBox(range: box, isChecked: checkbox == .checked, owner: owner))
            // The glyph takes the marker's first character: hidden text at the start
            // of a line would make it lay out like a wrapped line.
            map.substitutions.append(Substitution(range: owner, glyph: checkbox == .checked ? "☑" : "☐", owner: owner))
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
            let firstContent = hideQuotePrefixes(in: range)
            scanCallout(in: range, contentStart: firstContent)
        }
        quoteDepth += 1
        descendInto(blockQuote)
        quoteDepth -= 1
    }

    /// A quote whose first line starts with `[!NOTE]` or another kind becomes a callout.
    private mutating func scanCallout(in range: NSRange, contentStart: Int) {
        let line = ns.lineRange(for: NSRange(location: range.location, length: 0))
        var contentEnd = NSMaxRange(line)
        while contentEnd > contentStart, isNewline(ns.character(at: contentEnd - 1)) { contentEnd -= 1 }
        let content = ns.substring(with: NSRange(location: contentStart, length: contentEnd - contentStart))
        guard content.hasPrefix("[!"), let close = content.firstIndex(of: "]") else { return }
        let name = content[content.index(content.startIndex, offsetBy: 2)..<close].lowercased()
        guard let kind = CalloutKind(rawValue: name) else { return }
        let markerLength = (String(content[...close]) as NSString).length
        let rest = String(content[content.index(after: close)...])
        let spaces = (String(rest.prefix { $0 == " " }) as NSString).length
        let titleText = rest.trimmingCharacters(in: .whitespaces)
        let titleStart = contentStart + markerLength + spaces
        let title = titleText.isEmpty ? nil : NSRange(location: titleStart, length: (titleText as NSString).length)
        let marker = NSRange(location: contentStart, length: title == nil ? markerLength : markerLength + spaces)
        hide(marker, owner: NSRange(location: line.location, length: contentEnd - line.location))
        map.callouts.append(Callout(range: range, kind: kind, marker: marker, title: title))
    }

    /// Hides each line's `>` prefix, and returns where the first line's text starts.
    @discardableResult
    private mutating func hideQuotePrefixes(in range: NSRange) -> Int {
        var firstContent: Int?
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
            if firstContent == nil { firstContent = prefixEnd }
            lineStart = NSMaxRange(line)
        }
        return firstContent ?? range.location
    }

    mutating func visitTable(_ table: Markdown.Table) {
        guard let range = nsRange(table), let block = TableBlock.parse(ns, range: range) else { return }
        map.tables.append(block)
        map.spans.append(StyledSpan(range: block.delimiterLine, kind: .syntax))
        // The parser folds a paragraph directly above a table into the table, so scan it here.
        let leadLength = block.range.location - range.location
        if leadLength > 0 {
            let lead = NSRange(location: range.location, length: leadLength)
            map.merge(MarkdownScanner.scan(ns.substring(with: lead)).shifted(by: lead.location))
        }
    }
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
        map.taskBoxes = taskBoxes.map { TaskBox(range: shift($0.range), isChecked: $0.isChecked, owner: shift($0.owner)) }
        map.tables = tables.map { $0.shifted(by: base) }
        map.paragraphBreaks = paragraphBreaks.map(shift)
        map.images = images.map { ImageInfo(range: shift($0.range), source: $0.source, alt: $0.alt, isBlock: $0.isBlock) }
        map.callouts = callouts.map { Callout(range: shift($0.range), kind: $0.kind, marker: shift($0.marker), title: $0.title.map(shift)) }
        map.codeBlocks = codeBlocks.map {
            CodeBlockInfo(range: shift($0.range), contentRange: shift($0.contentRange), language: $0.language, isClosed: $0.isClosed)
        }
        return map
    }
}
