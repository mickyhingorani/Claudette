import AppKit
import ClaudetteCore

extension NSAttributedString.Key {
    static let claudetteURL = NSAttributedString.Key("claudetteURL")
}

@MainActor
/// Turns a `StyleMap` into text attributes and the set of hidden characters.
final class EditorStyler {
    private(set) var map = StyleMap()
    var theme = Theme.default
    var mode = ViewMode.formatted

    /// Hidden syntax by the text that owns it, built once per scan: looking it up for each
    /// link and code span by searching the whole list was slow in long documents.
    private var hiddenByOwner: [NSRange: [HiddenRange]] = [:]

    func rescan(_ text: String) {
        map = MarkdownScanner.scan(text)
        hiddenByOwner = Dictionary(grouping: map.hidden, by: \.owner)
    }

    private var baseFont: NSFont { mode == .formatted ? theme.bodyFont : theme.monoFont }

    private var baseParagraph: NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = mode == .formatted ? 1.3 : 1.2
        return style
    }

    var emptyLineFont: NSFont { baseFont }

    /// The space shown between paragraphs in place of the blank line: half a line.
    var paragraphGap: CGFloat { ((baseFont.ascender - baseFont.descender) * baseParagraph.lineHeightMultiple / 2).rounded() }

    var typingAttributes: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: theme.text, .paragraphStyle: baseParagraph]
    }

    /// Styles the text, changing only attributes that differ from what's there. Setting every
    /// attribute again would make the whole document lay out again on every keystroke.
    func apply(to storage: NSTextStorage) {
        let styled = NSMutableAttributedString(string: storage.string)
        apply(toScratch: styled)
        let length = storage.length
        var location = 0
        while location < length {
            var run = NSRange()
            let wanted = styled.attributes(at: location, longestEffectiveRange: &run, in: NSRange(location: location, length: length - location))
            storage.enumerateAttributes(in: run) { current, part, _ in
                if !(current as NSDictionary).isEqual(to: wanted) { storage.setAttributes(wanted, range: part) }
            }
            location = NSMaxRange(run)
        }
    }

    /// Styles text from scratch: every attribute is set.
    func apply(toScratch storage: NSMutableAttributedString) {
        let all = NSRange(location: 0, length: storage.length)
        guard all.length > 0 else { return }
        storage.setAttributes(typingAttributes, range: all)
        for span in map.spans {
            style(span, in: storage)
        }
        if mode == .formatted { dimCheckedTasks(in: storage) }
        colorCode(in: storage)
        keepOperatorsAsTyped(in: storage)
        if mode == .markdown {
            for range in map.hidden.map(\.range) + map.substitutions.map(\.range) {
                storage.addAttribute(.foregroundColor, value: theme.accent, range: range)
            }
        } else {
            for substitution in map.substitutions where substitution.range.length > 1 {
                let size = baseFont.pointSize
                let font = NSFont(name: "Apple Symbols", size: size * 1.15) ?? baseFont
                storage.addAttribute(.font, value: font, range: substitution.range)
                storage.addAttribute(.foregroundColor, value: theme.palette.check, range: substitution.range)
            }
        }
    }

    private func style(_ span: StyledSpan, in storage: NSMutableAttributedString) {
        let range = span.range
        guard NSMaxRange(range) <= storage.length else { return }
        switch span.kind {
        case .heading(let level):
            if mode == .formatted {
                storage.addAttribute(.foregroundColor, value: theme.palette.heading(level: level), range: range)
                let scales: [CGFloat] = [1.7, 1.35, 1.15]
                let scale = level <= 3 ? scales[level - 1] : 1
                let size = (baseFont.pointSize * scale).rounded()
                storage.addAttribute(.font, value: font(theme.headingFont, size: size, trait: .boldFontMask), range: range)
                let paragraph = baseParagraph
                paragraph.paragraphSpacingBefore = level == 1 ? 8 : 14
                paragraph.paragraphSpacing = 6
                storage.addAttribute(.paragraphStyle, value: paragraph, range: range)
            } else {
                addTrait(.boldFontMask, in: range, of: storage)
            }
        case .strong:
            addTrait(.boldFontMask, in: range, of: storage)
            if mode == .formatted { storage.addAttribute(.foregroundColor, value: theme.palette.strong, range: range) }
        case .emphasis:
            addTrait(.italicFontMask, in: range, of: storage)
            if mode == .formatted { storage.addAttribute(.foregroundColor, value: theme.palette.emphasis, range: range) }
        case .strikethrough:
            if mode == .markdown {
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
        case .inlineCode:
            if mode == .formatted {
                storage.addAttribute(.font, value: monoScaled, range: range)
                storage.addAttribute(.foregroundColor, value: theme.palette.inlineCode, range: range)
            }
        case .codeBlock:
            storage.addAttribute(.font, value: monoScaled, range: range)
            if mode == .formatted {
                let paragraph = baseParagraph
                // Fixed from the size: code fonts build in very different amounts of space.
                let lineHeight = (monoScaled.pointSize * 1.55).rounded()
                paragraph.lineHeightMultiple = 0
                paragraph.minimumLineHeight = lineHeight
                paragraph.maximumLineHeight = lineHeight
                paragraph.paragraphSpacing = 0
                paragraph.firstLineHeadIndent = 14
                paragraph.headIndent = 14
                paragraph.tailIndent = -14
                storage.addAttribute(.paragraphStyle, value: paragraph, range: range)
            }
        case .link(let url):
            storage.addAttribute(.claudetteURL, value: url, range: range)
            storage.addAttribute(.foregroundColor, value: mode == .formatted ? theme.palette.link : theme.accent, range: range)
        case .blockquote:
            if mode == .formatted, let callout = map.callouts.first(where: { $0.range == range }) {
                styleCallout(callout, in: storage)
                return
            }
            storage.addAttribute(.foregroundColor, value: theme.soft, range: range)
            if mode == .formatted {
                let paragraph = baseParagraph
                paragraph.firstLineHeadIndent = HidingLayoutManager.quoteIndent
                paragraph.headIndent = HidingLayoutManager.quoteIndent
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

    private func dimCheckedTasks(in storage: NSMutableAttributedString) {
        let text = storage.string as NSString
        for box in map.taskBoxes where box.isChecked && NSMaxRange(box.owner) <= text.length {
            let line = text.lineRange(for: NSRange(location: box.owner.location, length: 0))
            var end = NSMaxRange(line)
            while end > NSMaxRange(box.owner), [0x0A, 0x0D].contains(text.character(at: end - 1)) { end -= 1 }
            storage.addAttribute(.foregroundColor, value: theme.soft, range: NSRange(location: NSMaxRange(box.owner), length: end - NSMaxRange(box.owner)))
        }
    }

    /// Callout text keeps the normal text color; its first line leaves room for the icon.
    private func styleCallout(_ callout: Callout, in storage: NSMutableAttributedString) {
        let paragraph = baseParagraph
        paragraph.firstLineHeadIndent = HidingLayoutManager.quoteIndent
        paragraph.headIndent = HidingLayoutManager.quoteIndent
        storage.addAttribute(.paragraphStyle, value: paragraph, range: callout.range)
        let text = storage.string as NSString
        let firstLine = NSIntersectionRange(text.lineRange(for: NSRange(location: callout.range.location, length: 0)), callout.range)
        let first = paragraph.mutableCopy() as! NSMutableParagraphStyle
        first.firstLineHeadIndent = HidingLayoutManager.quoteIndent + HidingLayoutManager.calloutIconWidth
        storage.addAttribute(.paragraphStyle, value: first, range: firstLine)
        if let title = callout.title {
            storage.addAttribute(.foregroundColor, value: theme.palette.callout(callout.kind), range: title)
            addTrait(.boldFontMask, in: title, of: storage)
        }
    }

    /// The parts of a span that aren't its own hidden syntax. Line decorations must stop
    /// at hidden text: one that runs into it can spread across the whole line.
    private func visibleParts(of range: NSRange) -> [NSRange] {
        var parts = IndexSet(integersIn: range.location..<NSMaxRange(range))
        for item in hiddenByOwner[range] ?? [] {
            parts.remove(integersIn: item.range.location..<NSMaxRange(item.range))
        }
        return parts.rangeView.map { NSRange(location: $0.lowerBound, length: $0.count) }
    }

    /// Languages guessed for unlabeled code blocks, by where each block starts.
    private var guessedLanguages: [Int: String] = [:]

    /// A new document gets fresh guesses.
    func forgetGuessedLanguages() {
        guessedLanguages = [:]
    }

    private func colorCode(in storage: NSMutableAttributedString) {
        let text = storage.string as NSString
        let starts = Set(map.codeBlocks.map(\.range.location))
        guessedLanguages = guessedLanguages.filter { starts.contains($0.key) }
        for block in map.codeBlocks where NSMaxRange(block.contentRange) <= text.length {
            let code = text.substring(with: block.contentRange)
            var language = block.language
            if language == nil {
                // Guessing is slow, so each block is guessed once, not on every keystroke.
                language = guessedLanguages[block.range.location] ?? CodeHighlighter.shared.guessLanguage(in: code)
                guessedLanguages[block.range.location] = language
            }
            for token in CodeHighlighter.shared.tokens(in: code, language: language) {
                let range = NSRange(location: block.contentRange.location + token.range.location, length: token.range.length)
                storage.addAttribute(.foregroundColor, value: theme.palette.color(for: token.kind), range: range)
            }
        }
    }

    /// Resizing or bolding a font drops its features, so coding fonts get theirs back here.
    private func keepOperatorsAsTyped(in storage: NSMutableAttributedString) {
        storage.enumerateAttribute(.font, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let font = value as? NSFont, font.isFixedPitch else { return }
            storage.addAttribute(.font, value: cached("typed", font) { Theme.showingOperatorsAsTyped(font) }, range: range)
        }
    }

    private var monoScaled: NSFont { font(theme.monoFont, size: (baseFont.pointSize * 0.88).rounded()) }

    /// Font conversions are slow and the same few repeat for every bold word and code span.
    private var fontCache: [String: NSFont] = [:]

    private func cached(_ change: String, _ font: NSFont, make: () -> NSFont) -> NSFont {
        let key = "\(change) \(font.fontDescriptor.hashValue) \(font.fontName) \(font.pointSize)"
        if let hit = fontCache[key] { return hit }
        let made = make()
        if fontCache.count > 500 { fontCache.removeAll() }
        fontCache[key] = made
        return made
    }

    private func font(_ base: NSFont, size: CGFloat? = nil, trait: NSFontTraitMask? = nil) -> NSFont {
        cached("\(size ?? 0) \(trait?.rawValue ?? 0)", base) {
            var result = size.map { NSFontManager.shared.convert(base, toSize: $0) } ?? base
            if let trait { result = NSFontManager.shared.convert(result, toHaveTrait: trait) }
            return result
        }
    }

    private func addTrait(_ trait: NSFontTraitMask, in range: NSRange, of storage: NSMutableAttributedString) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            guard let font = value as? NSFont else { return }
            storage.addAttribute(.font, value: self.font(font, trait: trait), range: subrange)
        }
    }

    /// Lines up wrapped lines of a list item with its text.
    private func hangListLine(markerRange: NSRange, in storage: NSMutableAttributedString) {
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
        for item in map.hidden where item.kind == .headingMark || !touches(item.owner) {
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
        for paragraphBreak in map.paragraphBreaks {
            hidden.insert(integersIn: paragraphBreak.location..<NSMaxRange(paragraphBreak))
        }
        return (hidden, substitutions)
    }

    var decorations: EditorDecorations { decorations(selection: NSRange(location: NSNotFound, length: 0)) }

    func decorations(selection: NSRange) -> EditorDecorations {
        guard mode == .formatted else { return EditorDecorations() }
        var result = EditorDecorations()
        result.paragraphBreaks = map.paragraphBreaks
        result.callouts = map.callouts.map {
            CalloutDecoration(range: $0.range, kind: $0.kind, marker: $0.marker, showsDefaultTitle: $0.title == nil)
        }
        func touches(_ owner: NSRange) -> Bool {
            selection.location != NSNotFound && selection.location <= NSMaxRange(owner) && NSMaxRange(selection) >= owner.location
        }
        result.checkboxes = map.taskBoxes.filter { !touches($0.owner) }.map {
            CheckboxDecoration(location: $0.owner.location, isChecked: $0.isChecked, textLocation: NSMaxRange($0.owner) + 1)
        }
        for span in map.spans {
            switch span.kind {
            case .codeBlock: result.codeBlocks.append(span.range)
            case .blockquote where !map.callouts.contains { $0.range == span.range }: result.quotes.append(span.range)
            case .thematicBreak: result.rules.append(span.range)
            case .link: result.underlines.append(contentsOf: visibleParts(of: span.range))
            case .strikethrough: result.strikes.append(contentsOf: visibleParts(of: span.range))
            case .inlineCode:
                let marks = (hiddenByOwner[span.range] ?? []).reduce(0) { $0 + $1.range.length } / 2
                result.chips.append(NSRange(location: span.range.location + marks, length: span.range.length - marks * 2))
            default: break
            }
        }
        return result
    }
}
