import AppKit
import XCTest
@testable import Claudette

/// Return starts a paragraph in the formatted view, and the blank line between paragraphs shows as a gap.
@MainActor
final class ParagraphTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() {
        windows.forEach { $0.close() }
        windows = []
    }

    private func makeEditor(_ text: String, caret: Int = 0) -> EditorTextView {
        let (scroll, editor) = EditorTextView.makeInScrollView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        windows.append(window)
        editor.load(text: text)
        editor.setSelectedRange(NSRange(location: caret, length: 0))
        return editor
    }

    private func caret(_ editor: EditorTextView, at location: Int) -> NSRect {
        editor.setSelectedRange(NSRange(location: location, length: 0))
        editor.layoutManager!.ensureLayout(for: editor.textContainer!)
        let screen = editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: nil)
        return editor.convert(editor.window!.convertFromScreen(screen), from: nil)
    }

    private var caretLocation: (EditorTextView) -> Int { { $0.selectedRange().location } }

    // MARK: Showing paragraphs

    func testBreakBetweenParagraphsIsHidden() {
        let editor = makeEditor("a\n\nb")
        XCTAssertTrue(editor.hidingLayoutManager.isHidden(at: 1))
        XCTAssertFalse(editor.hidingLayoutManager.isHidden(at: 2))
    }

    func testMarkdownViewHidesNoBreak() {
        let editor = makeEditor("a\n\nb")
        editor.viewMode = .markdown
        XCTAssertFalse(editor.hidingLayoutManager.isHidden(at: 1))
    }

    func testParagraphGapIsMoreThanALineBreakAndLessThanABlankLine() {
        let paragraphs = makeEditor("a\n\nb")
        let gap = caret(paragraphs, at: 3).minY - caret(paragraphs, at: 0).minY
        let lines = makeEditor("a\nb")
        let line = caret(lines, at: 2).minY - caret(lines, at: 0).minY
        XCTAssertGreaterThan(gap, line * 1.3)
        XCTAssertLessThan(gap, line * 1.75)
    }

    func testExtraBlankLinesStayVisible() {
        let editor = makeEditor("a\n\n\nb")
        XCTAssertFalse(editor.hidingLayoutManager.isHidden(at: 3))
        let gap = caret(editor, at: 4).minY - caret(editor, at: 0).minY
        let single = makeEditor("a\n\nb")
        XCTAssertGreaterThan(gap, caret(single, at: 3).minY - caret(single, at: 0).minY + 10)
    }

    // MARK: The caret skips the break

    func testRightArrowCrossesBreakInOneStep() {
        let editor = makeEditor("a\n\nb", caret: 1)
        editor.moveRight(nil)
        XCTAssertEqual(caretLocation(editor), 3)
    }

    func testLeftArrowCrossesBreakInOneStep() {
        let editor = makeEditor("a\n\nb", caret: 3)
        editor.moveLeft(nil)
        XCTAssertEqual(caretLocation(editor), 1)
    }

    func testCaretNeverRestsOnTheHiddenBlankLine() {
        let editor = makeEditor("a\n\nb")
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        XCTAssertEqual(caretLocation(editor), 1)
    }

    func testDownArrowGoesToNextParagraph() {
        let editor = makeEditor("a\n\nb", caret: 0)
        editor.moveDown(nil)
        XCTAssertEqual(caretLocation(editor), 3)
    }

    func testUpArrowGoesToPreviousParagraph() {
        let editor = makeEditor("a\n\nb", caret: 3)
        editor.moveUp(nil)
        XCTAssertLessThanOrEqual(caretLocation(editor), 1)
    }

    func testCrlfBreakIsSkippedToo() {
        let editor = makeEditor("a\r\n\r\nb", caret: 1)
        editor.moveRight(nil)
        XCTAssertEqual(caretLocation(editor), 5)
    }

    // MARK: Return and Shift-Return

    func testReturnStartsANewParagraph() {
        let editor = makeEditor("ab", caret: 2)
        editor.insertNewline(nil)
        XCTAssertEqual(editor.string, "ab\n\n")
        XCTAssertEqual(caretLocation(editor), 4)
    }

    func testReturnSplitsAParagraph() {
        let editor = makeEditor("abcd", caret: 2)
        editor.insertNewline(nil)
        XCTAssertEqual(editor.string, "ab\n\ncd")
        XCTAssertEqual(caretLocation(editor), 4)
    }

    func testTypingAfterReturnMakesTwoParagraphs() {
        let editor = makeEditor("ab", caret: 2)
        editor.insertNewline(nil)
        editor.insertText("c", replacementRange: editor.selectedRange())
        XCTAssertEqual(editor.string, "ab\n\nc")
    }

    func testReturnUsesTheFilesLineEnding() {
        let editor = makeEditor("a\r\nb", caret: 4)
        editor.insertNewline(nil)
        XCTAssertEqual(editor.string, "a\r\nb\r\n\r\n")
    }

    func testShiftReturnBreaksTheLineInsideAParagraph() {
        let editor = makeEditor("abcd", caret: 2)
        editor.insertLineBreak(nil)
        XCTAssertEqual(editor.string, "ab\ncd")
    }

    func testReturnInCodeIsAPlainNewline() {
        let editor = makeEditor("```\nab\n```\n", caret: 6)
        editor.insertNewline(nil)
        XCTAssertEqual(editor.string, "```\nab\n\n```\n")
    }

    func testReturnInAListStartsTheNextItem() {
        let editor = makeEditor("- a", caret: 3)
        editor.insertNewline(nil)
        XCTAssertEqual(editor.string, "- a\n- ")
    }

    func testReturnInMarkdownViewIsAPlainNewline() {
        let editor = makeEditor("ab", caret: 2)
        editor.viewMode = .markdown
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        editor.insertNewline(nil)
        XCTAssertEqual(editor.string, "ab\n")
    }

    func testReturnOnAnEmptyLineAddsOneLine() {
        let editor = makeEditor("a\n\n", caret: 3)
        editor.insertNewline(nil)
        XCTAssertEqual(editor.string, "a\n\n\n")
    }

    func testReturnUndoesInOneStep() {
        let editor = makeEditor("ab", caret: 2)
        editor.insertNewline(nil)
        editor.undoManager?.undo()
        XCTAssertEqual(editor.string, "ab")
    }

    func testCaretOnNewParagraphIsFullSize() {
        let editor = makeEditor("ab", caret: 2)
        let before = caret(editor, at: 2).height
        editor.insertNewline(nil)
        XCTAssertEqual(caret(editor, at: caretLocation(editor)).height, before, accuracy: 1)
    }

    // MARK: Joining paragraphs

    func testBackspaceAtParagraphStartJoinsIt() {
        let editor = makeEditor("a\n\nb", caret: 3)
        editor.deleteBackward(nil)
        XCTAssertEqual(editor.string, "ab")
        XCTAssertEqual(caretLocation(editor), 1)
    }

    func testDeleteAtParagraphEndJoinsTheNext() {
        let editor = makeEditor("a\n\nb", caret: 1)
        editor.deleteForward(nil)
        XCTAssertEqual(editor.string, "ab")
        XCTAssertEqual(caretLocation(editor), 1)
    }

    func testBackspaceBeforeAListItemKeepsItsMarker() {
        let editor = makeEditor("- a\n\n- b", caret: 5)
        editor.deleteBackward(nil)
        XCTAssertEqual(editor.string, "- a\n- b")
        XCTAssertEqual(editor.selectedRange().location, 4)
    }

    func testBackspaceBeforeANumberedItemKeepsItsNumber() {
        let editor = makeEditor("1. a\n\n2. b", caret: 6)
        editor.deleteBackward(nil)
        XCTAssertEqual(editor.string, "1. a\n2. b")
    }

    func testBackspaceBeforeAQuoteKeepsItsMarker() {
        let editor = makeEditor("Para\n\n> quote", caret: 6)
        editor.deleteBackward(nil)
        XCTAssertEqual(editor.string, "Para\n> quote")
    }

    func testBackspaceBeforeACrlfListItemKeepsItsMarker() {
        let editor = makeEditor("- a\r\n\r\n- b", caret: 7)
        editor.deleteBackward(nil)
        XCTAssertEqual(editor.string, "- a\r\n- b")
    }

    func testDeleteBeforeAListItemKeepsItsMarker() {
        let editor = makeEditor("- a\n\n- b", caret: 3)
        editor.deleteForward(nil)
        XCTAssertEqual(editor.string, "- a\n- b")
    }

    func testBackspaceOnEmptyNewParagraphRemovesIt() {
        let editor = makeEditor("ab", caret: 2)
        editor.insertNewline(nil)
        editor.deleteBackward(nil)
        XCTAssertEqual(editor.string, "ab")
    }
}

@MainActor
final class ParagraphGapTests: XCTestCase {
    func testTableKeepsTheGapBelowIt() throws {
        let (_, editor) = EditorTextView.makeInScrollView()
        editor.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        editor.load(text: "| A |\n|---|\n| 1 |\n\nAfter\n")
        let layout = editor.hidingLayoutManager
        layout.ensureLayout(for: editor.textContainer!)
        let table = try XCTUnwrap(editor.tableOverlays.first)
        let after = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: 19), effectiveRange: nil)
        XCTAssertGreaterThanOrEqual(after.minY - table.gridSize.height, editor.styler.paragraphGap - 0.5)
    }
}
