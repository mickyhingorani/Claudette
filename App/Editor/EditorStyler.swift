import AppKit
import ClaudetteCore

extension NSAttributedString.Key {
    static let claudetteURL = NSAttributedString.Key("claudetteURL")
}

/// Turns a `StyleMap` into text attributes and the set of hidden characters.
final class EditorStyler {
    private(set) var map = StyleMap()
    var theme = Theme.ink
    var mode = ViewMode.formatted

    func rescan(_ text: String) {
        map = MarkdownScanner.scan(text)
    }

    private var baseFont: NSFont { mode == .formatted ? theme.bodyFont : theme.monoFont }

    private var baseParagraph: NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = mode == .formatted ? 1.3 : 1.2
        style.paragraphSpacing = mode == .formatted ? 8 : 0
        return style
    }

    var typingAttributes: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: theme.text, .paragraphStyle: baseParagraph]
    }

    func apply(to storage: NSTextStorage) {
        let all = NSRange(location: 0, length: storage.length)
        guard all.length > 0 else { return }
        storage.setAttributes(typingAttributes, range: all)
        for span in map.spans {
            style(span, in: storage)
        }
        if mode == .formatted { tightenBlankLines(in: storage) }
        if mode == .markdown {
            for range in map.hidden.map(\.range) + map.substitutions.map(\.range) {
                storage.addAttribute(.foregroundColor, value: theme.accent, range: range)
            }
        } else {
            for substitution in map.substitutions where substitution.range.length > 1 {
                let size = baseFont.pointSize
                let font = NSFont(name: "Apple Symbols", size: size * 1.15) ?? baseFont
                storage.addAttribute(.font, value: font, range: substitution.range)
                storage.addAttribute(.foregroundColor, value: theme.accent, range: substitution.range)
            }
            if theme.keepsHeadingMarks {
                for mark in map.hidden where mark.kind == .headingMark {
                    storage.addAttribute(.foregroundColor, value: theme.dim, range: mark.range)
                }
            }
        }
    }

    /// Paragraphs already have their own spacing, so blank lines stay small.
    private func tightenBlankLines(in storage: NSTextStorage) {
        let text = storage.string as NSString
        let code = map.spans.filter { $0.kind == .codeBlock }.map(\.range)
        func style(height: CGFloat) -> NSParagraphStyle {
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = height
            paragraph.maximumLineHeight = height
            return paragraph
        }
        let small = style(height: 8)
        let roomy = style(height: 22)
        var location = 0
        while location < text.length {
            let line = text.lineRange(for: NSRange(location: location, length: 0))
            let isBlank = text.substring(with: line).allSatisfy(\.isNewline)
            if isBlank, !code.contains(where: { NSLocationInRange(line.location, $0) }) {
                // A code block's background reaches past its text, so give it more room.
                let touchesCode = code.contains { $0.location == NSMaxRange(line) || NSMaxRange($0) + newlineLength(in: text, at: NSMaxRange($0)) == line.location }
                storage.addAttribute(.paragraphStyle, value: touchesCode ? roomy : small, range: line)
            }
            location = NSMaxRange(line)
        }
    }

    private func newlineLength(in text: NSString, at location: Int) -> Int {
        guard location < text.length else { return 0 }
        if text.character(at: location) == 0x0D, location + 1 < text.length, text.character(at: location + 1) == 0x0A { return 2 }
        return 1
    }

    private func style(_ span: StyledSpan, in storage: NSTextStorage) {
        let range = span.range
        guard NSMaxRange(range) <= storage.length else { return }
        switch span.kind {
        case .heading(let level):
            if mode == .formatted {
                let scales: [CGFloat] = [1.7, 1.35, 1.15]
                let scale = level <= 3 ? scales[level - 1] : 1
                let size = (baseFont.pointSize * scale).rounded()
                let sized = NSFontManager.shared.convert(baseFont, toSize: size)
                storage.addAttribute(.font, value: NSFontManager.shared.convert(sized, toHaveTrait: .boldFontMask), range: range)
                let paragraph = baseParagraph
                paragraph.paragraphSpacingBefore = level == 1 ? 8 : 14
                paragraph.paragraphSpacing = 6
                storage.addAttribute(.paragraphStyle, value: paragraph, range: range)
            } else {
                addTrait(.boldFontMask, in: range, of: storage)
            }
        case .strong:
            addTrait(.boldFontMask, in: range, of: storage)
        case .emphasis:
            addTrait(.italicFontMask, in: range, of: storage)
        case .strikethrough:
            if mode == .markdown {
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
        case .inlineCode:
            if mode == .formatted {
                storage.addAttribute(.font, value: monoScaled, range: range)
            }
        case .codeBlock:
            storage.addAttribute(.font, value: monoScaled, range: range)
            if mode == .formatted {
                let paragraph = baseParagraph
                paragraph.lineHeightMultiple = 1.2
                paragraph.paragraphSpacing = 0
                paragraph.firstLineHeadIndent = 14
                paragraph.headIndent = 14
                paragraph.tailIndent = -14
                storage.addAttribute(.paragraphStyle, value: paragraph, range: range)
            }
        case .link(let url):
            storage.addAttribute(.claudetteURL, value: url, range: range)
            storage.addAttribute(.foregroundColor, value: theme.accent, range: range)
        case .blockquote:
            storage.addAttribute(.foregroundColor, value: theme.soft, range: range)
            if mode == .formatted {
                let paragraph = baseParagraph
                paragraph.firstLineHeadIndent = 18
                paragraph.headIndent = 18
                storage.addAttribute(.paragraphStyle, value: paragraph, range: range)
            }
        case .listItem:
            storage.addAttribute(.foregroundColor, value: theme.accent, range: range)
            if mode == .formatted { hangListLine(markerRange: range, in: storage) }
        case .frontmatter:
            storage.addAttribute(.font, value: monoScaled, range: range)
            storage.addAttribute(.foregroundColor, value: theme.dim, range: range)
        case .thematicBreak, .syntax, .image:
            storage.addAttribute(.foregroundColor, value: theme.dim, range: range)
        }
    }

    /// The parts of a span that aren't its own hidden syntax. Line decorations must stop
    /// at hidden text: one that runs into it can spread across the whole line.
    private func visibleParts(of range: NSRange) -> [NSRange] {
        var parts = IndexSet(integersIn: range.location..<NSMaxRange(range))
        for item in map.hidden where item.owner == range {
            parts.remove(integersIn: item.range.location..<NSMaxRange(item.range))
        }
        return parts.rangeView.map { NSRange(location: $0.lowerBound, length: $0.count) }
    }

    private var monoScaled: NSFont { NSFontManager.shared.convert(theme.monoFont, toSize: (baseFont.pointSize * 0.88).rounded()) }

    private func addTrait(_ trait: NSFontTraitMask, in range: NSRange, of storage: NSTextStorage) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            guard let font = value as? NSFont else { return }
            storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: subrange)
        }
    }

    /// Lines up wrapped lines of a list item with its text.
    private func hangListLine(markerRange: NSRange, in storage: NSTextStorage) {
        let text = storage.string as NSString
        let line = text.lineRange(for: NSRange(location: markerRange.location, length: 0))
        let prefix = text.substring(with: NSRange(location: line.location, length: NSMaxRange(markerRange) - line.location)) + " "
        let width = (prefix as NSString).size(withAttributes: [.font: baseFont]).width
        let paragraph = baseParagraph
        paragraph.headIndent = width
        paragraph.paragraphSpacing = 3
        storage.addAttribute(.paragraphStyle, value: paragraph, range: line)
    }

    /// What's hidden or swapped, given where the selection is.
    func display(selection: NSRange) -> (hidden: IndexSet, substitutions: [Int: Character]) {
        guard mode == .formatted else { return (IndexSet(), [:]) }
        var hidden = IndexSet()
        var substitutions: [Int: Character] = [:]
        func touches(_ owner: NSRange) -> Bool {
            selection.location <= NSMaxRange(owner) && NSMaxRange(selection) >= owner.location
        }
        for item in map.hidden where !touches(item.owner) {
            if item.kind == .headingMark && theme.keepsHeadingMarks { continue }
            hidden.insert(integersIn: item.range.location..<NSMaxRange(item.range))
        }
        for item in map.substitutions where !touches(item.owner) {
            if let glyph = item.glyph.first { substitutions[item.range.location] = glyph }
            if item.range.length > 1 {
                hidden.insert(integersIn: (item.range.location + 1)..<NSMaxRange(item.range))
            }
        }
        for table in map.tables {
            hidden.insert(integersIn: table.range.location..<NSMaxRange(table.range))
        }
        return (hidden, substitutions)
    }

    var decorations: EditorDecorations {
        guard mode == .formatted else { return EditorDecorations() }
        var result = EditorDecorations()
        for span in map.spans {
            switch span.kind {
            case .codeBlock: result.codeBlocks.append(span.range)
            case .blockquote: result.quotes.append(span.range)
            case .thematicBreak: result.rules.append(span.range)
            case .link: result.underlines.append(contentsOf: visibleParts(of: span.range))
            case .strikethrough: result.strikes.append(contentsOf: visibleParts(of: span.range))
            case .inlineCode:
                let marks = map.hidden.filter { $0.owner == span.range }.reduce(0) { $0 + $1.range.length } / 2
                result.chips.append(NSRange(location: span.range.location + marks, length: span.range.length - marks * 2))
            default: break
            }
        }
        return result
    }
}
