import AppKit
import XCTest
import ClaudetteCore
@testable import Claudette

@MainActor
final class GuideTests: XCTestCase {
    private func entry(_ id: String) -> GuideEntry {
        MarkdownGuide.sections.flatMap(\.entries).first { $0.id == id }!
    }

    private func makeEditor(_ text: String, selection: NSRange) -> EditorTextView {
        let (_, editor) = EditorTextView.makeInScrollView()
        editor.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        editor.load(text: text)
        editor.setSelectedRange(selection)
        return editor
    }

    func testClickingAnEntryInsertsItAndSelectsTheSampleText() {
        let editor = makeEditor("Hello\n", selection: NSRange(location: 5, length: 0))
        editor.insertGuideEntry(entry("heading2"))
        XCTAssertEqual(editor.string, "Hello\n\n## Heading\n")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 10, length: 7))
    }

    func testInlineEntryWrapsTheSelection() {
        let editor = makeEditor("make this bold", selection: NSRange(location: 10, length: 4))
        editor.insertGuideEntry(entry("bold"))
        XCTAssertEqual(editor.string, "make this **bold**")
    }

    func testInsertUndoesInOneStep() {
        let editor = makeEditor("Hello\n", selection: NSRange(location: 5, length: 0))
        editor.insertGuideEntry(entry("table"))
        editor.undoManager?.undo()
        XCTAssertEqual(editor.string, "Hello\n")
    }

    func testReadOnlyFileGetsNothing() {
        let editor = makeEditor("Hello\n", selection: NSRange(location: 5, length: 0))
        editor.isEditable = false
        editor.insertGuideEntry(entry("bold"))
        XCTAssertEqual(editor.string, "Hello\n")
    }

    func testGuideStartsClosedAndToggles() throws {
        let suite = "ClaudetteGuideTests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let starter = FileManager.default.temporaryDirectory.appendingPathComponent("GuideTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: starter); defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, starterFolder: starter, watchesFolders: false)
        XCTAssertFalse(model.isGuideOpen)
        model.toggleGuide()
        XCTAssertTrue(model.isGuideOpen)
    }
}
