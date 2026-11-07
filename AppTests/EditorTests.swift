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

    func testFreshlyOpenedFileHidesSyntaxAtTheCursor() {
        let editor = makeEditor("# Title\n")
        XCTAssertTrue(editor.hidingLayoutManager.isHidden(at: 0))
    }

    func testHeadingMarkStaysHiddenWithCursorInHeading() {
        let editor = makeEditor("# Title\n\nx\n")
        editor.setSelectedRange(NSRange(location: 5, length: 0))
        XCTAssertTrue(editor.hidingLayoutManager.isHidden(at: 0))
    }

    func testTypingAHeadingHidesItsMark() {
        let editor = makeEditor("")
        editor.insertText("# Title", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.hidingLayoutManager.isHidden(at: 0))
    }

    func testCaretEntersHeadingAfterItsMark() {
        let editor = makeEditor("a\n# T\n")
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        XCTAssertEqual(editor.selectedRange().location, 4)
    }

    func testCaretAtStartOfDocumentSkipsHeadingMark() {
        let editor = makeEditor("## T\n")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertEqual(editor.selectedRange().location, 3)
    }

    func testLeftArrowFromHeadingStartGoesToLineAbove() {
        let editor = makeEditor("a\n# T\n")
        editor.setSelectedRange(NSRange(location: 4, length: 0))
        editor.moveLeft(nil)
        XCTAssertEqual(editor.selectedRange().location, 1)
    }

    func testBackspaceAtHeadingStartTurnsItIntoPlainText() {
        let editor = makeEditor("## T\n")
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        editor.deleteBackward(nil)
        XCTAssertEqual(editor.string, "T\n")
        editor.undoManager?.undo()
        XCTAssertEqual(editor.string, "## T\n")
    }

    func testMarkdownViewCaretMovesFreelyInHeadingMark() {
        let editor = makeEditor("## T\n")
        editor.viewMode = .markdown
        editor.setSelectedRange(NSRange(location: 1, length: 0))
        XCTAssertEqual(editor.selectedRange().location, 1)
        XCTAssertFalse(editor.hidingLayoutManager.isHidden(at: 0))
    }

    func testEveryThemeHidesHeadingMarks() {
        for theme in Theme.all {
            let editor = makeEditor("# T\n\nx\n")
            editor.theme = theme
            editor.setSelectedRange(NSRange(location: 2, length: 0))
            XCTAssertTrue(editor.hidingLayoutManager.isHidden(at: 0), theme.name)
        }
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

    private func color(_ editor: EditorTextView, at index: Int) -> NSColor? {
        editor.textStorage?.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
    }

    private func themed(_ text: String, _ theme: Theme = .nord) -> EditorTextView {
        let editor = makeEditor(text)
        editor.theme = theme
        return editor
    }

    func testHeadingsUseThemeColors() {
        let editor = themed("# A\n\n## B\n\n### C\n")
        let p = Theme.nord.palette
        XCTAssertEqual(color(editor, at: 2), p.heading1)
        XCTAssertEqual(color(editor, at: 8), p.heading2)
        XCTAssertEqual(color(editor, at: 15), p.heading3)
    }

    func testBoldAndItalicUseThemeColors() {
        let editor = themed("**a** and *b*")
        XCTAssertEqual(color(editor, at: 2), Theme.nord.palette.strong)
        XCTAssertEqual(color(editor, at: 11), Theme.nord.palette.emphasis)
    }

    func testLinkAndInlineCodeUseThemeColors() {
        let editor = themed("[a](u) `b`")
        XCTAssertEqual(color(editor, at: 1), Theme.nord.palette.link)
        XCTAssertEqual(color(editor, at: 8), Theme.nord.palette.inlineCode)
    }

    func testCheckboxUsesThemeColor() {
        XCTAssertEqual(color(themed("- [x] a\n"), at: 0), Theme.nord.palette.check)
    }

    func testMarkdownViewKeepsDocumentRolesPlain() {
        let editor = themed("**a**")
        editor.viewMode = .markdown
        XCTAssertEqual(color(editor, at: 2), Theme.nord.text)
    }

    func testCodeBlockTokensUseThemeColors() {
        let editor = themed("```js\nconst a = 1;\n```\n")
        XCTAssertEqual(color(editor, at: 6), Theme.nord.palette.keyword)
        XCTAssertEqual(color(editor, at: 16), Theme.nord.palette.number)
    }

    func testCodeIsColoredInMarkdownViewToo() {
        let editor = themed("```js\nconst a = 1;\n```\n")
        editor.viewMode = .markdown
        XCTAssertEqual(color(editor, at: 6), Theme.nord.palette.keyword)
    }

    func testCodeColorsFollowTheTheme() {
        let editor = themed("```js\nconst a = 1;\n```\n")
        editor.theme = .slate
        XCTAssertEqual(color(editor, at: 6), Theme.slate.palette.keyword)
    }

    func testTypingInCodeRecolorsIt() {
        let editor = themed("```js\nx\n```\n")
        editor.setSelectedRange(NSRange(location: 6, length: 1))
        editor.insertText("const a = 1;", replacementRange: editor.selectedRange())
        XCTAssertEqual(color(editor, at: 6), Theme.nord.palette.keyword)
    }

    func testColoringNeverChangesText() {
        let text = "```html\r\n<a href=\"x\">😀</a>\r\n```\r\n"
        XCTAssertEqual(themed(text).string, text)
    }

    func testTypingInALargeCodeBlockStaysFast() {
        let lines = (0..<400).map { "const value\($0) = compute(\($0), 'text');" }.joined(separator: "\n")
        let editor = themed("```js\n\(lines)\n```\n")
        editor.setSelectedRange(NSRange(location: 6, length: 0))
        let start = Date()
        for _ in 0..<10 { editor.insertText("x", replacementRange: editor.selectedRange()) }
        let perKey = Date().timeIntervalSince(start) / 10
        print("PERF per keystroke:", perKey)
        XCTAssertLessThan(perKey, 0.1)
    }

    private func caretHeight(_ editor: EditorTextView) -> CGFloat {
        let layout = editor.hidingLayoutManager
        let glyph = layout.glyphIndexForCharacter(at: editor.selectedRange().location)
        return layout.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil).height
    }

    func testCaretOnBlankLineIsFullHeight() {
        let editor = makeEditor("a\n\nb\n")
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        XCTAssertGreaterThan(caretHeight(editor), 16)
    }

    func testReturnMidDocumentGivesFullHeightCaret() {
        let editor = makeEditor("a\nb\n")
        editor.setSelectedRange(NSRange(location: 1, length: 0))
        editor.insertNewline(nil)
        editor.insertNewline(nil)
        XCTAssertGreaterThan(caretHeight(editor), 16)
    }

    func testBlankLineCaretLeavesTextAlone() {
        let text = "a\r\n\r\nb\r\n"
        let editor = makeEditor(text)
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        XCTAssertEqual(editor.string, text)
        XCTAssertFalse(editor.undoManager?.canUndo ?? true)
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
        // a, x, y, b: the blank lines between paragraphs are hidden too
        XCTAssertEqual(fragments.count, 4, "\(fragments)")
    }
}
