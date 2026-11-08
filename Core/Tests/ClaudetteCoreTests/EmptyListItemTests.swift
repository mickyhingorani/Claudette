import Foundation
import Testing
@testable import ClaudetteCore

private func r(_ location: Int, _ length: Int) -> NSRange { NSRange(location: location, length: length) }
private func items(_ text: String) -> [NSRange] {
    MarkdownScanner.scan(text).spans.filter { $0.kind == .listItem }.map(\.range)
}
private func headings(_ text: String) -> [StyledSpan] {
    MarkdownScanner.scan(text).spans.filter { if case .heading = $0.kind { return true } else { return false } }
}

/// A list item that's still empty, just after Return or Tab, reads as a list item, so the
/// line above doesn't turn into a heading and the marker shows as a bullet.
@Suite struct EmptyListItemTests {
    @Test func emptyNestedBulletIsAnItem() {
        #expect(items("- a\n  - ") == [r(0, 1), r(6, 1)])
        #expect(headings("- a\n  - ").isEmpty)
    }

    @Test func emptyBulletAfterAParagraphIsAnItem() {
        #expect(items("Text\n- ") == [r(5, 1)])
        #expect(headings("Text\n- ").isEmpty)
    }

    @Test func emptyNestedNumberIsAnItem() {
        #expect(items("1. a\n   1. ").count == 2)
    }

    @Test func emptyItemWithCrlfIsAnItem() {
        #expect(items("- a\r\n  - \r\n") == [r(0, 1), r(7, 1)])
    }

    @Test func dashUnderlineWithoutASpaceIsStillAHeading() {
        #expect(headings("Title\n-").count == 1)
    }

    @Test func textAfterAnEmptyItemKeepsItsPositions() {
        let map = MarkdownScanner.scan("- a\n  - \n\n**b**")
        #expect(map.hidden.contains { $0.range == r(10, 2) })
    }
}

@Suite struct NestedBulletTests {
    private func glyphs(_ text: String) -> [String] { MarkdownScanner.scan(text).substitutions.map(\.glyph) }

    @Test func topLevelBulletIsSolid() { #expect(glyphs("- a") == ["•"]) }
    @Test func nestedBulletIsHollow() { #expect(glyphs("- a\n  - b") == ["•", "◦"]) }
    @Test func deeperBulletIsASquare() { #expect(glyphs("- a\n  - b\n    - c") == ["•", "◦", "▪"]) }
    @Test func bulletUnderANumberIsHollow() { #expect(glyphs("1. a\n   - b") == ["◦"]) }
    @Test func emptyNestedBulletIsHollowToo() { #expect(glyphs("- a\n  - ") == ["•", "◦"]) }
}

@Suite struct LineIndexClampTests {
    @Test func columnPastALinesEndStopsThere() {
        let index = LineIndex("ab\ncd")
        #expect(index.offset(line: 1, utf8Column: 9) == 2)
    }
}

@Suite struct EmptyCheckboxTests {
    @Test func emptyCheckboxIsACheckbox() {
        #expect(MarkdownScanner.scan("- [ ] a\n- [ ] ").taskBoxes.count == 2)
    }

    @Test func emptyNestedCheckboxIsACheckbox() {
        #expect(MarkdownScanner.scan("- [ ] a\n  - [ ] ").taskBoxes.count == 2)
    }
}
