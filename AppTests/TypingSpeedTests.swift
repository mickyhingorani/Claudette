import AppKit
import XCTest
@testable import Claudette

@MainActor
final class TypingSpeedTests: XCTestCase {
    private func longDocument() -> String {
        let section = "## Section\n\nSome **bold** text with a [link](https://x.com) and `code` here.\n\n- item one\n- [ ] task two\n\n> a quote line\n\n```js\nconst a = 1;\n```\n\n"
        return String(repeating: section, count: 230)
    }

    /// Restyling applies only the attributes that changed, so a keystroke re-lays out
    /// the text around it, not the whole document.
    func testAKeystrokeRelaysOutOnlyNearbyText() {
        let (_, editor) = EditorTextView.makeInScrollView()
        editor.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let text = longDocument()
        editor.load(text: text)
        editor.layoutManager!.ensureLayout(for: editor.textContainer!)
        editor.setSelectedRange(NSRange(location: (text as NSString).length / 2, length: 0))
        editor.hidingLayoutManager.largestInvalidation = 0
        editor.insertText("x", replacementRange: editor.selectedRange())
        XCTAssertLessThan(editor.hidingLayoutManager.largestInvalidation, 2_000)
    }

    func testRestylingStillFollowsTheEdit() {
        let (_, editor) = EditorTextView.makeInScrollView()
        editor.theme = .slate
        editor.load(text: "plain\n")
        editor.insertText("**", replacementRange: NSRange(location: 0, length: 0))
        editor.insertText("**", replacementRange: NSRange(location: 7, length: 0))
        let color = editor.textStorage!.attribute(.foregroundColor, at: 3, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, Theme.slate.palette.strong)
        // "** plain**" is no longer bold.
        editor.insertText(" ", replacementRange: NSRange(location: 2, length: 0))
        let after = editor.textStorage!.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor
        XCTAssertEqual(after, Theme.slate.text, "styles that no longer apply are removed")
    }

    func testRestyleKeepsEveryRunIdenticalToAFullStyle() {
        let (_, editor) = EditorTextView.makeInScrollView()
        let text = longDocument()
        editor.load(text: text)
        editor.insertText("**x**", replacementRange: NSRange(location: 500, length: 0))
        let fresh = NSMutableAttributedString(string: editor.string)
        editor.styler.apply(toScratch: fresh)
        XCTAssertTrue(editor.textStorage!.isEqual(to: fresh))
    }

    /// After each edit, the incrementally styled text must match styling the whole document.
    func testRandomEditsAlwaysMatchAFullRestyle() {
        let pieces = ["**", "*", "`", "```", "```js\n", "\n", "\n\n", "# ", "## ", "- ", "- [ ] ", "1. ", "> ", "> [!NOTE]\n> ",
                      "| a | b |\n|---|---|\n| 1 | 2 |\n", "[x](y)", "![p](q.png)", "~~", "===\n", "word ", "x"]
        var generator = SeededGenerator(seed: 7)
        for theme in [Theme.slate, Theme.terminal] {
            for mode in [ViewMode.formatted, .markdown] {
                let (_, editor) = EditorTextView.makeInScrollView()
                editor.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
                editor.theme = theme
                editor.viewMode = mode
                editor.load(text: longDocument())
                for step in 0..<60 {
                    let length = (editor.string as NSString).length
                    let location = Int.random(in: 0...length, using: &generator)
                    if Bool.random(using: &generator), length > 0 {
                        let count = min(Int.random(in: 1...4, using: &generator), length - min(location, length - 1))
                        editor.applyEdit(NSRange(location: min(location, length - 1), length: max(count, 1)), "")
                    } else {
                        editor.applyEdit(NSRange(location: location, length: 0), pieces.randomElement(using: &generator)!)
                    }
                    let fresh = NSMutableAttributedString(string: editor.string)
                    editor.styler.apply(toScratch: fresh)
                    if !editor.textStorage!.isEqual(to: fresh) {
                        var index = 0
                        let storage = editor.textStorage!
                        while index < storage.length,
                              (storage.attributes(at: index, effectiveRange: nil) as NSDictionary).isEqual(to: fresh.attributes(at: index, effectiveRange: nil)) { index += 1 }
                        let ns = editor.string as NSString
                        let context = ns.substring(with: NSRange(location: max(0, index - 30), length: min(60, ns.length - max(0, index - 30))))
                        let have = storage.attributes(at: index, effectiveRange: nil).map { "\($0.key.rawValue)=\($0.value)" }.sorted()
                        let want = fresh.attributes(at: index, effectiveRange: nil).map { "\($0.key.rawValue)=\($0.value)" }.sorted()
                        XCTFail("\(theme.name) \(mode) step \(step): differs at \(index) in \(context.debugDescription)\nhave \(have.filter { !want.contains($0) })\nwant \(want.filter { !have.contains($0) })\nregion \(editor.styler.lastRestyledRange) blocks \(editor.styler.map.codeBlocks.filter { abs($0.range.location - index) < 400 }.map { "\($0.range) \($0.language ?? "-")" })")
                        return
                    }
                }
            }
        }
    }

    /// Typing in the middle of a long document restyles only text near the edit.
    func testAKeystrokeRestylesOnlyNearbyText() {
        let (_, editor) = EditorTextView.makeInScrollView()
        editor.load(text: longDocument())
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length / 2, length: 0))
        editor.insertText("x", replacementRange: editor.selectedRange())
        XCTAssertLessThan(editor.styler.lastRestyledLength, 1_000)
    }
}

/// A repeatable random source, so a failing sequence of edits can be replayed.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
