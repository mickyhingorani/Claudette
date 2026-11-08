import AppKit
import XCTest
@testable import Claudette

@MainActor
final class TypingSpeedTests: XCTestCase {
    private func longDocument() -> String {
        let section = "## Section\n\nSome **bold** text with a [link](https://x.com) and `code` here.\n\n- item one\n- [ ] task two\n\n> a quote line\n\n```js\nconst a = 1;\n```\n\n"
        return String(repeating: section, count: 230)
    }

    /// Restyling applies only the attributes that changed, so a keystroke re-lays out
    /// the text around it, not the whole document.
    func testAKeystrokeRelaysOutOnlyNearbyText() {
        let (_, editor) = EditorTextView.makeInScrollView()
        editor.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let text = longDocument()
        editor.load(text: text)
        editor.layoutManager!.ensureLayout(for: editor.textContainer!)
        editor.setSelectedRange(NSRange(location: (text as NSString).length / 2, length: 0))
        editor.hidingLayoutManager.largestInvalidation = 0
        editor.insertText("x", replacementRange: editor.selectedRange())
        XCTAssertLessThan(editor.hidingLayoutManager.largestInvalidation, 2_000)
    }

    func testRestylingStillFollowsTheEdit() {
        let (_, editor) = EditorTextView.makeInScrollView()
        editor.theme = .slate
        editor.load(text: "plain\n")
        editor.insertText("**", replacementRange: NSRange(location: 0, length: 0))
        editor.insertText("**", replacementRange: NSRange(location: 7, length: 0))
        let color = editor.textStorage!.attribute(.foregroundColor, at: 3, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, Theme.slate.palette.strong)
        // "** plain**" is no longer bold.
        editor.insertText(" ", replacementRange: NSRange(location: 2, length: 0))
        let after = editor.textStorage!.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor
        XCTAssertEqual(after, Theme.slate.text, "styles that no longer apply are removed")
    }

    func testRestyleKeepsEveryRunIdenticalToAFullStyle() {
        let (_, editor) = EditorTextView.makeInScrollView()
        let text = longDocument()
        editor.load(text: text)
        editor.insertText("**x**", replacementRange: NSRange(location: 500, length: 0))
        let fresh = NSMutableAttributedString(string: editor.string)
        editor.styler.apply(toScratch: fresh)
        XCTAssertTrue(editor.textStorage!.isEqual(to: fresh))
    }
}
