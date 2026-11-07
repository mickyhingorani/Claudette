import Foundation
import Testing
@testable import ClaudetteCore

private func r(_ location: Int, _ length: Int) -> NSRange { NSRange(location: location, length: length) }
private func hidden(_ text: String) -> [NSRange] {
    MarkdownScanner.scan(text).hidden.map(\.range).sorted { $0.location < $1.location }
}

@Suite struct MarkdownScannerTests {
    @Test func strongHidesFourMarkers() {
        let map = MarkdownScanner.scan("a **b** c")
        #expect(map.hidden.map(\.range) == [r(2, 2), r(5, 2)])
        #expect(map.hidden.allSatisfy { $0.owner == r(2, 5) })
        #expect(map.spans.contains(StyledSpan(range: r(2, 5), kind: .strong)))
    }

    @Test func emphasisHidesTwoMarkers() {
        #expect(hidden("a *b* c") == [r(2, 1), r(4, 1)])
    }

    @Test func strikethroughHidesTildes() {
        #expect(hidden("~~b~~") == [r(0, 2), r(3, 2)])
    }

    @Test func headingHidesHashAndSpace() {
        let map = MarkdownScanner.scan("## Title\n")
        #expect(map.hidden == [HiddenRange(range: r(0, 3), owner: r(0, 8), kind: .headingMark)])
        #expect(map.spans.contains(StyledSpan(range: r(0, 8), kind: .heading(level: 2))))
    }

    @Test func setextHeadingHidesNothing() {
        let map = MarkdownScanner.scan("Title\n===\n")
        #expect(map.hidden.isEmpty)
        #expect(map.spans.contains { $0.kind == .heading(level: 1) })
    }

    @Test func linkHidesBracketsAndURL() {
        let map = MarkdownScanner.scan("[t](http://x)")
        #expect(map.hidden.map(\.range) == [r(0, 1), r(2, 11)])
        #expect(map.spans.contains(StyledSpan(range: r(0, 13), kind: .link(url: "http://x"))))
    }

    @Test func linkWithBracketInTextFindsItsOwnEnd() {
        #expect(hidden("[a [b] c](u)") == [r(0, 1), r(8, 4)])
    }

    @Test func inlineCodeHidesBackticks() {
        #expect(hidden("x `c` y") == [r(2, 1), r(4, 1)])
    }

    @Test func fenceLinesHidden() {
        let map = MarkdownScanner.scan("```\ncode\n```\nnext\n")
        #expect(map.hidden.map(\.range) == [r(0, 4), r(8, 4)])
        #expect(map.hidden.allSatisfy { $0.kind == .fenceLine && $0.owner == r(0, 12) })
        #expect(map.spans.contains(StyledSpan(range: r(0, 12), kind: .codeBlock)))
    }

    @Test func unclosedFenceHidesOnlyOpening() {
        #expect(hidden("```\ncode") == [r(0, 4)])
    }

    @Test func bulletSubstituted() {
        let map = MarkdownScanner.scan("- item\n")
        #expect(map.substitutions == [Substitution(range: r(0, 1), glyph: "•", owner: r(0, 1))])
    }

    @Test func orderedMarkerStaysVisible() {
        let map = MarkdownScanner.scan("1. item\n")
        #expect(map.substitutions.isEmpty)
        #expect(map.hidden.isEmpty)
        #expect(map.spans.contains(StyledSpan(range: r(0, 2), kind: .listItem)))
    }

    @Test func taskBoxChecked() {
        let map = MarkdownScanner.scan("- [x] done\n")
        #expect(map.taskBoxes == [TaskBox(range: r(2, 3), isChecked: true, owner: r(0, 5))])
        #expect(map.substitutions == [Substitution(range: r(0, 5), glyph: "☑", owner: r(0, 5))])
        #expect(map.hidden.isEmpty)
    }

    @Test func taskBoxUnchecked() {
        let map = MarkdownScanner.scan("- [ ] todo\n")
        #expect(map.taskBoxes == [TaskBox(range: r(2, 3), isChecked: false, owner: r(0, 5))])
        #expect(map.substitutions.first?.glyph == "☐")
    }

    @Test func blockquoteHidesEachLinePrefix() {
        #expect(hidden("> a\n> b\n") == [r(0, 2), r(4, 2)])
    }

    @Test func strongInsideBlockquoteIsExact() {
        #expect(hidden("> x\n> **b**\n") == [r(0, 2), r(4, 2), r(6, 2), r(9, 2)])
    }

    @Test func strongInsideListIsExact() {
        #expect(hidden("- a\n  **b**\n") == [r(6, 2), r(9, 2)])
    }

    @Test func thematicBreakHidden() {
        let map = MarkdownScanner.scan("a\n\n---\n\nb\n")
        #expect(map.hidden.map(\.range) == [r(3, 3)])
        #expect(map.spans.contains(StyledSpan(range: r(3, 3), kind: .thematicBreak)))
    }

    @Test func imageStaysAsDimmedSource() {
        let map = MarkdownScanner.scan("![a](b.png)")
        #expect(map.hidden.isEmpty)
        #expect(map.spans.contains(StyledSpan(range: r(0, 11), kind: .image)))
    }

    @Test func frontmatterDimmedNotParsed() {
        let map = MarkdownScanner.scan("---\na: b\n---\n# T\n")
        #expect(map.spans.contains(StyledSpan(range: r(0, 12), kind: .frontmatter)))
        #expect(!map.spans.contains { $0.kind == .thematicBreak })
        #expect(map.hidden.map(\.range) == [r(13, 2)])
    }

    @Test func dashesLaterAreNotFrontmatter() {
        #expect(!MarkdownScanner.scan("x\n---\na\n---\n").spans.contains { $0.kind == .frontmatter })
    }

    @Test func rangesExactAfterEmoji() {
        #expect(hidden("😀 **b**") == [r(3, 2), r(6, 2)])
    }

    @Test func rangesExactWithCRLF() {
        #expect(hidden("a\r\n\r\n**b**") == [r(5, 2), r(8, 2)])
    }

    @Test func rangesExactWithBOM() {
        #expect(hidden("\u{FEFF}# T") == [r(1, 2)])
    }

    @Test func nestedEmphasisInStrong() {
        #expect(hidden("**a *b* c**") == [r(0, 2), r(4, 1), r(6, 1), r(9, 2)])
    }

    @Test func emptyTextHasEmptyMap() {
        #expect(MarkdownScanner.scan("") == StyleMap())
    }
}
