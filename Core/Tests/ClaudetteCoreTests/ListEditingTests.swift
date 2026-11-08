import Foundation
import Testing
@testable import ClaudetteCore

private func r(_ location: Int, _ length: Int) -> NSRange { NSRange(location: location, length: length) }

/// Applies a list action to text with the caret marked by `|`, and returns the result the same way.
private func run(_ marked: String, _ action: (String, NSRange) -> (edits: [TextEdit], selection: NSRange)?) -> String? {
    let caret = (marked as NSString).range(of: "|").location
    let text = (marked as NSString).replacingCharacters(in: r(caret, 1), with: "")
    guard let result = action(text, r(caret, 0)) else { return nil }
    let changed = NSMutableString(string: text)
    for edit in result.edits.sorted(by: { $0.range.location > $1.range.location }) {
        changed.replaceCharacters(in: edit.range, with: edit.replacement)
    }
    changed.insert("|", at: result.selection.location)
    return changed as String
}

private func enter(_ marked: String) -> String? { run(marked, ListEditing.returnEdits) }
private func tab(_ marked: String) -> String? { run(marked) { ListEditing.indentEdits(in: $0, selection: $1, outdent: false) } }
private func backTab(_ marked: String) -> String? { run(marked) { ListEditing.indentEdits(in: $0, selection: $1, outdent: true) } }

@Suite struct ListReturnTests {
    @Test func bulletContinues() { #expect(enter("- a|") == "- a\n- |") }
    @Test func starAndPlusBulletsKeepTheirMark() {
        #expect(enter("* a|") == "* a\n* |")
        #expect(enter("+ a|") == "+ a\n+ |")
    }
    @Test func numberCountsUp() { #expect(enter("1. a|") == "1. a\n2. |") }
    @Test func parenthesisNumbersKeepTheirMark() { #expect(enter("3) a|") == "3) a\n4) |") }
    @Test func laterNumbersMoveUp() { #expect(enter("1. a|\n2. b\n3. c") == "1. a\n2. |\n3. b\n4. c") }
    @Test func renumberingStopsAtTheEndOfTheList() { #expect(enter("1. a|\n2. b\n\npara\n\n1. x") == "1. a\n2. |\n3. b\n\npara\n\n1. x") }
    @Test func renumberingSkipsNestedItems() { #expect(enter("1. a|\n   - n\n2. b") == "1. a\n2. |\n   - n\n3. b") }
    @Test func checkboxContinuesUnchecked() { #expect(enter("- [x] done|") == "- [x] done\n- [ ] |") }
    @Test func numberedCheckboxContinues() { #expect(enter("1. [ ] a|") == "1. [ ] a\n2. [ ] |") }
    @Test func indentationCarriesOver() { #expect(enter("- a\n  - b|") == "- a\n  - b\n  - |") }
    @Test func returnMidItemSplitsIt() { #expect(enter("- ab|cd") == "- ab\n- |cd") }
    @Test func crlfFilesKeepTheirLineEndings() { #expect(enter("- a|\r\n") == "- a\r\n- |\r\n") }

    @Test func emptyItemEndsTheList() { #expect(enter("- a\n- |") == "- a\n\n|") }
    @Test func emptyNumberedItemEndsTheList() { #expect(enter("1. a\n2. |") == "1. a\n\n|") }
    @Test func emptyCheckboxEndsTheList() { #expect(enter("- [ ] a\n- [ ] |") == "- [ ] a\n\n|") }
    @Test func emptyNestedItemMovesOut() { #expect(enter("- a\n  - |") == "- a\n- |") }

    @Test func plainTextIsLeftAlone() { #expect(enter("just text|") == nil) }
    @Test func caretBeforeTheMarkerIsLeftAlone() { #expect(enter("|- a") == nil) }
    @Test func dividerIsNotAList() { #expect(enter("---|") == nil) }
    @Test func dashWithoutASpaceIsNotAList() { #expect(enter("-a|") == nil) }
}

@Suite struct ListIndentTests {
    @Test func tabNestsABullet() { #expect(tab("- a|") == "  - a|") }
    @Test func tabNestsANumberByItsWidth() { #expect(tab("1. a|") == "   1. a|") }
    @Test func shiftTabBringsItBack() { #expect(backTab("  - a|") == "- a|") }
    @Test func shiftTabAtTheTopLevelDoesNothing() { #expect(backTab("- a|") == nil) }
    @Test func tabOutsideAListIsLeftAlone() { #expect(tab("text|") == nil) }
    @Test func tabWorksWithTheCaretAnywhereOnTheLine() { #expect(tab("- a|b") == "  - a|b") }
}
