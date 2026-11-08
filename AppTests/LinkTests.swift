import AppKit
import XCTest
@testable import Claudette

@MainActor
final class LinkTests: XCTestCase {
    private func makeEditor() -> (EditorTextView, opened: () -> [URL], documents: () -> [URL], refused: () -> [String]) {
        let (_, editor) = EditorTextView.makeInScrollView()
        editor.documentFolder = URL(fileURLWithPath: "/Users/someone/Notes", isDirectory: true)
        var opened: [URL] = []
        var documents: [URL] = []
        var refused: [String] = []
        editor.openExternally = { opened.append($0) }
        editor.onOpenDocument = { documents.append($0) }
        editor.onRefusedLink = { refused.append($0) }
        return (editor, { opened }, { documents }, { refused })
    }

    func testWebLinkOpensInTheBrowser() {
        let (editor, opened, _, _) = makeEditor()
        editor.followLink("https://example.com")
        XCTAssertEqual(opened(), [URL(string: "https://example.com")!])
    }

    func testMarkdownLinkOpensInClaudette() {
        let (editor, opened, documents, _) = makeEditor()
        editor.followLink("plan.md")
        XCTAssertEqual(documents(), [URL(fileURLWithPath: "/Users/someone/Notes/plan.md")])
        XCTAssertTrue(opened().isEmpty)
    }

    func testScriptLinkIsRefused() {
        let (editor, opened, documents, refused) = makeEditor()
        editor.followLink("file:///Users/someone/run.command")
        XCTAssertTrue(opened().isEmpty)
        XCTAssertTrue(documents().isEmpty)
        XCTAssertEqual(refused(), ["file:///Users/someone/run.command"])
    }
}
