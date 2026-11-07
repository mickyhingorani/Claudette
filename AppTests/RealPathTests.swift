import AppKit
import XCTest
import ClaudetteCore
@testable import Claudette

/// Tests that go through a real window, a live cell field, and real actions,
/// because calling the undo manager or commit methods directly hides what users hit.
@MainActor
final class RealPathTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    private var window: NSWindow!
    private let undoAction = Selector(("undo:"))
    private let redoAction = Selector(("redo:"))
    private let tableText = "| A | B |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\n"

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = UUID().uuidString
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        window = nil
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    private func makeModel() -> AppModel {
        let model = AppModel(defaults: defaults, starterFolder: root, watchesFolders: false)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = model.scrollView
        model.scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        model.editor.setFrameSize(NSSize(width: 800, height: 600))
        window.makeFirstResponder(model.editor)
        return model
    }

    @discardableResult
    private func write(_ text: String, _ name: String = "a.md") throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

    private func open(_ model: AppModel, _ url: URL) {
        model.refresh()
        model.open(url)
        model.editor.positionTableOverlays()
    }

    private func typeInCell(_ overlay: TableOverlayView, _ text: String) throws {
        let fieldEditor = try XCTUnwrap(overlay.editingField?.currentEditor() as? NSTextView)
        fieldEditor.selectAll(nil)
        fieldEditor.insertText(text, replacementRange: fieldEditor.selectedRange())
    }

    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 4) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        return condition()
    }

    // MARK: Undo

    func testUndoActionUndoesTyping() throws {
        let model = makeModel()
        open(model, try write("ab"))
        model.editor.setSelectedRange(NSRange(location: 2, length: 0))
        model.editor.insertText("c", replacementRange: model.editor.selectedRange())
        XCTAssertTrue(model.editor.tryToPerform(undoAction, with: nil))
        XCTAssertEqual(model.editor.string, "ab")
    }

    func testRedoActionRestoresTyping() throws {
        let model = makeModel()
        open(model, try write("ab"))
        model.editor.setSelectedRange(NSRange(location: 2, length: 0))
        model.editor.insertText("c", replacementRange: model.editor.selectedRange())
        model.editor.tryToPerform(undoAction, with: nil)
        model.editor.tryToPerform(redoAction, with: nil)
        XCTAssertEqual(model.editor.string, "abc")
    }

    func testUndoIsSavedToFile() throws {
        let model = makeModel()
        let file = try write("ab")
        open(model, file)
        model.editor.setSelectedRange(NSRange(location: 2, length: 0))
        model.editor.insertText("c", replacementRange: model.editor.selectedRange())
        model.saveNow()
        model.editor.tryToPerform(undoAction, with: nil)
        model.saveNow()
        XCTAssertEqual(try read(file), "ab")
    }

    func testUndoMenuItemEnablesAfterTyping() throws {
        let model = makeModel()
        open(model, try write("ab"))
        let item = NSMenuItem(title: "Undo", action: undoAction, keyEquivalent: "z")
        XCTAssertFalse(model.editor.validateMenuItem(item))
        model.editor.setSelectedRange(NSRange(location: 2, length: 0))
        model.editor.insertText("c", replacementRange: model.editor.selectedRange())
        XCTAssertTrue(model.editor.validateMenuItem(item))
    }

    func testAppMenuUndoGoesThroughTheResponderChain() throws {
        let items = (NSApp.mainMenu?.items ?? []).flatMap { $0.submenu?.items ?? [] }
        let undo = try XCTUnwrap(items.first { $0.title.hasPrefix("Undo") })
        XCTAssertEqual(undo.action, undoAction)
        XCTAssertNil(undo.target)
    }

    func testUndoInOpenCellLeavesDocumentAlone() throws {
        let model = makeModel()
        open(model, try write("x\n\n" + tableText))
        model.editor.setSelectedRange(NSRange(location: 1, length: 0))
        model.editor.insertText("y", replacementRange: model.editor.selectedRange())
        let overlay = try XCTUnwrap(model.editor.tableOverlays.first)
        overlay.beginEditing(row: 1, column: 0)
        let responder = try XCTUnwrap(window.firstResponder)
        responder.tryToPerform(undoAction, with: nil)
        XCTAssertTrue(model.editor.string.hasPrefix("xy"))
    }

    // MARK: Open cells

    func testOpenCellSurvivesFileDeletedOutside() throws {
        let model = makeModel()
        let file = try write(tableText)
        open(model, file)
        try XCTUnwrap(model.editor.tableOverlays.first).beginEditing(row: 1, column: 0)
        try FileManager.default.removeItem(at: file)
        model.refresh()
        XCTAssertNil(model.currentFile)
    }

    func testOpenCellSurvivesTrash() throws {
        let model = makeModel()
        let file = try write(tableText)
        open(model, file)
        let overlay = try XCTUnwrap(model.editor.tableOverlays.first)
        overlay.beginEditing(row: 1, column: 0)
        try typeInCell(overlay, "typed")
        model.trash(file)
        XCTAssertNil(model.currentFile)
    }

    func testOpenCellLeavesOutsideRewriteAlone() throws {
        let model = makeModel()
        let file = try write(tableText)
        open(model, file)
        try XCTUnwrap(model.editor.tableOverlays.first).beginEditing(row: 1, column: 0)
        try write("Claude rewrote this file completely")
        model.refresh()
        window.makeFirstResponder(nil)
        model.flush()
        XCTAssertEqual(try read(file), "Claude rewrote this file completely")
    }

    func testTypedCellAndOutsideRewriteKeepsBoth() throws {
        let model = makeModel()
        let file = try write(tableText, "Name.md")
        open(model, file)
        let overlay = try XCTUnwrap(model.editor.tableOverlays.first)
        overlay.beginEditing(row: 1, column: 0)
        try typeInCell(overlay, "typed")
        try write("theirs", "Name.md")
        model.refresh()
        XCTAssertTrue(try read(file).contains("| typed | 2 |"))
        XCTAssertEqual(try read(root.appendingPathComponent("Name (conflict).md")), "theirs")
    }

    func testCellInSecondTableStaysSafeWhenFirstTableGoes() throws {
        let model = makeModel()
        let two = "| X |\n|---|\n| 9 |\n\n" + tableText
        let file = try write(two)
        open(model, file)
        try XCTUnwrap(model.editor.tableOverlays.last).beginEditing(row: 1, column: 0)
        try write(tableText)
        model.refresh()
        window.makeFirstResponder(nil)
        model.flush()
        XCTAssertEqual(try read(file), tableText)
    }

    func testCellEndsNormallyWhenFocusLeaves() throws {
        let model = makeModel()
        let file = try write(tableText)
        open(model, file)
        let overlay = try XCTUnwrap(model.editor.tableOverlays.first)
        overlay.beginEditing(row: 1, column: 0)
        try typeInCell(overlay, "typed")
        window.makeFirstResponder(model.editor)
        model.flush()
        XCTAssertTrue(try read(file).contains("| typed | 2 |"))
    }

    func testCellTextAutosavesWhileCellStaysOpen() throws {
        let model = makeModel()
        let file = try write(tableText)
        open(model, file)
        let overlay = try XCTUnwrap(model.editor.tableOverlays.first)
        overlay.beginEditing(row: 1, column: 0)
        try typeInCell(overlay, "typed")
        XCTAssertTrue(waitUntil { (try? self.read(file))?.contains("| typed | 2 |") == true })
        XCTAssertNotNil(overlay.editingCell)
    }

    func testSwitchingToMarkdownKeepsCellText() throws {
        let model = makeModel()
        open(model, try write(tableText))
        let overlay = try XCTUnwrap(model.editor.tableOverlays.first)
        overlay.beginEditing(row: 1, column: 0)
        try typeInCell(overlay, "typed")
        model.viewMode = .markdown
        XCTAssertTrue(model.editor.string.contains("| typed | 2 |"))
    }

    func testRightClickCommitsOpenCellBeforeRowDelete() throws {
        let model = makeModel()
        open(model, try write(tableText))
        let overlay = try XCTUnwrap(model.editor.tableOverlays.first)
        overlay.beginEditing(row: 2, column: 0)
        try typeInCell(overlay, "typed")
        let point = overlay.convert(NSPoint(x: 20, y: 50), to: nil)
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                       context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        _ = overlay.menu(for: event)
        XCTAssertNil(overlay.editingCell)
        XCTAssertTrue(model.editor.string.contains("| typed | 4 |"))
    }

    // MARK: Files

    func testFileThatStopsBeingUTF8BecomesReadOnly() throws {
        let model = makeModel()
        let file = try write("ok")
        open(model, file)
        try Data([0x63, 0xE9]).write(to: file)
        model.refresh()
        XCTAssertFalse(model.editor.isEditable)
        XCTAssertNotNil(model.notice)
    }

    func testFileThatBecomesUTF8IsEditableAgain() throws {
        let model = makeModel()
        let file = root.appendingPathComponent("a.md")
        try Data([0x63, 0xE9]).write(to: file)
        open(model, file)
        try Data("fixed".utf8).write(to: file)
        model.refresh()
        XCTAssertTrue(model.editor.isEditable)
        XCTAssertNil(model.notice)
    }

    func testNonUTF8FileRefusesEdits() throws {
        let model = makeModel()
        let file = root.appendingPathComponent("a.md")
        let bytes = Data([0x63, 0xE9])
        try bytes.write(to: file)
        open(model, file)
        XCTAssertFalse(model.editor.applyEdit(NSRange(location: 0, length: 0), "x"))
        model.flush()
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testBlankNewFileDoesNotBlockOpeningAnother() throws {
        let model = makeModel()
        let file = try write("real")
        model.refresh()
        model.newFile()
        model.editor.applyEdit(NSRange(location: 0, length: 0), " ")
        model.open(file)
        XCTAssertEqual(model.currentFile, file)
    }

    func testSaveNoticeClearsWhenASaveWorks() throws {
        let model = makeModel()
        let file = try write("a")
        open(model, file)
        model.editor.applyEdit(NSRange(location: 1, length: 0), "b")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: file.path)
        model.saveNow()
        XCTAssertNotNil(model.notice)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        model.saveNow()
        XCTAssertNil(model.notice)
        XCTAssertEqual(try read(file), "ab")
    }

    func testQuitAsksWhenTextCouldNotBeSaved() throws {
        let model = makeModel()
        let file = try write("a")
        open(model, file)
        model.editor.applyEdit(NSRange(location: 1, length: 0), "b")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: file.path)
        var asked = false
        XCTAssertFalse(model.shouldQuit { asked = true; return false })
        XCTAssertTrue(asked)
    }

    func testQuitDoesNotAskWhenEverythingSaved() throws {
        let model = makeModel()
        open(model, try write("a"))
        model.editor.applyEdit(NSRange(location: 1, length: 0), "b")
        XCTAssertTrue(model.shouldQuit { XCTFail("Should not ask"); return false })
    }

    func testBOMSurvivesEditThroughTheEditor() throws {
        let model = makeModel()
        let text = "\u{FEFF}# T\r\n\r\nbody\r\n"
        let file = try write(text)
        open(model, file)
        model.editor.applyEdit(NSRange(location: (text as NSString).length, length: 0), "x")
        model.flush()
        XCTAssertEqual(try Data(contentsOf: file), Data((text + "x").utf8))
    }

    // MARK: Typing around tables

    private func typeAtEnd(_ text: String, _ typed: String) throws -> String {
        let model = makeModel()
        open(model, try write(text))
        model.editor.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        model.editor.insertText(typed, replacementRange: NSRange(location: NSNotFound, length: 0))
        return model.editor.string
    }

    func testTypingBelowTableWithFinalNewlineStartsParagraph() throws {
        XCTAssertEqual(try typeAtEnd("| a |\n|---|\n| 1 |\n", "h"), "| a |\n|---|\n| 1 |\n\nh")
    }

    func testTypingAfterTableWithoutFinalNewlineStartsParagraph() throws {
        XCTAssertEqual(try typeAtEnd("| a |\n|---|\n| 1 |", "h"), "| a |\n|---|\n| 1 |\n\nh")
    }

    func testTypingBelowTableKeepsCRLF() throws {
        XCTAssertEqual(try typeAtEnd("| a |\r\n|---|\r\n| 1 |\r\n", "h"), "| a |\r\n|---|\r\n| 1 |\r\n\r\nh")
    }

    func testTypingBelowAParagraphIsUnchanged() throws {
        XCTAssertEqual(try typeAtEnd("text\n", "h"), "text\nh")
    }

    func testCaretLeavesTableWhenSwitchingToFormatted() throws {
        let model = makeModel()
        open(model, try write("x\n\n" + tableText + "\nend\n"))
        model.viewMode = .markdown
        model.editor.setSelectedRange(NSRange(location: 8, length: 0))
        model.viewMode = .formatted
        let table = try XCTUnwrap(model.editor.tableOverlays.first).table.range
        XCTAssertFalse(NSLocationInRange(model.editor.selectedRange().location, table))
    }

    // MARK: Focus

    func testEditorHasFocusWhenShown() {
        let model = AppModel(defaults: defaults, starterFolder: root, watchesFolders: false)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = model.scrollView
        XCTAssertTrue(waitUntil { self.window.firstResponder === model.editor })
    }
}
