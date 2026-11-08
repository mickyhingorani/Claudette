import AppKit
import XCTest
import ClaudetteCore
@testable import Claudette

/// The WCAG contrast ratio between two colors.
enum ThemeContrast {
    static func ratio(_ a: NSColor, _ b: NSColor) -> CGFloat {
        func luminance(_ color: NSColor) -> CGFloat {
            let c = color.usingColorSpace(.sRGB)!
            func channel(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * channel(c.redComponent) + 0.7152 * channel(c.greenComponent) + 0.0722 * channel(c.blueComponent)
        }
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}

final class ThemeTests: XCTestCase {
    private func luminance(_ color: NSColor) -> CGFloat {
        let c = color.usingColorSpace(.sRGB)!
        func channel(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(c.redComponent) + 0.7152 * channel(c.greenComponent) + 0.0722 * channel(c.blueComponent)
    }

    private func contrast(_ a: NSColor, _ b: NSColor) -> CGFloat {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    func testAllThemesAreOffered() {
        XCTAssertEqual(Theme.all.map(\.name), ["Slate", "Nord", "Solarized", "Harbor", "Terminal"])
    }

    func testSlateIsTheDefault() {
        XCTAssertEqual(Theme.default, .slate)
    }

    func testRemovedInkThemeFallsBackToTheDefault() {
        XCTAssertEqual(Theme.named("ink"), .slate)
    }

    func testEachThemeHasItsOwnFont() {
        XCTAssertEqual(Set(Theme.all.map { $0.bodyFont.familyName }).count, Theme.all.count)
    }

    /// Headings, body text and code, as the bundled fonts' family names.
    func testThemeFontsAreTheOnesChosen() {
        let fonts = Theme.all.map { [$0.headingFont.familyName, $0.bodyFont.familyName, $0.monoFont.familyName] }
        XCTAssertEqual(fonts, [
            ["Atkinson Hyperlegible Next", "Atkinson Hyperlegible Next", "JetBrains Mono"],
            ["Geist", "Geist", "Geist Mono"],
            ["IBM Plex Sans", "IBM Plex Sans", "IBM Plex Mono"],
            ["Hanken Grotesk", "Hanken Grotesk", "JetBrains Mono"],
            ["JetBrains Mono", "JetBrains Mono", "JetBrains Mono"],
        ])
    }

    func testEveryThemeFontHasBoldAndItalic() {
        let manager = NSFontManager.shared
        for theme in Theme.all {
            for font in [theme.titleFont, theme.bodyFont, theme.monoFont] {
                let bold = manager.convert(font, toHaveTrait: .boldFontMask)
                let italic = manager.convert(font, toHaveTrait: .italicFontMask)
                XCTAssertTrue(manager.traits(of: bold).contains(.boldFontMask), "\(theme.name) \(font.fontName)")
                XCTAssertTrue(manager.traits(of: italic).contains(.italicFontMask), "\(theme.name) \(font.fontName)")
                XCTAssertEqual(bold.familyName, font.familyName)
            }
        }
    }

    /// Code shows `=>` and `!=` as typed, not as arrow and not-equal symbols.
    func testCodeFontsKeepOperatorsAsTyped() {
        for theme in Theme.all {
            for font in [theme.monoFont, theme.bodyFont] where font.isFixedPitch {
                let text = NSAttributedString(string: "=>", attributes: [.font: font])
                let line = CTLineCreateWithAttributedString(text)
                let runs = CTLineGetGlyphRuns(line) as! [CTRun]
                var glyphs = [CGGlyph](repeating: 0, count: 2)
                CTRunGetGlyphs(runs[0], CFRange(location: 0, length: 2), &glyphs)
                var plain = [CGGlyph](repeating: 0, count: 2)
                CTFontGetGlyphsForCharacters(font as CTFont, Array("=>".utf16), &plain, 2)
                XCTAssertEqual(glyphs, plain, "\(theme.name) \(font.fontName)")
            }
        }
    }

    func testTextIsReadableInEveryTheme() {
        for theme in Theme.all {
            XCTAssertGreaterThanOrEqual(contrast(theme.text, theme.background), 4.5, theme.name)
            XCTAssertGreaterThanOrEqual(contrast(theme.soft, theme.background), 4.5, theme.name)
            XCTAssertGreaterThanOrEqual(contrast(theme.accent, theme.background), 4.5, theme.name)
            XCTAssertGreaterThanOrEqual(contrast(theme.text, theme.panel), 4.5, theme.name)
        }
    }

    /// Harbor sets its big titles in a serif; every other theme uses its heading font.
    func testTitleFonts() {
        XCTAssertEqual(Theme.harbor.titleFont.familyName, "Newsreader")
        for theme in Theme.all where theme != .harbor {
            XCTAssertEqual(theme.titleFont, theme.headingFont, theme.name)
        }
    }

    /// Harbor's Note callouts are blue, not its gold link color; other themes keep theirs.
    func testHarborNoteCalloutIsBlue() {
        let harbor = Theme.harbor.palette
        XCTAssertNotEqual(harbor.callout(.note), harbor.link)
        XCTAssertGreaterThanOrEqual(contrast(harbor.callout(.note), Theme.harbor.background), 4.5)
        for theme in Theme.all where theme != .harbor {
            XCTAssertEqual(theme.palette.callout(.note), theme.palette.link, theme.name)
        }
    }

    /// Only Harbor outlines its code chips and code blocks.
    func testOnlyHarborOutlinesCode() {
        XCTAssertNotNil(Theme.harbor.outline)
        for theme in Theme.all where theme != .harbor {
            XCTAssertNil(theme.outline, theme.name)
        }
    }

    func testEveryThemeCanBeBoldAndItalic() {
        let manager = NSFontManager.shared
        for theme in Theme.all {
            XCTAssertTrue(manager.traits(of: manager.convert(theme.bodyFont, toHaveTrait: .boldFontMask)).contains(.boldFontMask), theme.name)
        }
    }

    func testEveryColorIsReadable() {
        for theme in Theme.all {
            let p = theme.palette
            for color in [p.strong, p.emphasis, p.link, p.check] {
                XCTAssertGreaterThanOrEqual(contrast(color, theme.background), 4.5, theme.name)
            }
            for color in [p.heading1, p.heading2, p.heading3] {
                XCTAssertGreaterThanOrEqual(contrast(color, theme.background), 3, theme.name)
            }
            XCTAssertGreaterThanOrEqual(contrast(p.inlineCode, theme.chip), 4.5, theme.name)
            XCTAssertGreaterThanOrEqual(contrast(p.tableHeaderText, p.tableHeader), 4.5, theme.name)
            for color in [p.keyword, p.string, p.number, p.function, p.tag, p.attribute, p.type] {
                XCTAssertGreaterThanOrEqual(contrast(color, theme.panel), 4.5, theme.name)
            }
            XCTAssertGreaterThanOrEqual(contrast(p.comment, theme.panel), 3, theme.name)
        }
    }

    func testEachThemeHasItsOwnColors() {
        XCTAssertEqual(Set(Theme.all.map { $0.palette.heading1 }).count, Theme.all.count)
    }
}

@MainActor
final class ThemeFontEditorTests: XCTestCase {
    private func glyphs(_ string: String, in editor: EditorTextView, at location: Int) -> (shown: [CGGlyph], plain: [CGGlyph]) {
        let font = editor.textStorage!.attribute(.font, at: location, effectiveRange: nil) as! NSFont
        let text = NSAttributedString(string: string, attributes: [.font: font])
        let run = (CTLineGetGlyphRuns(CTLineCreateWithAttributedString(text)) as! [CTRun])[0]
        var shown = [CGGlyph](repeating: 0, count: 2)
        CTRunGetGlyphs(run, CFRange(location: 0, length: 2), &shown)
        var plain = [CGGlyph](repeating: 0, count: 2)
        CTFontGetGlyphsForCharacters(font as CTFont, Array(string.utf16), &plain, 2)
        return (shown, plain)
    }

    func testBoldTerminalTextKeepsOperatorsAsTyped() {
        let (_, editor) = EditorTextView.makeInScrollView()
        editor.theme = .terminal
        editor.load(text: "**a => b**")
        let result = glyphs("=>", in: editor, at: 4)
        XCTAssertEqual(result.shown, result.plain)
    }

    func testCodeBlockKeepsOperatorsAsTyped() {
        let (_, editor) = EditorTextView.makeInScrollView()
        editor.theme = .solarized
        editor.load(text: "```\na != b\n```\n")
        let result = glyphs("!=", in: editor, at: 6)
        XCTAssertEqual(result.shown, result.plain)
    }

    func testHeadingsUseTheThemesHeadingFont() {
        let (_, editor) = EditorTextView.makeInScrollView()
        editor.theme = .solarized
        editor.load(text: "# Title\n\nbody\n")
        let heading = editor.textStorage!.attribute(.font, at: 3, effectiveRange: nil) as! NSFont
        let body = editor.textStorage!.attribute(.font, at: 10, effectiveRange: nil) as! NSFont
        XCTAssertEqual(heading.familyName, "IBM Plex Sans")
        XCTAssertEqual(body.familyName, "IBM Plex Sans")
        XCTAssertGreaterThan(heading.pointSize, body.pointSize)
    }

    func testEditorPassesTheOutlineToDrawing() {
        let (_, editor) = EditorTextView.makeInScrollView()
        editor.theme = .harbor
        XCTAssertEqual(editor.hidingLayoutManager.outlineColor, Theme.harbor.outline)
        editor.theme = .slate
        XCTAssertNil(editor.hidingLayoutManager.outlineColor)
    }

    /// Harbor: `#` titles in regular-weight Newsreader, `##` and below in bold Hanken Grotesk.
    func testHarborTitlesAreSerifAndSmallerHeadingsAreBoldSans() {
        let (_, editor) = EditorTextView.makeInScrollView()
        editor.theme = .harbor
        editor.load(text: "# Title\n\n## Part\n\nbody\n")
        let manager = NSFontManager.shared
        let title = editor.textStorage!.attribute(.font, at: 3, effectiveRange: nil) as! NSFont
        let part = editor.textStorage!.attribute(.font, at: 13, effectiveRange: nil) as! NSFont
        XCTAssertEqual(title.familyName, "Newsreader")
        XCTAssertFalse(manager.traits(of: title).contains(.boldFontMask))
        XCTAssertEqual(part.familyName, "Hanken Grotesk")
        XCTAssertTrue(manager.traits(of: part).contains(.boldFontMask))
    }
}

@MainActor
final class CodeLineSpacingTests: XCTestCase {
    /// Code fonts differ in how much space they build in, so code lines get the same rhythm in every theme.
    func testCodeLinesAreOneAndAHalfTimesTheFontSize() {
        for theme in Theme.all {
            let (_, editor) = EditorTextView.makeInScrollView()
            editor.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
            editor.theme = theme
            editor.load(text: "```\na\nb\nc\n```\n")
            let layout = editor.hidingLayoutManager
            layout.ensureLayout(for: editor.textContainer!)
            let font = editor.textStorage!.attribute(.font, at: 6, effectiveRange: nil) as! NSFont
            let line = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: 6), effectiveRange: nil)
            XCTAssertEqual(line.height, (font.pointSize * 1.55).rounded(), accuracy: 0.5, theme.name)
        }
    }
}

@MainActor
final class LanguageGuessEditorTests: XCTestCase {
    func testTypingInUnlabeledCodeGuessesItsLanguageOnce() {
        let (_, editor) = EditorTextView.makeInScrollView()
        editor.load(text: "```\nfunction add(a, b) {\n  return a + b;\n}\n```\n")
        let before = CodeHighlighter.shared.guessCount
        for character in "// note" {
            editor.insertText(String(character), replacementRange: NSRange(location: 4, length: 0))
        }
        XCTAssertEqual(CodeHighlighter.shared.guessCount, before)
    }

    func testUnlabeledCodeIsStillColored() {
        let (_, editor) = EditorTextView.makeInScrollView()
        editor.theme = .slate
        editor.load(text: "```\nfunction add(a, b) {\n  return a + b;\n}\n```\n")
        let keyword = editor.textStorage!.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor
        XCTAssertEqual(keyword, Theme.slate.palette.keyword)
    }

    func testOpeningAnotherFileGuessesAgain() {
        let (_, editor) = EditorTextView.makeInScrollView()
        editor.load(text: "```\nfunction a() {}\n```\n")
        let before = CodeHighlighter.shared.guessCount
        editor.load(text: "```\ndef a():\n    return 1\n```\n")
        XCTAssertGreaterThan(CodeHighlighter.shared.guessCount, before)
    }
}
