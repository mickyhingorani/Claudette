import Foundation
import Testing
@testable import ClaudetteCore

private func apply(_ edits: [TextEdit], to text: String) -> String {
    let result = NSMutableString(string: text)
    for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
        result.replaceCharacters(in: edit.range, with: edit.replacement)
    }
    return result as String
}

private func table(_ text: String) throws -> TableBlock {
    try #require(MarkdownScanner.scan(text).tables.first)
}

private let basic = "before\n\n| A | B |\n|---|:-:|\n| 1 | 2 |\n| 3 | 4 |\n\nafter\n"

@Suite struct TableTests {
    @Test func findsCells() throws {
        let t = try table(basic)
        #expect(t.header.map(\.text) == ["A", "B"])
        #expect(t.rows.map { $0.map(\.text) } == [["1", "2"], ["3", "4"]])
    }

    @Test func tableRangeCoversAllLines() throws {
        let t = try table(basic)
        #expect((basic as NSString).substring(with: t.range) == "| A | B |\n|---|:-:|\n| 1 | 2 |\n| 3 | 4 |")
    }

    @Test func parsesAlignments() throws {
        let t = try table("| a | b | c |\n|:--|:-:|--:|\n")
        #expect(t.alignments == [.left, .center, .right])
    }

    @Test func noOuterPipes() throws {
        let t = try table("a | b\n--|--\n1 | 2\n")
        #expect(t.rows[0].map(\.text) == ["1", "2"])
    }

    @Test func escapedPipeStaysInCell() throws {
        let t = try table("| a |\n|---|\n| x \\| y |\n")
        #expect(t.rows[0].map(\.text) == ["x \\| y"])
        #expect(t.rows[0][0].displayText == "x | y")
    }

    @Test func shortRowPaddedWithEmptyCells() throws {
        let t = try table("| a | b |\n|---|---|\n| 1 |\n")
        #expect(t.rows[0].count == 2)
        #expect(t.rows[0][1].isPadding)
    }

    @Test func cellRangesExactAfterEmoji() throws {
        let text = "😀\n\n| 😀 | b |\n|---|---|\n| 1 | 2 |\n"
        let t = try table(text)
        #expect((text as NSString).substring(with: t.header[1].textRange) == "b")
    }

    @Test func tableInBlockquoteSkipsPrefix() throws {
        let t = try table("> | a |\n> |---|\n> | 1 |\n")
        #expect(t.rows[0].map(\.text) == ["1"])
    }

    @Test func setCellChangesOnlyThatCell() throws {
        let t = try table(basic)
        let result = apply(TableEditor.setCell(t, row: 1, column: 1, text: "two"), to: basic)
        #expect(result == basic.replacingOccurrences(of: "| 1 | 2 |", with: "| 1 | two |"))
    }

    @Test func setHeaderCell() throws {
        let t = try table(basic)
        #expect(apply(TableEditor.setCell(t, row: 0, column: 0, text: "Z"), to: basic).contains("| Z | B |"))
    }

    @Test func setCellEscapesPipe() throws {
        let t = try table(basic)
        #expect(apply(TableEditor.setCell(t, row: 1, column: 0, text: "x|y"), to: basic).contains("| x\\|y | 2 |"))
    }

    @Test func setCellKeepsExistingEscape() throws {
        let t = try table(basic)
        #expect(apply(TableEditor.setCell(t, row: 1, column: 0, text: "x\\|y"), to: basic).contains("| x\\|y | 2 |"))
    }

    @Test func setCellFlattensNewlines() throws {
        let t = try table(basic)
        #expect(apply(TableEditor.setCell(t, row: 1, column: 0, text: "x\ny"), to: basic).contains("| x y | 2 |"))
    }

    @Test func setEmptyCell() throws {
        let text = "| a | b |\n|---|---|\n|  | 2 |\n"
        let t = try table(text)
        #expect(apply(TableEditor.setCell(t, row: 1, column: 0, text: "x"), to: text) == "| a | b |\n|---|---|\n| x | 2 |\n")
    }

    @Test func clearCellLeavesEmptyCell() throws {
        let t = try table(basic)
        let result = apply(TableEditor.setCell(t, row: 1, column: 0, text: ""), to: basic)
        #expect(try table(result).rows[0].map(\.text) == ["", "2"])
    }

    @Test func setPaddingCellFillsRow() throws {
        let text = "| a | b | c |\n|---|---|---|\n| 1 |\n"
        let t = try table(text)
        let result = apply(TableEditor.setCell(t, row: 1, column: 2, text: "x"), to: text)
        #expect(try table(result).rows[0].map(\.text) == ["1", "", "x"])
    }

    @Test func setPaddingCellWithoutTrailingPipe() throws {
        let text = "a | b\n--|--\n1\n"
        let t = try table(text)
        let result = apply(TableEditor.setCell(t, row: 1, column: 1, text: "x"), to: text)
        #expect(try table(result).rows[0].map(\.text) == ["1", "x"])
    }

    @Test func addRowMatchesColumnCount() throws {
        let t = try table(basic)
        let result = apply(TableEditor.addRow(t, after: 2), to: basic)
        let updated = try table(result)
        #expect(updated.rows.count == 3)
        #expect(updated.rows[2].map(\.text) == ["", ""])
        #expect(result.hasSuffix("\n\nafter\n"))
    }

    @Test func addRowAfterHeaderGoesBelowDelimiter() throws {
        let t = try table(basic)
        #expect(try table(apply(TableEditor.addRow(t, after: 0), to: basic)).rows[0].map(\.text) == ["", ""])
    }

    @Test func addRowKeepsCRLF() throws {
        let text = "| a |\r\n|---|\r\n| 1 |\r\n"
        let t = try table(text)
        #expect(apply(TableEditor.addRow(t, after: 1), to: text) == "| a |\r\n|---|\r\n| 1 |\r\n|  |\r\n")
    }

    @Test func deleteLastBodyRow() throws {
        let t = try table(basic)
        let result = apply(TableEditor.deleteRow(t, row: 2), to: basic)
        #expect(result == basic.replacingOccurrences(of: "\n| 3 | 4 |", with: ""))
    }

    @Test func deleteFirstBodyRow() throws {
        let t = try table(basic)
        let result = apply(TableEditor.deleteRow(t, row: 1), to: basic)
        #expect(result == basic.replacingOccurrences(of: "\n| 1 | 2 |", with: ""))
    }

    @Test func headerRowCannotBeDeleted() throws {
        #expect(TableEditor.deleteRow(try table(basic), row: 0).isEmpty)
    }

    @Test func addColumnKeepsShape() throws {
        let t = try table(basic)
        let updated = try table(apply(TableEditor.addColumn(t, after: 0), to: basic))
        #expect(updated.header.map(\.text) == ["A", "", "B"])
        #expect(updated.rows[1].map(\.text) == ["3", "", "4"])
        #expect(updated.alignments == [.left, .left, .center])
    }

    @Test func addColumnAtEnd() throws {
        let t = try table(basic)
        let updated = try table(apply(TableEditor.addColumn(t, after: 1), to: basic))
        #expect(updated.header.map(\.text) == ["A", "B", ""])
        #expect(updated.rows[0].allSatisfy { !$0.isPadding })
    }

    @Test func deleteMiddleColumn() throws {
        let text = "| a | b | c |\n|---|---|---|\n| 1 | 2 | 3 |\n"
        let t = try table(text)
        #expect(apply(TableEditor.deleteColumn(t, column: 1), to: text) == "| a | c |\n|---|---|\n| 1 | 3 |\n")
    }

    @Test func deleteFirstColumn() throws {
        let t = try table(basic)
        let updated = try table(apply(TableEditor.deleteColumn(t, column: 0), to: basic))
        #expect(updated.header.map(\.text) == ["B"])
    }

    @Test func deleteLastColumn() throws {
        let t = try table(basic)
        let updated = try table(apply(TableEditor.deleteColumn(t, column: 1), to: basic))
        #expect(updated.header.map(\.text) == ["A"])
    }

    @Test func onlyColumnCannotBeDeleted() throws {
        #expect(TableEditor.deleteColumn(try table("| a |\n|---|\n"), column: 0).isEmpty)
    }
}
