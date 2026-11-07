import AppKit
import XCTest
@testable import Claudette

/// The caret's real position and size, measured in a window as the text view reports them.
@MainActor
final class CaretTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() {
        windows.forEach { $0.close() }
        windows = []
    }

    private func makeEditor(_ text: String) -> EditorTextView {
        let (scroll, editor) = EditorTextView.makeInScrollView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        windows.append(window)
        editor.load(text: text)
        return editor
    }

    private func caret(_ editor: EditorTextView, at location: Int) -> NSRect {
        editor.setSelectedRange(NSRange(location: location, length: 0))
        return caret(editor)
    }

    private func caret(_ editor: EditorTextView) -> NSRect {
        editor.layoutManager!.ensureLayout(for: editor.textContainer!)
        let screen = editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: nil)
        return editor.convert(editor.window!.convertFromScreen(screen), from: nil)
    }

    private func textHeight(_ editor: EditorTextView, at location: Int) -> CGFloat {
        let font = editor.textStorage!.attribute(.font, at: location, effectiveRange: nil) as! NSFont
        return font.ascender - font.descender
    }

    // MARK: Moving above a heading

    func testUpArrowLeavesHeadingForParagraphAbove() {
        let editor = makeEditor("intro\n\n# Title\n")
        editor.setSelectedRange(NSRange(location: 9, length: 0))
        editor.moveUp(nil)
        XCTAssertLessThanOrEqual(editor.selectedRange().location, 5)
    }

    func testUpArrowLeavesHeadingForTextLineAbove() {
        let editor = makeEditor("intro\n# Title\n")
        editor.setSelectedRange(NSRange(location: 8, length: 0))
        editor.moveUp(nil)
        XCTAssertLessThanOrEqual(editor.selectedRange().location, 5)
    }

    func testUpArrowWalksPastHeadingToTopOfDocument() {
        let editor = makeEditor("\n\n# Title\nbody\n")
        editor.setSelectedRange(NSRange(location: 10, length: 0))
        for _ in 0..<5 { editor.moveUp(nil) }
        XCTAssertEqual(editor.selectedRange().location, 0)
    }

    func testDownArrowStillEntersHeadingAfterItsMark() {
        let editor = makeEditor("intro\n\n# Title\n")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.moveDown(nil)
        XCTAssertEqual(editor.selectedRange().location, 9)
    }

    func testCaretAtHeadingStartSitsOnTheHeadingLine() {
        let editor = makeEditor("intro\n\n# Title\n")
        let atStart = caret(editor, at: 9)
        let inside = caret(editor, at: 10)
        XCTAssertEqual(atStart.minY, inside.minY, accuracy: 0.5)
        XCTAssertEqual(atStart.height, inside.height, accuracy: 0.5)
    }

    func testCaretAtHeadingStartUnderTextSitsOnTheHeadingLine() {
        let editor = makeEditor("intro\n# Title\n")
        let atStart = caret(editor, at: 8)
        let inside = caret(editor, at: 9)
        XCTAssertEqual(atStart.minY, inside.minY, accuracy: 0.5)
        XCTAssertLessThan(atStart.minX, inside.minX)
    }

    // MARK: Blank lines

    func testBlankLineIsFullHeightWithCaretElsewhere() {
        let editor = makeEditor("a\n\nb\n")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertEqual(lineHeight(editor, at: 2), lineHeight(editor, at: 0), accuracy: 0.5)
    }

    func testParagraphsAddNoSpaceOfTheirOwn() {
        let editor = makeEditor("a\nb\n")
        let style = editor.textStorage!.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(style?.paragraphSpacing, 0)
    }

    // MARK: Caret size

    /// The system draws the caret when the selection changes, so the line under it must
    /// already have its final height by then.
    func testBlankLineIsFullHeightWhenSelectionChangeIsAnnounced() {
        let editor = makeEditor("a\n\nb\n")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        var height: CGFloat = 0
        let observer = NotificationCenter.default.addObserver(forName: NSTextView.didChangeSelectionNotification, object: editor, queue: nil) { _ in
            MainActor.assumeIsolated { height = self.lineHeight(editor, at: 2) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        XCTAssertGreaterThan(height, 16)
    }

    func testNewBlankLineIsFullHeightWhenSelectionChangeIsAnnounced() {
        let editor = makeEditor("a\nb\n")
        editor.setSelectedRange(NSRange(location: 1, length: 0))
        editor.insertNewline(nil)
        var height: CGFloat = 0
        let observer = NotificationCenter.default.addObserver(forName: NSTextView.didChangeSelectionNotification, object: editor, queue: nil) { _ in
            MainActor.assumeIsolated { height = self.lineHeight(editor, at: editor.selectedRange().location) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        editor.insertNewline(nil)
        XCTAssertGreaterThan(height, 16)
    }

    private func lineHeight(_ editor: EditorTextView, at location: Int) -> CGFloat {
        let layout = editor.hidingLayoutManager
        layout.ensureLayout(for: editor.textContainer!)
        let glyph = layout.glyphIndexForCharacter(at: location)
        return layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).height
    }

    func testCaretMatchesBodyText() {
        let editor = makeEditor("plain body text\n")
        XCTAssertEqual(caret(editor, at: 3).height, textHeight(editor, at: 3), accuracy: 1)
    }

    func testCaretMatchesHeadingText() {
        let editor = makeEditor("before\n\n# Title\n")
        XCTAssertEqual(caret(editor, at: 12).height, textHeight(editor, at: 12), accuracy: 1)
    }

    func testCaretMatchesCodeText() {
        let editor = makeEditor("```\nlet a = 1\n```\n")
        XCTAssertEqual(caret(editor, at: 6).height, textHeight(editor, at: 6), accuracy: 1)
    }

    func testCaretOnBlankLineMatchesBodyText() {
        let editor = makeEditor("a\n\nb\n")
        XCTAssertEqual(caret(editor, at: 2).height, textHeight(editor, at: 0), accuracy: 1)
    }

    func testCaretAtEndOfDocumentMatchesBodyText() {
        let editor = makeEditor("a\n")
        XCTAssertEqual(caret(editor, at: 2).height, textHeight(editor, at: 0), accuracy: 1)
    }

    func testCaretInMarkdownViewMatchesText() {
        let editor = makeEditor("# Title\n")
        editor.viewMode = .markdown
        XCTAssertEqual(caret(editor, at: 3).height, textHeight(editor, at: 3), accuracy: 1)
    }

    func testCaretSitsOnTheTextNotInItsLineSpacing() {
        let editor = makeEditor("plain body text\n")
        let layout = editor.hidingLayoutManager
        let rect = caret(editor, at: 3)
        let font = editor.textStorage!.attribute(.font, at: 3, effectiveRange: nil) as! NSFont
        let glyph = layout.glyphIndexForCharacter(at: 3)
        let fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let baseline = fragment.minY + layout.location(forGlyphAt: glyph).y + editor.textContainerOrigin.y
        XCTAssertEqual(rect.minY, baseline - font.ascender, accuracy: 1)
    }

    // MARK: Below a code block

    private func codeBottom(_ editor: EditorTextView) throws -> CGFloat {
        let blocks = editor.styler.decorations.codeBlocks
        let range = try XCTUnwrap(blocks.first)
        return try XCTUnwrap(editor.hidingLayoutManager.codeBackgroundRect(of: range)).maxY + editor.textContainerOrigin.y
    }

    func testCaretOnTextRightBelowCodeClearsItsBackground() throws {
        let editor = makeEditor("```\nlet a = 1\n```\nafter\n")
        let rect = caret(editor, at: 19)
        XCTAssertGreaterThanOrEqual(rect.minY, try codeBottom(editor))
    }

    func testTextUnderBlankLineBelowCodeClearsItsBackground() throws {
        let editor = makeEditor("```\nlet a = 1\n```\n\nafter\n")
        let rect = caret(editor, at: 21)
        XCTAssertGreaterThanOrEqual(rect.minY, try codeBottom(editor))
    }

    func testCaretOnRevealedClosingFenceStaysInsideBackground() throws {
        let editor = makeEditor("```\nlet a = 1\n```\n\nafter\n")
        let rect = caret(editor, at: 16)
        XCTAssertLessThanOrEqual(rect.maxY, try codeBottom(editor))
    }

    func testCaretAtEndOfDocumentBelowCodeClearsItsBackground() throws {
        let editor = makeEditor("```\nlet a = 1\n```\n")
        let rect = caret(editor, at: 18)
        XCTAssertGreaterThanOrEqual(rect.minY, try codeBottom(editor))
    }
}

@MainActor
final class CodeFenceTests: XCTestCase {
    private func makeEditor(_ text: String, caret: Int) -> EditorTextView {
        let (_, editor) = EditorTextView.makeInScrollView()
        editor.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        editor.load(text: text)
        editor.setSelectedRange(NSRange(location: caret, length: 0))
        return editor
    }

    func testReturnAfterOpeningFenceAddsClosingFence() {
        let editor = makeEditor("intro\n```html", caret: 13)
        editor.insertNewline(nil)
        XCTAssertEqual(editor.string, "intro\n```html\n\n```")
        XCTAssertEqual(editor.selectedRange().location, 14)
    }

    func testTypingAfterAutoClosedFenceStaysInTheBlock() {
        let editor = makeEditor("```", caret: 3)
        editor.insertNewline(nil)
        editor.insertText("x", replacementRange: editor.selectedRange())
        XCTAssertEqual(editor.string, "```\nx\n```")
        XCTAssertEqual(editor.styler.map.codeBlocks.first?.isClosed, true)
    }

    func testAutoClosedFenceMatchesTheOpeningOne() {
        let editor = makeEditor("  ~~~~py\nrest", caret: 8)
        editor.insertNewline(nil)
        XCTAssertEqual(editor.string, "  ~~~~py\n\n  ~~~~\nrest")
    }

    func testReturnAfterFenceOfClosedBlockAddsNothing() {
        let editor = makeEditor("```\nx\n```\n", caret: 3)
        editor.insertNewline(nil)
        XCTAssertEqual(editor.string, "```\n\nx\n```\n")
    }

    func testReturnAfterClosingFenceAddsNothing() {
        let editor = makeEditor("```\nx\n```", caret: 9)
        editor.insertNewline(nil)
        XCTAssertEqual(editor.string, "```\nx\n```\n")
    }

    func testAutoCloseUndoesInOneStep() {
        let editor = makeEditor("```", caret: 3)
        editor.insertNewline(nil)
        editor.undoManager?.undo()
        XCTAssertEqual(editor.string, "```")
    }
}
