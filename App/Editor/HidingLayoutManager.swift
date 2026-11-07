import AppKit

struct EditorDecorations: Equatable {
    var codeBlocks: [NSRange] = []
    var quotes: [NSRange] = []
    var rules: [NSRange] = []
    var chips: [NSRange] = []
}

/// Draws the document with some characters hidden or swapped, without changing the text.
final class HidingLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    private(set) var hidden = IndexSet()
    private(set) var substitutions: [Int: Character] = [:]
    var decorations = EditorDecorations()
    var codeBackground = NSColor.clear
    var ruleColor = NSColor.clear
    var quoteBarColor = NSColor.clear

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

    private func drawChip(_ range: NSRange, showing glyphsToShow: NSRange, at origin: NSPoint) {
        guard let length = textStorage?.length, NSMaxRange(range) <= length, let container = textContainers.first else { return }
        let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard NSIntersectionRange(glyphs, glyphsToShow).length > 0 else { return }
        codeBackground.setFill()
        enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { rect, _ in
            let chip = rect.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -3, dy: 2)
            NSBezierPath(roundedRect: chip, xRadius: 4, yRadius: 4).fill()
        }
    }

    private func fragmentsRect(of range: NSRange, showing glyphsToShow: NSRange) -> NSRect? {
        guard let length = textStorage?.length, NSMaxRange(range) <= length else { return nil }
        let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard NSIntersectionRange(glyphs, glyphsToShow).length > 0 || glyphs.length == 0 else { return nil }
        var result: NSRect?
        enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in
            result = result?.union(rect) ?? rect
        }
        return result
    }
}
