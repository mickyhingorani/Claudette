import Foundation
import Testing
@testable import ClaudetteCore

private func r(_ location: Int, _ length: Int) -> NSRange { NSRange(location: location, length: length) }

private func entry(_ id: String) -> GuideEntry {
    MarkdownGuide.sections.flatMap(\.entries).first { $0.id == id }!
}

private func insert(_ id: String, into text: String, at selection: NSRange) -> (text: String, selection: NSRange) {
    let result = MarkdownGuide.insertion(of: entry(id), in: text, selection: selection)
    let changed = (text as NSString).replacingCharacters(in: result.edit.range, with: result.edit.replacement)
    return (changed, result.selection)
}

@Suite struct MarkdownGuideTests {
    @Test func guideCoversTheBasics() {
        let ids = Set(MarkdownGuide.sections.flatMap(\.entries).map(\.id))
        for id in ["heading1", "bold", "italic", "strikethrough", "link", "image", "bullet", "numbered", "task",
                   "quote", "callout", "inlineCode", "codeBlock", "table", "rule"] {
            #expect(ids.contains(id), "\(id)")
        }
    }

    @Test func boldGoesAtTheCaretWithItsWordSelected() {
        let result = insert("bold", into: "Say hi", at: r(4, 0))
        #expect(result.text == "Say **bold**hi")
        #expect(result.selection == r(6, 4))
    }

    @Test func boldWrapsTheSelection() {
        let result = insert("bold", into: "Say hi now", at: r(4, 2))
        #expect(result.text == "Say **hi** now")
        #expect(result.selection == r(6, 2))
    }

    @Test func linkSelectsItsText() {
        let result = insert("link", into: "", at: r(0, 0))
        #expect(result.text == "[link text](https://example.com)")
        #expect(result.selection == r(1, 9))
    }

    @Test func headingOnAnEmptyLineGoesRightThere() {
        let result = insert("heading2", into: "a\n\n", at: r(3, 0))
        #expect(result.text == "a\n\n## Heading")
        #expect(result.selection == r(6, 7))
    }

    @Test func headingInTheMiddleOfALineStartsANewParagraphBelowIt() {
        let result = insert("heading1", into: "one two\nnext", at: r(3, 0))
        #expect(result.text == "one two\n\n# Heading\nnext")
        #expect(result.selection == r(11, 7))
    }

    @Test func blockIgnoresASelectionAndStartsBelowIt() {
        let result = insert("quote", into: "keep me", at: r(0, 4))
        #expect(result.text == "keep me\n\n> Quote")
    }

    @Test func multiLineBlocksUseTheFilesLineEndings() {
        let result = insert("callout", into: "a\r\n", at: r(3, 0))
        #expect(result.text == "a\r\n> [!NOTE]\r\n> Note text")
    }

    @Test func codeBlockSelectsTheCode() {
        let result = insert("codeBlock", into: "", at: r(0, 0))
        #expect(result.text == "```js\ncode\n```")
        #expect(result.selection == r(6, 4))
    }

    @Test func ruleLeavesTheCaretAfterIt() {
        let result = insert("rule", into: "", at: r(0, 0))
        #expect(result.text == "---")
        #expect(result.selection == r(3, 0))
    }

    @Test func everyEntryLooksLikeWhatItInserts() {
        for entry in MarkdownGuide.sections.flatMap(\.entries) {
            let result = MarkdownGuide.insertion(of: entry, in: "", selection: r(0, 0))
            #expect(result.edit.replacement == entry.markdown, "\(entry.id)")
        }
    }
}
