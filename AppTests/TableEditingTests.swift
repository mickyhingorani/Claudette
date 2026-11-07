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

    func testTableSitsBelowTextDirectlyAboveIt() throws {
        let editor = makeEditor("Here are the results:\n| A |\n|---|\n| 1 |\n\nAfter\n")
        let overlay = try XCTUnwrap(editor.tableOverlays.first)
        let layout = editor.hidingLayoutManager
        let baseline = layout.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).minY + layout.location(forGlyphAt: 0).y + editor.textContainerOrigin.y
        XCTAssertGreaterThan(overlay.frame.minY, baseline)
        let after = layout.glyphIndexForCharacter(at: (editor.string as NSString).range(of: "After").location)
        XCTAssertGreaterThanOrEqual(layout.lineFragmentRect(forGlyphAt: after, effectiveRange: nil).minY + editor.textContainerOrigin.y, overlay.frame.maxY)
    }

    func testTableUsesThemeColors() throws {
        let editor = makeEditor("| A |\n|---|\n| **b** |\n")
        editor.theme = .nord
        let overlay = try XCTUnwrap(editor.tableOverlays.first)
        let palette = Theme.nord.palette
        XCTAssertEqual(overlay.strings[0][0].attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, palette.tableHeaderText)
        XCTAssertEqual(overlay.strings[1][0].attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, palette.strong)
    }

    func testCaretOnLineAboveTableIsNotTableHeight() {
        let editor = makeEditor("Here\n| A |\n|---|\n| 1 |\n| 2 |\n| 3 |\n\nAfter\n")
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        let layout = editor.hidingLayoutManager
        var range = NSRange()
        let used = layout.lineFragmentUsedRect(forGlyphAt: 2, effectiveRange: &range)
        XCTAssertLessThan(used.height, 40)
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
        // Past the table and the hidden blank line after it, to the next paragraph.
        XCTAssertEqual(editor.selectedRange().location, (text as NSString).range(of: "After").location)
    }

    func testCursorSkipsBackwardOverTable() {
        let editor = makeEditor(text)
        editor.setSelectedRange(NSRange(location: tableEnd + 1, length: 0))
        editor.setSelectedRange(NSRange(location: tableStart + 3, length: 0))
        // Past the table and the hidden blank line before it, to the end of the paragraph above.
        XCTAssertEqual(editor.selectedRange().location, tableStart - 2)
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
        let manager = NSFontManager.shared
        let headerFont = manager.convert(manager.convert(Theme.default.bodyFont, toSize: (Theme.default.bodyFont.pointSize * 0.94).rounded()), toHaveTrait: .boldFontMask)
        let word = ("Price" as NSString).size(withAttributes: [.font: headerFont]).width
        XCTAssertGreaterThanOrEqual(overlay.columnWidths[2], word + 20)
        XCTAssertLessThanOrEqual(overlay.gridSize.width, 680)
    }

    // Real events sent through a window, the way clicks and keys arrive in the app.

    private func windowed(_ text: String) -> (NSWindow, EditorTextView) {
        let (scroll, editor) = EditorTextView.makeInScrollView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scroll
        scroll.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        editor.setFrameSize(NSSize(width: 800, height: 600))
        editor.load(text: text)
        editor.positionTableOverlays()
        window.makeFirstResponder(editor)
        return (window, editor)
    }

    /// Sends a click to the view the window would pick. A window in the background
    /// swallows its first click, so `sendEvent` can't be used here.
    private func click(_ window: NSWindow, at point: NSPoint) {
        func event(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                               context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        let root = window.contentView!.superview!
        let target = root.hitTest(root.convert(point, from: nil))
        NSApp.postEvent(event(.leftMouseUp), atStart: false)
        target?.mouseDown(with: event(.leftMouseDown))
    }

    func testClickOnCellOpensItForEditing() throws {
        let (window, editor) = windowed(text)
        let overlay = try XCTUnwrap(editor.tableOverlays.first)
        let cell = NSPoint(x: 20, y: overlay.bounds.height - 12)
        click(window, at: overlay.convert(cell, to: nil))
        XCTAssertEqual(overlay.editingCell?.row, 1)
        XCTAssertEqual(overlay.editingCell?.column, 0)
    }

    func testClickOnCheckboxTogglesIt() throws {
        let (window, editor) = windowed("Intro\n\n- [ ] todo\n")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        let layout = editor.hidingLayoutManager
        let glyph = layout.glyphIndexForCharacter(at: 7)
        let rect = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: editor.textContainer!)
        let point = NSPoint(x: rect.midX + editor.textContainerOrigin.x, y: rect.midY + editor.textContainerOrigin.y)
        click(window, at: editor.convert(point, to: nil))
        XCTAssertEqual(editor.string, "Intro\n\n- [x] todo\n")
    }

    func testCommandBEventBoldsSelection() {
        let (window, editor) = windowed("x b y")
        editor.setSelectedRange(NSRange(location: 2, length: 1))
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber,
                                     context: nil, characters: "b", charactersIgnoringModifiers: "b", isARepeat: false, keyCode: 11)
        XCTAssertTrue(editor.performKeyEquivalent(with: event!))
        XCTAssertEqual(editor.string, "x **b** y")
    }

    func testTypedKeyEventEntersText() {
        let (window, editor) = windowed("ab")
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                     context: nil, characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8)
        window.sendEvent(event!)
        XCTAssertEqual(editor.string, "abc")
    }
}
