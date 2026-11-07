import AppKit

struct EditorDecorations: Equatable {
    var codeBlocks: [NSRange] = []
    var quotes: [NSRange] = []
    var rules: [NSRange] = []
    var chips: [NSRange] = []
    var underlines: [NSRange] = []
    var strikes: [NSRange] = []
}

/// Draws the document with some characters hidden or swapped, without changing the text.
final class HidingLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    private(set) var hidden = IndexSet()
    private(set) var substitutions: [Int: Character] = [:]
    var decorations = EditorDecorations()
    /// Tables drawn over hidden source, as the source range and the height to reserve.
    private(set) var reservedTables: [(range: NSRange, height: CGFloat)] = []
    var codeBackground = NSColor.clear
    var ruleColor = NSColor.clear
    var quoteBarColor = NSColor.clear
    var underlineColor = NSColor.clear
    var strikeColor = NSColor.clear

    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }

    func isHidden(at index: Int) -> Bool { hidden.contains(index) }

    /// Pass `invalidate: false` from inside text storage editing, where layout is redone anyway.
    func setDisplay(hidden newHidden: IndexSet, substitutions newSubstitutions: [Int: Character], invalidate: Bool = true) {
        var changed = hidden.symmetricDifference(newHidden)
        for key in Set(substitutions.keys).union(newSubstitutions.keys)
        where substitutions[key] != newSubstitutions[key] {
            changed.insert(key)
        }
        hidden = newHidden
        substitutions = newSubstitutions
        guard invalidate, !changed.isEmpty, let storage = textStorage else { return }
        let text = storage.string as NSString
        for range in changed.rangeView {
            let start = min(range.lowerBound, text.length)
            let end = min(range.upperBound, text.length)
            // Hidden newlines change line breaks, so redo whole paragraphs.
            let paragraph = text.paragraphRange(for: NSRange(location: start, length: end - start))
            invalidateGlyphs(forCharacterRange: paragraph, changeInLength: 0, actualCharacterRange: nil)
            invalidateLayout(forCharacterRange: paragraph, actualCharacterRange: nil)
        }
    }

    func setReservedTables(_ tables: [(range: NSRange, height: CGFloat)], invalidate: Bool) {
        let changed = tables.map(\.height) != reservedTables.map(\.height)
        reservedTables = tables
        guard invalidate, changed, let length = textStorage?.length else { return }
        for table in tables where NSMaxRange(table.range) <= length {
            invalidateLayout(forCharacterRange: table.range, actualCharacterRange: nil)
        }
    }

    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
                       lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
                       baselineOffset: UnsafeMutablePointer<CGFloat>,
                       in textContainer: NSTextContainer,
                       forGlyphRange glyphRange: NSRange) -> Bool {
        guard !reservedTables.isEmpty else { return false }
        let characters = characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard let table = reservedTables.first(where: { NSIntersectionRange($0.range, characters).length > 0 }) else { return false }
        lineFragmentRect.pointee.size.height = table.height
        lineFragmentUsedRect.pointee.size.height = table.height
        return true
    }

    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties: UnsafePointer<NSLayoutManager.GlyphProperty>,
                       characterIndexes: UnsafePointer<Int>,
                       font: NSFont,
                       forGlyphRange glyphRange: NSRange) -> Int {
        let count = glyphRange.length
        var newGlyphs = Array(UnsafeBufferPointer(start: glyphs, count: count))
        var newProperties = Array(UnsafeBufferPointer(start: properties, count: count))
        var didChange = false
        for i in 0..<count {
            let index = characterIndexes[i]
            if hidden.contains(index) {
                newProperties[i] = .null
                didChange = true
            } else if let character = substitutions[index], let glyph = glyph(for: character, in: font) {
                newGlyphs[i] = glyph
                didChange = true
            }
        }
        guard didChange else { return 0 }
        setGlyphs(newGlyphs, properties: newProperties, characterIndexes: characterIndexes, font: font, forGlyphRange: glyphRange)
        return count
    }

    private func glyph(for character: Character, in font: NSFont) -> CGGlyph? {
        let units = Array(String(character).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        guard CTFontGetGlyphsForCharacters(font as CTFont, units, &glyphs, units.count), glyphs[0] != 0 else { return nil }
        return glyphs[0]
    }

    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldUse action: NSLayoutManager.ControlCharacterAction,
                       forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
        hidden.contains(charIndex) ? .zeroAdvancement : action
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        for range in decorations.codeBlocks {
            guard let rect = fragmentsRect(of: range, showing: glyphsToShow) else { continue }
            codeBackground.setFill()
            NSBezierPath(roundedRect: rect.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: 0, dy: -6), xRadius: 7, yRadius: 7).fill()
        }
        for range in decorations.chips {
            drawChip(range, showing: glyphsToShow, at: origin)
        }
        for range in decorations.underlines {
            drawLine(under: range, color: underlineColor, offset: 2.5, showing: glyphsToShow, at: origin)
        }
        for range in decorations.strikes {
            drawLine(under: range, color: strikeColor, offset: -5, showing: glyphsToShow, at: origin)
        }
        for range in decorations.quotes {
            guard let rect = fragmentsRect(of: range, showing: glyphsToShow) else { continue }
            quoteBarColor.setFill()
            NSRect(x: rect.minX + origin.x + 2, y: rect.minY + origin.y, width: 3, height: rect.height).fill()
        }
        for range in decorations.rules where hidden.contains(range.location) {
            guard let rect = fragmentsRect(of: range, showing: glyphsToShow) else { continue }
            ruleColor.setFill()
            NSRect(x: rect.minX + origin.x, y: rect.midY + origin.y, width: rect.width, height: 1).fill()
        }
    }

    /// Text attributes can't do this: their lines spread across a line that has hidden text at a wrap.
    private func drawLine(under range: NSRange, color: NSColor, offset: CGFloat, showing glyphsToShow: NSRange, at origin: NSPoint) {
        color.setFill()
        for rect in lineRects(of: range) {
            NSRect(x: rect.minX + origin.x, y: rect.maxY + offset + origin.y, width: rect.width, height: 1).fill()
        }
    }

    /// One rectangle per line a range is on, from its text's left edge to its baseline.
    func lineRects(of range: NSRange) -> [NSRect] {
        guard let glyphs = displayedGlyphs(of: range) else { return [] }
        var rects: [NSRect] = []
        enumerateLineFragments(forGlyphRange: glyphs) { fragment, used, _, lineGlyphs, _ in
            let part = NSIntersectionRange(lineGlyphs, glyphs)
            guard part.length > 0 else { return }
            let start = self.location(forGlyphAt: part.location)
            // Measured glyph by glyph: bounding-rect lookups return the whole line
            // when a wrapped line ends in hidden glyphs.
            let next = NSMaxRange(part)
            let endX = next < NSMaxRange(lineGlyphs) ? self.location(forGlyphAt: next).x : used.width + used.minX - fragment.minX
            rects.append(NSRect(x: fragment.minX + start.x, y: fragment.minY, width: endX - start.x, height: start.y))
        }
        return rects
    }

    /// The glyphs for a range, without hidden syntax at either end.
    private func displayedGlyphs(of range: NSRange) -> NSRange? {
        guard let length = textStorage?.length, NSMaxRange(range) <= length, range.length > 0 else { return nil }
        var start = range.location
        var end = NSMaxRange(range)
        while start < end, hidden.contains(start) { start += 1 }
        while end > start, hidden.contains(end - 1) { end -= 1 }
        if start == end {
            // All hidden, like a rule: use the whole range.
            start = range.location
            end = NSMaxRange(range)
        }
        // Mapped one character at a time: `glyphRange(forCharacterRange:)` runs on through
        // any hidden glyphs that follow, and hidden text at a line start joins the line before.
        let first = glyphIndexForCharacter(at: start)
        let last = glyphIndexForCharacter(at: end - 1)
        return NSRange(location: first, length: last - first + 1)
    }

    private func drawChip(_ range: NSRange, showing glyphsToShow: NSRange, at origin: NSPoint) {
        guard let glyphs = displayedGlyphs(of: range), let container = textContainers.first,
              NSIntersectionRange(glyphs, glyphsToShow).length > 0 else { return }
        codeBackground.setFill()
        enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { rect, _ in
            let chip = rect.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -3, dy: 2)
            NSBezierPath(roundedRect: chip, xRadius: 4, yRadius: 4).fill()
        }
    }

    private func fragmentsRect(of range: NSRange, showing glyphsToShow: NSRange) -> NSRect? {
        guard let glyphs = displayedGlyphs(of: range), NSIntersectionRange(glyphs, glyphsToShow).length > 0 else { return nil }
        return blockRect(of: range)
    }

    /// The line fragments a block's displayed text is on.
    func blockRect(of range: NSRange) -> NSRect? {
        guard let glyphs = displayedGlyphs(of: range) else { return nil }
        var result: NSRect?
        enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in
            result = result?.union(rect) ?? rect
        }
        return result
    }
}
