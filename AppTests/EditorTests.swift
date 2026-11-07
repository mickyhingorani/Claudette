import AppKit
import XCTest
@testable import Claudette

final class EditorTests: XCTestCase {
    private func makeEditor(_ text: String) -> EditorTextView {
        let (_, editor) = EditorTextView.makeInScrollView()
        editor.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        editor.load(text: text)
        return editor
    }

    func testSyntaxHiddenAwayFromCursor() {
        let editor = makeEditor("x **b** y")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertTrue(editor.hidingLayoutManager.isHidden(at: 2))
        XCTAssertTrue(editor.hidingLayoutManager.isHidden(at: 5))
    }

    func testSyntaxRevealedWhenCursorInsideSpan() {
        let editor = makeEditor("x **b** y")
        editor.setSelectedRange(NSRange(location: 4, length: 0))
        XCTAssertFalse(editor.hidingLayoutManager.isHidden(at: 2))
    }

    func testSyntaxHidesAgainWhenCursorLeaves() {
        let editor = makeEditor("x **b** y")
        editor.setSelectedRange(NSRange(location: 4, length: 0))
        editor.setSelectedRange(NSRange(location: 9, length: 0))
        XCTAssertTrue(editor.hidingLayoutManager.isHidden(at: 2))
    }

    func testMarkdownModeHidesNothing() {
        let editor = makeEditor("x **b** y")
        editor.viewMode = .markdown
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertFalse(editor.hidingLayoutManager.isHidden(at: 2))
    }

    func testCursorMovesThroughHiddenSpanWithoutSticking() {
        let text = "a **b** [c](u) `d` e"
        let editor = makeEditor(text)
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        var last = 0
        for _ in 0..<(text.utf16.count * 2) {
            editor.moveRight(nil)
            let location = editor.selectedRange().location
            if location == text.utf16.count { return }
            XCTAssertGreaterThan(location, last)
            last = location
        }
        XCTFail("Cursor never reached the end, stopped at \(last)")
    }

    func testSelectionSurvivesViewSwitch() {
        let editor = makeEditor("x **b** y")
        let selection = NSRange(location: 8, length: 1)
        editor.setSelectedRange(selection)
        editor.viewMode = .markdown
        XCTAssertEqual(editor.selectedRange(), selection)
        editor.viewMode = .formatted
        XCTAssertEqual(editor.selectedRange(), selection)
    }

    func testViewSwitchLeavesTextUnchanged() {
        let text = "# A\r\n\r\n- **b**\r\n"
        let editor = makeEditor(text)
        editor.viewMode = .markdown
        editor.viewMode = .formatted
        XCTAssertEqual(editor.string, text)
    }

    func testTypingKeepsStyleMapCurrent() {
        let editor = makeEditor("x")
        editor.setSelectedRange(NSRange(location: 1, length: 0))
        editor.insertText(" **b** z", replacementRange: editor.selectedRange())
        XCTAssertTrue(editor.hidingLayoutManager.isHidden(at: 2))
    }

    func testBoldWrapsSelection() {
        let editor = makeEditor("x b y")
        editor.setSelectedRange(NSRange(location: 2, length: 1))
        editor.toggleWrap(marker: "**")
        XCTAssertEqual(editor.string, "x **b** y")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 4, length: 1))
    }

    func testBoldUnwrapsSelection() {
        let editor = makeEditor("x **b** y")
        editor.setSelectedRange(NSRange(location: 4, length: 1))
        editor.toggleWrap(marker: "**")
        XCTAssertEqual(editor.string, "x b y")
    }

    func testBoldUndoRestoresText() {
        let editor = makeEditor("x b y")
        editor.setSelectedRange(NSRange(location: 2, length: 1))
        editor.toggleWrap(marker: "**")
        editor.undoManager?.undo()
        XCTAssertEqual(editor.string, "x b y")
    }

    func testInsertLinkWrapsSelectionAndSelectsURL() {
        let editor = makeEditor("see b")
        editor.setSelectedRange(NSRange(location: 4, length: 1))
        editor.insertLink()
        XCTAssertEqual(editor.string, "see [b](url)")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 8, length: 3))
    }

    func testToggleTaskBox() {
        let editor = makeEditor("- [ ] todo\n")
        editor.toggleTaskBox(at: 2)
        XCTAssertEqual(editor.string, "- [x] todo\n")
        editor.undoManager?.undo()
        XCTAssertEqual(editor.string, "- [ ] todo\n")
    }

    func testUnderlineDrawnOnlyUnderVisibleLinkText() {
        let editor = makeEditor("[t](http://x) y")
        XCTAssertEqual(editor.hidingLayoutManager.decorations.underlines, [NSRange(location: 1, length: 1)])
        XCTAssertNil(editor.textStorage!.attribute(.underlineStyle, at: 1, effectiveRange: nil))
    }

    func testStrikeDrawnOnlyOverVisibleText() {
        let editor = makeEditor("~~b~~ y")
        XCTAssertEqual(editor.hidingLayoutManager.decorations.strikes, [NSRange(location: 2, length: 1)])
    }

    func testBlankLineBeforeCodeBlockLeavesRoom() {
        let editor = makeEditor("a\n\n```\nx\n```\n\nb\n")
        let style = editor.textStorage!.attribute(.paragraphStyle, at: 2, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertGreaterThan(style?.minimumLineHeight ?? 0, 8)
    }

    func testBlankLineAfterCodeBlockLeavesRoom() {
        let text = "a\n\n```\nx\n```\n\nb\n"
        let editor = makeEditor(text)
        let blank = (text as NSString).range(of: "\n\nb").location + 1
        let style = editor.textStorage!.attribute(.paragraphStyle, at: blank, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertGreaterThan(style?.minimumLineHeight ?? 0, 8)
    }

    func testFreshlyOpenedFileHidesSyntaxAtTheCursor() {
        let editor = makeEditor("# Title\n")
        XCTAssertTrue(editor.hidingLayoutManager.isHidden(at: 0))
    }

    func testMovingCursorIntoHeadingAfterOpeningRevealsIt() {
        let editor = makeEditor("# Title\n\nx\n")
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        XCTAssertFalse(editor.hidingLayoutManager.isHidden(at: 0))
    }

    func testUnderlineOfWrappedLineCoversOnlyTheLink() throws {
        let (_, editor) = EditorTextView.makeInScrollView()
        editor.theme = .terminal
        editor.setFrameSize(NSSize(width: 980, height: 700))
        editor.load(text: "Four days, mostly on foot. **Keep mornings open** and *book ahead*. See [the plan](https://example.com).")
        let layout = editor.hidingLayoutManager
        let rects = layout.lineRects(of: try XCTUnwrap(layout.decorations.underlines.first))
        XCTAssertEqual(rects.count, 1)
        XCTAssertLessThan(try XCTUnwrap(rects.first).width, 120)
    }

    func testCodeBackgroundStartsAtItsFirstVisibleLine() throws {
        let editor = makeEditor("a\n\n```\nx\n```\n\nb\n")
        let layout = editor.hidingLayoutManager
        let block = try XCTUnwrap(layout.decorations.codeBlocks.first)
        let top = try XCTUnwrap(layout.blockRect(of: block)).minY
        let codeGlyph = layout.glyphIndexForCharacter(at: 7)
        XCTAssertEqual(top, layout.lineFragmentRect(forGlyphAt: codeGlyph, effectiveRange: nil).minY)
    }

    func testLoadClearsUndo() {
        let editor = makeEditor("x b y")
        editor.setSelectedRange(NSRange(location: 2, length: 1))
        editor.toggleWrap(marker: "**")
        editor.load(text: "other")
        XCTAssertFalse(editor.undoManager?.canUndo ?? true)
    }
}

final class LayoutDiagnosticsTests: XCTestCase {
    func testHiddenFenceLineAddsNoLineFragment() {
        let (_, editor) = EditorTextView.makeInScrollView()
        editor.load(text: "a\n\n```\nx\ny\n```\n\nb\n")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        let layout = editor.hidingLayoutManager
        layout.ensureLayout(for: editor.textContainer!)
        var fragments: [NSRange] = []
        layout.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layout.numberOfGlyphs)) { _, _, _, glyphs, _ in
            fragments.append(glyphs)
        }
        // a, blank, x, y, blank, b
        XCTAssertEqual(fragments.count, 6, "\(fragments)")
    }
}
