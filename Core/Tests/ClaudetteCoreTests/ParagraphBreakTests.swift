import Foundation
import Testing
@testable import ClaudetteCore

private func r(_ location: Int, _ length: Int) -> NSRange { NSRange(location: location, length: length) }
private func breaks(_ text: String) -> [NSRange] { MarkdownScanner.scan(text).paragraphBreaks }

/// A paragraph break is the newline ending a line of text that a blank line follows.
@Suite struct ParagraphBreakTests {
    @Test func blankLineBetweenParagraphs() {
        #expect(breaks("a\n\nb") == [r(1, 1)])
    }

    @Test func crlfBreakTakesBothCharacters() {
        #expect(breaks("a\r\n\r\nb") == [r(1, 2)])
    }

    @Test func onlyTheFirstBlankLineOfARun() {
        #expect(breaks("a\n\n\nb") == [r(1, 1)])
    }

    @Test func singleNewlineIsNoBreak() {
        #expect(breaks("a\nb") == [])
    }

    @Test func blankLineAtTheEndStillBreaks() {
        #expect(breaks("a\n\n") == [r(1, 1)])
    }

    @Test func blankLinesAtTheStartDoNotBreak() {
        #expect(breaks("\n\na") == [])
    }

    @Test func blankLinesInsideCodeDoNotBreak() {
        #expect(breaks("```\na\n\nb\n```\n") == [])
    }

    @Test func codeBlockEndCanBreak() {
        #expect(breaks("```\na\n```\n\nb") == [r(9, 1)])
    }

    @Test func blankLinesInsideFrontmatterDoNotBreak() {
        #expect(breaks("---\na: 1\n\nb: 2\n---\n") == [])
    }

    @Test func breaksShiftPastAByteOrderMark() {
        #expect(breaks("\u{FEFF}a\n\nb") == [r(2, 1)])
    }
}
