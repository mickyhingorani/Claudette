import AppKit
import XCTest
@testable import Claudette

@MainActor
final class CodeLabelTests: XCTestCase {
    private let text = "Intro\n\n```js\nconst a = 1;\nconst b = 2;\n```\n\nAfter\n"

    private func makeEditor(_ text: String, caret: Int = 0) -> EditorTextView {
        let (_, editor) = EditorTextView.makeInScrollView()
        editor.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        editor.load(text: text)
        editor.setSelectedRange(NSRange(location: caret, length: 0))
        editor.layoutManager!.ensureLayout(for: editor.textContainer!)
        editor.positionOverlays()
        return editor
    }

    private func visibleLabels(_ editor: EditorTextView) -> [CodeLabelView] {
        editor.codeLabels.filter { !$0.isHidden }
    }

    func testLabeledBlockShowsItsLanguage() throws {
        let label = try XCTUnwrap(visibleLabels(makeEditor(text)).first)
        XCTAssertEqual(label.language, "JavaScript")
    }

    func testUnlabeledBlockHasNoLabel() {
        XCTAssertTrue(visibleLabels(makeEditor("```\nplain\n```\n")).isEmpty)
    }

    func testLabelHidesWhileTheCaretIsInTheBlock() {
        let editor = makeEditor(text, caret: 15)
        XCTAssertTrue(visibleLabels(editor).isEmpty)
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertEqual(visibleLabels(editor).count, 1)
    }

    func testMarkdownViewHasNoLabels() {
        let editor = makeEditor(text)
        editor.viewMode = .markdown
        XCTAssertTrue(visibleLabels(editor).isEmpty)
    }

    func testCopyPutsJustTheCodeOnTheClipboard() throws {
        let editor = makeEditor(text)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ClaudetteTest-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        editor.copyPasteboard = pasteboard
        let label = try XCTUnwrap(visibleLabels(editor).first)
        label.onCopy?()
        XCTAssertEqual(pasteboard.string(forType: .string), "const a = 1;\nconst b = 2;")
        XCTAssertTrue(label.showsCopied)
    }

    func testLabelSitsInTheBlocksTopRightCorner() throws {
        let editor = makeEditor(text)
        let label = try XCTUnwrap(visibleLabels(editor).first)
        let block = try XCTUnwrap(editor.styler.map.codeBlocks.first)
        let area = try XCTUnwrap(editor.hidingLayoutManager.codeBackgroundRect(of: block.range))
            .offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
        XCTAssertTrue(area.contains(label.frame), "\(label.frame) not in \(area)")
        XCTAssertGreaterThan(label.frame.midX, area.midX)
        XCTAssertLessThan(label.frame.minY - area.minY, 12)
    }

    func testEachLabeledBlockGetsItsOwnLabel() {
        let text = "```py\nx = 1\n```\n\n```html\n<p>hi</p>\n```\n\n```\nplain\n```\n\nend"
        let editor = makeEditor(text, caret: (text as NSString).length)
        XCTAssertEqual(visibleLabels(editor).map(\.language), ["Python", "HTML"])
    }
}
