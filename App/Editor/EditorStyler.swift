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
        styleItems = Self.styleItems(of: map)
    }

    /// Rescans after an edit, and returns the part of the text whose styling may have changed:
    /// the edited lines, plus anything the scan now reads differently, like a code block
    /// that a new fence opened. `edited` is in the new text; `delta` is the change in length.
    func rescan(_ text: String, edited: NSRange, delta: Int) -> NSRange {
        let before = styleItems
        rescan(text)
        let oldEnd = NSMaxRange(edited) - delta
        func shifted(_ position: Int) -> Int {
            if position <= edited.location { return position }
            if position >= oldEnd { return position + delta }
            return NSMaxRange(edited)
        }
        // Guessed languages are kept by where each block starts, so they move with the text.
        var guesses: [Int: String] = [:]
        for (start, language) in guessedLanguages {
            if start < edited.location { guesses[start] = language } else if start >= oldEnd { guesses[start + delta] = language }
        }
        guessedLanguages = guesses
        let moved = Set(before.map { item in
            let start = shifted(item.range.location)
            return StyleItem(range: NSRange(location: start, length: max(0, shifted(NSMaxRange(item.range)) - start)), tag: item.tag)
        })
        let now = Set(styleItems)
        var dirty = edited
        for item in moved.symmetricDifference(now) {
            dirty = NSUnionRange(dirty, item.range)
        }
        // Code colors depend on everything before them in a block: one quote mark can make
        // the rest of it a string. So an edit in a code block restyles the whole block.
        for block in map.codeBlocks where NSIntersectionRange(block.range, dirty).length > 0 || NSLocationInRange(edited.location, block.range) {
            dirty = NSUnionRange(dirty, block.range)
        }
        let ns = text as NSString
        let start = ns.lineRange(for: NSRange(location: min(dirty.location, ns.length), length: 0)).location
        let end = NSMaxRange(ns.lineRange(for: NSRange(location: min(NSMaxRange(dirty), ns.length), length: 0)))
        return NSRange(location: start, length: end - start)
    }

    /// Everything from a scan that sets attributes, as plain ranges and labels to compare.
    private struct StyleItem: Hashable {
        var range: NSRange
        var tag: String
    }

    private var styleItems: [StyleItem] = []

    private static func styleItems(of map: StyleMap) -> [StyleItem] {
        var items: [StyleItem] = []
        items.reserveCapacity(map.spans.count + map.hidden.count + map.substitutions.count)
        for span in map.spans { items.append(StyleItem(range: span.range, tag: "span \(span.kind)")) }
        for item in map.hidden { items.append(StyleItem(range: item.range, tag: "hidden")) }
        for item in map.substitutions { items.append(StyleItem(range: item.range, tag: "sub \(item.glyph)")) }
        for box in map.taskBoxes { items.append(StyleItem(range: box.owner, tag: "task \(box.isChecked)")) }
        for block in map.codeBlocks {
            items.append(StyleItem(range: block.range, tag: "code \(block.language ?? "") \(block.isClosed)"))
            items.append(StyleItem(range: block.contentRange, tag: "code content"))
        }
        for callout in map.callouts {
            items.append(StyleItem(range: callout.range, tag: "callout \(callout.kind)"))
            if let title = callout.title { items.append(StyleItem(range: title, tag: "callout title")) }
        }
        return items
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

    private static func font(drawing symbol: String, size: CGFloat) -> NSFont? {
        let candidates = [NSFont.systemFont(ofSize: size), NSFont(name: "Apple Symbols", size: size)].compactMap { $0 }
        return candidates.first { has(symbol, in: $0) }
    }

    private static func has(_ symbol: String, in font: NSFont) -> Bool {
        var glyphs = [CGGlyph](repeating: 0, count: symbol.utf16.count)
        return CTFontGetGlyphsForCharacters(font as CTFont, Array(symbol.utf16), &glyphs, glyphs.count) && glyphs[0] != 0
    }

    /// How much text the last restyle covered, for checking edits stay local.
    private(set) var lastRestyledLength = 0
    private(set) var lastRestyledRange = NSRange()

    /// Styles the text, changing only attributes that differ from what's there. Setting every
    /// attribute again would make the whole document lay out again on every keystroke.
    /// `region` limits the work to part of the text; nil styles all of it.
    func apply(to storage: NSTextStorage, in region: NSRange? = nil) {
        let length = storage.length
        let area = region.map { NSIntersectionRange($0, NSRange(location: 0, length: length)) } ?? NSRange(location: 0, length: length)
        lastRestyledLength = area.length
        lastRestyledRange = area
        guard area.length > 0 else { return }
        let styled = NSMutableAttributedString(string: storage.string)
        apply(toScratch: StyledText(styled, region: area))
        var location = area.location
        while location < NSMaxRange(area) {
            var run = NSRange()
            let wanted = styled.attributes(at: location, longestEffectiveRange: &run, in: NSRange(location: location, length: NSMaxRange(area) - location))
            storage.enumerateAttributes(in: run) { current, part, _ in
                if !(current as NSDictionary).isEqual(to: wanted) { storage.setAttributes(wanted, range: part) }
            }
            location = NSMaxRange(run)
        }
    }

    /// Styles text from scratch: every attribute is set.
    func apply(toScratch storage: NSMutableAttributedString) {
        apply(toScratch: StyledText(storage, region: NSRange(location: 0, length: storage.length)))
    }

    private func apply(toScratch storage: StyledText) {
        let all = storage.region
        guard all.length > 0 else { return }
        storage.setAttributes(typingAttributes, range: all)
        for span in map.spans where storage.touches(span.range) {
            style(span, in: storage)
        }
        if mode == .formatted { dimCheckedTasks(in: storage) }
        colorCode(in: storage)
        keepOperatorsAsTyped(in: storage)
        // Setting fonts above undoes the system's choice of fallback fonts for characters a
        // theme font lacks, like emoji, ⌘ or Japanese, which would then draw as nothing.
        storage.text.fixFontAttribute(in: storage.region)
        if mode == .markdown {
            for range in map.hidden.map(\.range) + map.substitutions.map(\.range) where storage.touches(range) {
                storage.addAttribute(.foregroundColor, value: theme.accent, range: range)
            }
        } else {
            for substitution in map.substitutions where substitution.range.length == 1 && storage.touches(substitution.range) {
                // Theme fonts may not have the hollow or square bullets, so the first font that does draws it.
                if !Self.has(substitution.glyph, in: baseFont), let font = Self.font(drawing: substitution.glyph, size: baseFont.pointSize) {
                    storage.addAttribute(.font, value: font, range: substitution.range)
                }
            }
            for substitution in map.substitutions where substitution.range.length > 1 && storage.touches(substitution.range) {
                let size = baseFont.pointSize
                let font = NSFont(name: "Apple Symbols", size: size * 1.15) ?? baseFont
                storage.addAttribute(.font, value: font, range: substitution.range)
                storage.addAttribute(.foregroundColor, value: theme.palette.check, range: substitution.range)
            }
        }
    }

    private func style(_ span: StyledSpan, in storage: StyledText) {
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

    private func dimCheckedTasks(in storage: StyledText) {
        let text = storage.string as NSString
        for box in map.taskBoxes where box.isChecked && NSMaxRange(box.owner) <= text.length && storage.touches(box.owner) {
            let line = text.lineRange(for: NSRange(location: box.owner.location, length: 0))
            var end = NSMaxRange(line)
            while end > NSMaxRange(box.owner), [0x0A, 0x0D].contains(text.character(at: end - 1)) { end -= 1 }
            storage.addAttribute(.foregroundColor, value: theme.soft, range: NSRange(location: NSMaxRange(box.owner), length: end - NSMaxRange(box.owner)))
        }
    }

    /// Callout text keeps the normal text color; its first line leaves room for the icon.
    private func styleCallout(_ callout: Callout, in storage: StyledText) {
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

    private func colorCode(in storage: StyledText) {
        let text = storage.string as NSString
        let starts = Set(map.codeBlocks.map(\.range.location))
        guessedLanguages = guessedLanguages.filter { starts.contains($0.key) }
        for block in map.codeBlocks where NSMaxRange(block.contentRange) <= text.length && storage.touches(block.range) {
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
    private func keepOperatorsAsTyped(in storage: StyledText) {
        storage.enumerateAttribute(.font, in: storage.region) { value, range, _ in
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

    private func addTrait(_ trait: NSFontTraitMask, in range: NSRange, of storage: StyledText) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            guard let font = value as? NSFont else { return }
            storage.addAttribute(.font, value: self.font(font, trait: trait), range: subrange)
        }
    }

    /// How far list items sit in from the text around them.
    static let listIndent: CGFloat = 14
    /// Each space before a nested list item is drawn this wide.
    static let nestedSpaceWidth: CGFloat = 9

    /// Indents a list item, and lines up its wrapped lines with its text.
    private func hangListLine(markerRange: NSRange, in storage: StyledText) {
        let text = storage.string as NSString
        let line = text.lineRange(for: NSRange(location: markerRange.location, length: 0))
        let leading = markerRange.location - line.location
        // Spaces before a nested item are narrow; each is drawn wider so nesting shows.
        let space = (" " as NSString).size(withAttributes: [.font: baseFont]).width
        if leading > 0 {
            storage.addAttribute(.kern, value: Self.nestedSpaceWidth - space, range: NSRange(location: line.location, length: leading))
        }
        var marker = text.substring(with: markerRange)
        if mode == .formatted, marker.count == 1, "-*+".contains(marker) { marker = "•" }
        let markerWidth = ((marker + " ") as NSString).size(withAttributes: [.font: baseFont]).width
        let paragraph = baseParagraph
        paragraph.firstLineHeadIndent = Self.listIndent
        paragraph.headIndent = Self.listIndent + CGFloat(leading) * Self.nestedSpaceWidth + markerWidth
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

/// Text being styled, limited to a region: changes outside it are dropped, so restyling
/// part of a document gives exactly what styling all of it would give there.
final class StyledText {
    let text: NSMutableAttributedString
    let region: NSRange

    init(_ text: NSMutableAttributedString, region: NSRange) {
        self.text = text
        self.region = region
    }

    var string: String { text.string }
    var length: Int { text.length }

    func touches(_ range: NSRange) -> Bool {
        NSIntersectionRange(range, region).length > 0
    }

    func addAttribute(_ key: NSAttributedString.Key, value: Any, range: NSRange) {
        let part = NSIntersectionRange(range, region)
        if part.length > 0 { text.addAttribute(key, value: value, range: part) }
    }

    func setAttributes(_ attributes: [NSAttributedString.Key: Any], range: NSRange) {
        let part = NSIntersectionRange(range, region)
        if part.length > 0 { text.setAttributes(attributes, range: part) }
    }

    func enumerateAttribute(_ key: NSAttributedString.Key, in range: NSRange, using block: (Any?, NSRange, UnsafeMutablePointer<ObjCBool>) -> Void) {
        let part = NSIntersectionRange(range, region)
        if part.length > 0 { text.enumerateAttribute(key, in: part, using: block) }
    }
}
