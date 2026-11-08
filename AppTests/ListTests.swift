import AppKit
import XCTest
@testable import Claudette

@MainActor
final class ListTests: XCTestCase {
    private func makeEditor(_ text: String, caret: Int, mode: ViewMode = .formatted) -> EditorTextView {
        let (_, editor) = EditorTextView.makeInScrollView()
        editor.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        editor.viewMode = mode
        editor.load(text: text)
        editor.setSelectedRange(NSRange(location: caret, length: 0))
        return editor
    }

    func testReturnContinuesANumberedList() {
        let editor = makeEditor("1. a\n2. b", caret: 4)
        editor.insertNewline(nil)
        XCTAssertEqual(editor.string, "1. a\n2. \n3. b")
        XCTAssertEqual(editor.selectedRange().location, 8)
    }

    func testReturnOnAnEmptyItemEndsTheList() {
        let editor = makeEditor("- a\n- ", caret: 6)
        editor.insertNewline(nil)
        XCTAssertEqual(editor.string, "- a\n\n")
    }

    func testListsContinueInTheMarkdownViewToo() {
        let editor = makeEditor("- a", caret: 3, mode: .markdown)
        editor.insertNewline(nil)
        XCTAssertEqual(editor.string, "- a\n- ")
    }

    func testListMarkersInCodeAreLeftAlone() {
        let editor = makeEditor("```\n- a\n```\n", caret: 7)
        editor.insertNewline(nil)
        XCTAssertEqual(editor.string, "```\n- a\n\n```\n")
    }

    func testANewItemUndoesInOneStep() {
        let editor = makeEditor("1. a\n2. b", caret: 4)
        editor.insertNewline(nil)
        editor.undoManager?.undo()
        XCTAssertEqual(editor.string, "1. a\n2. b")
    }

    func testTabNestsAndShiftTabUnnests() {
        let editor = makeEditor("- a\n- b", caret: 7)
        editor.insertTab(nil)
        XCTAssertEqual(editor.string, "- a\n  - b")
        XCTAssertEqual(editor.selectedRange().location, 9)
        editor.insertBacktab(nil)
        XCTAssertEqual(editor.string, "- a\n- b")
    }

    func testTabOutsideAListStillTypesATab() {
        let editor = makeEditor("text", caret: 4)
        editor.insertTab(nil)
        XCTAssertEqual(editor.string, "text\t")
    }

    func testListsIndentFromTheText() {
        let editor = makeEditor("Text\n\n- item\n", caret: 0)
        let style = editor.textStorage!.attribute(.paragraphStyle, at: 8, effectiveRange: nil) as! NSParagraphStyle
        XCTAssertGreaterThan(style.firstLineHeadIndent, 0)
        XCTAssertGreaterThan(style.headIndent, style.firstLineHeadIndent)
    }

    func testNestedItemsSitClearlyFurtherIn() {
        let editor = makeEditor("- parent\n  - child\n", caret: 0)
        let layout = editor.hidingLayoutManager
        layout.ensureLayout(for: editor.textContainer!)
        func textX(_ index: Int) -> CGFloat { layout.location(forGlyphAt: layout.glyphIndexForCharacter(at: index)).x }
        XCTAssertGreaterThanOrEqual(textX(13) - textX(2), 14)
    }

    func testNestingNeverChangesTheText() {
        let text = "- parent\n  - child\n"
        XCTAssertEqual(makeEditor(text, caret: 0).string, text)
    }
}
