import AppKit
import XCTest
@testable import Claudette

/// Characters a theme's font doesn't have, like emoji, ⌘ and Japanese, still draw in a font that does.
@MainActor
final class FontFallbackTests: XCTestCase {
    private let text = "Shortcut ⌘-click and ⇧Return.\n\nEmoji: ✅ 🚀 and arrows → plus 日本語.\n"

    private func canDraw(_ editor: EditorTextView, _ character: String) -> Bool {
        let ns = editor.string as NSString
        let index = ns.range(of: character).location
        let font = editor.textStorage!.attribute(.font, at: index, effectiveRange: nil) as! NSFont
        let units = Array(character.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        return CTFontGetGlyphsForCharacters(font as CTFont, units, &glyphs, units.count) && glyphs[0] != 0
    }

    func testMissingCharactersDrawInEveryTheme() {
        for theme in Theme.all {
            let (_, editor) = EditorTextView.makeInScrollView()
            editor.theme = theme
            editor.load(text: text)
            for character in ["⌘", "⇧", "✅", "🚀", "→", "日"] {
                XCTAssertTrue(canDraw(editor, character), "\(theme.name) can't draw \(character)")
            }
        }
    }

    func testTypedEmojiDraws() {
        let (_, editor) = EditorTextView.makeInScrollView()
        editor.load(text: "Done ")
        editor.insertText("🎉", replacementRange: NSRange(location: 5, length: 0))
        XCTAssertTrue(canDraw(editor, "🎉"))
    }

    func testEmojiInBoldAndHeadingsDraws() {
        let (_, editor) = EditorTextView.makeInScrollView()
        editor.load(text: "# Launch 🚀\n\n**done ✅**\n")
        XCTAssertTrue(canDraw(editor, "🚀"))
        XCTAssertTrue(canDraw(editor, "✅"))
    }
}
