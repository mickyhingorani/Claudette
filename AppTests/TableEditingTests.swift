import AppKit
import XCTest
@testable import Claudette

final class TableEditingTests: XCTestCase {
    private let text = "Intro\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\nAfter\n"
    private var tableStart: Int { 7 }
    private var tableEnd: Int { 36 }

    private func makeEditor(_ text: String, width: CGFloat = 800) -> EditorTextView {
        let (_, editor) = EditorTextView.makeInScrollView()
        editor.setFrameSize(NSSize(width: width, height: 600))
        editor.load(text: text)
        editor.positionTableOverlays()
        return editor
    }

    func testTableSourceHiddenInFormattedView() {
        let editor = makeEditor(text)
        XCTAssertTrue(editor.hidingLayoutManager.isHidden(at: tableStart + 2))
    }

    func testOverlayExistsOnlyInFormattedView() {
        let editor = makeEditor(text)
        XCTAssertEqual(editor.tableOverlays.count, 1)
        editor.viewMode = .markdown
        XCTAssertEqual(editor.tableOverlays.count, 0)
        XCTAssertFalse(editor.hidingLayoutManager.isHidden(at: tableStart + 2))
    }

    func testTextBelowTableClearsOverlay() throws {
        let editor = makeEditor(text)
        let overlay = try XCTUnwrap(editor.tableOverlays.first)
        let layout = editor.hidingLayoutManager
        let glyph = layout.glyphIndexForCharacter(at: (text as NSString).range(of: "After").location)
        let below = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY + editor.textContainerOrigin.y
        XCTAssertGreaterThanOrEqual(below, overlay.frame.maxY)
        XCTAssertGreaterThan(overlay.frame.height, 40)
    }

    func testNarrowWidthWrapsCellsTaller() throws {
        let long = "| A |\n|---|\n| " + String(repeating: "word ", count: 60) + "|\n"
        let wide = try XCTUnwrap(makeEditor(long, width: 1000).tableOverlays.first).frame.height
        let narrow = try XCTUnwrap(makeEditor(long, width: 320).tableOverlays.first).frame.height
        XCTAssertGreaterThan(narrow, wide)
    }

    func testCursorSkipsForwardOverTable() {
        let editor = makeEditor(text)
        editor.setSelectedRange(NSRange(location: 6, length: 0))
        editor.setSelectedRange(NSRange(location: tableStart + 3, length: 0))
        XCTAssertEqual(editor.selectedRange().location, tableEnd + 1)
    }

    func testCursorSkipsBackwardOverTable() {
        let editor = makeEditor(text)
        editor.setSelectedRange(NSRange(location: tableEnd + 1, length: 0))
        editor.setSelectedRange(NSRange(location: tableStart + 3, length: 0))
        XCTAssertEqual(editor.selectedRange().location, tableStart - 1)
    }

    func testCellEditChangesOnlyThatCell() throws {
        let editor = makeEditor(text)
        let overlay = try XCTUnwrap(editor.tableOverlays.first)
        overlay.beginEditing(row: 1, column: 1)
        overlay.commitEditing(text: "two")
        XCTAssertEqual(editor.string, text.replacingOccurrences(of: "| 1 | 2 |", with: "| 1 | two |"))
    }

    func testCellEditThenUndoRestoresBytes() throws {
        let editor = makeEditor(text)
        let overlay = try XCTUnwrap(editor.tableOverlays.first)
        overlay.beginEditing(row: 1, column: 0)
        overlay.commitEditing(text: "changed")
        editor.undoManager?.undo()
        XCTAssertEqual(editor.string, text)
    }

    func testCellEditReportsTextChange() throws {
        let editor = makeEditor(text)
        var reported: String?
        editor.onTextChange = { reported = $0 }
        let overlay = try XCTUnwrap(editor.tableOverlays.first)
        overlay.beginEditing(row: 1, column: 0)
        overlay.commitEditing(text: "x")
        XCTAssertEqual(reported, editor.string)
    }

    func testTabMovesToNextCell() throws {
        let overlay = try XCTUnwrap(makeEditor(text).tableOverlays.first)
        overlay.beginEditing(row: 1, column: 0)
        overlay.moveToNextCell(committing: "1")
        XCTAssertEqual(overlay.editingCell?.row, 1)
        XCTAssertEqual(overlay.editingCell?.column, 1)
    }

    func testTabInLastCellAddsRow() throws {
        let editor = makeEditor(text)
        let overlay = try XCTUnwrap(editor.tableOverlays.first)
        overlay.beginEditing(row: 1, column: 1)
        overlay.moveToNextCell(committing: "2")
        XCTAssertEqual(overlay.table.rows.count, 2)
        XCTAssertEqual(overlay.editingCell?.row, 2)
        XCTAssertEqual(overlay.editingCell?.column, 0)
    }

    func testSameOverlayKeptAcrossCellEdit() throws {
        let editor = makeEditor(text)
        let overlay = try XCTUnwrap(editor.tableOverlays.first)
        overlay.beginEditing(row: 1, column: 0)
        overlay.commitEditing(text: "x")
        XCTAssertTrue(editor.tableOverlays.first === overlay)
    }

    func testTwoTablesBothDrawn() {
        let editor = makeEditor(text + "\n| C |\n|---|\n| 3 |\n")
        XCTAssertEqual(editor.tableOverlays.count, 2)
        XCTAssertGreaterThan(editor.tableOverlays[1].frame.minY, editor.tableOverlays[0].frame.maxY)
    }

    func testShrinkingNeverBreaksAWord() throws {
        let long = "| Item | Notes | Price |\n|---|---|---:|\n| a | " + String(repeating: "word ", count: 80) + "| 1 |\n"
        let overlay = try XCTUnwrap(makeEditor(long).tableOverlays.first)
        let word = ("Price" as NSString).size(withAttributes: [.font: NSFontManager.shared.convert(Theme.ink.bodyFont, toHaveTrait: .boldFontMask)]).width
        XCTAssertGreaterThanOrEqual(overlay.columnWidths[2], word + 20)
        XCTAssertLessThanOrEqual(overlay.gridSize.width, 680)
    }
}
