import Foundation

/// Table changes as text edits. Everything outside the edits stays exactly as it was.
/// Row 0 is the header. Edits are sorted last-first, so they can be applied in order.
public enum TableEditor {
    public static func setCell(_ table: TableBlock, row: Int, column: Int, text: String) -> [TextEdit] {
        let new = sanitize(text)
        let cell = table.cell(row: row, column: column)
        if cell.isPadding {
            if new.isEmpty { return [] }
            return fillPadding(table, row: row, column: column, text: new)
        }
        if new == cell.text { return [] }
        if cell.text.isEmpty { return [TextEdit(range: cell.cellRange, replacement: " \(new) ")] }
        if new.isEmpty { return [TextEdit(range: cell.cellRange, replacement: "  ")] }
        return [TextEdit(range: cell.textRange, replacement: new)]
    }

    public static func addRow(_ table: TableBlock, after row: Int) -> [TextEdit] {
        let line = row == 0 ? table.delimiterLine : table.rowLines[row]
        let cells = String(repeating: "  |", count: table.columnCount)
        return [TextEdit(range: NSRange(location: NSMaxRange(line), length: 0),
                         replacement: table.lineEnding + table.linePrefix + "|" + cells)]
    }

    public static func deleteRow(_ table: TableBlock, row: Int) -> [TextEdit] {
        guard row >= 1 else { return [] }
        let previous = row == 1 ? table.delimiterLine : table.rowLines[row - 1]
        let start = NSMaxRange(previous)
        return [TextEdit(range: NSRange(location: start, length: NSMaxRange(table.rowLines[row]) - start), replacement: "")]
    }

    public static func addColumn(_ table: TableBlock, after column: Int) -> [TextEdit] {
        var edits: [TextEdit] = []
        func insert(in cells: [TableCell], endsWithPipe: Bool, text: String) {
            let real = cells.filter { !$0.isPadding }
            guard column < real.count else { return }
            let isOpenEnd = column == real.count - 1 && !endsWithPipe
            edits.append(TextEdit(range: NSRange(location: NSMaxRange(real[column].cellRange), length: 0),
                                  replacement: isOpenEnd ? " |\(text)" : "|\(text)"))
        }
        for row in 0..<table.rowCount {
            insert(in: row == 0 ? table.header : table.rows[row - 1], endsWithPipe: table.rowEndsWithPipe[row], text: "  ")
        }
        insert(in: table.delimiterCells, endsWithPipe: table.rowEndsWithPipe[0], text: "---")
        return lastFirst(edits)
    }

    public static func deleteColumn(_ table: TableBlock, column: Int) -> [TextEdit] {
        guard table.columnCount > 1 else { return [] }
        var edits: [TextEdit] = []
        func remove(from cells: [TableCell], endsWithPipe: Bool) {
            let real = cells.filter { !$0.isPadding }
            guard column < real.count else { return }
            let bounds = real[column].cellRange
            // Take one pipe with the cell: the one before it, or after it for the first column.
            // A lone cell with no closing pipe has no pipe after it to take.
            let hasPipeAfter = real.count > 1 || endsWithPipe
            let range: NSRange
            if column > 0 {
                range = NSRange(location: bounds.location - 1, length: bounds.length + 1)
            } else {
                range = NSRange(location: bounds.location, length: bounds.length + (hasPipeAfter ? 1 : 0))
            }
            edits.append(TextEdit(range: range, replacement: ""))
        }
        remove(from: table.header, endsWithPipe: table.rowEndsWithPipe[0])
        remove(from: table.delimiterCells, endsWithPipe: table.rowEndsWithPipe[0])
        for (index, row) in table.rows.enumerated() {
            remove(from: row, endsWithPipe: table.rowEndsWithPipe[index + 1])
        }
        return lastFirst(edits)
    }

    private static func fillPadding(_ table: TableBlock, row: Int, column: Int, text: String) -> [TextEdit] {
        let cells = row == 0 ? table.header : table.rows[row - 1]
        let firstPadding = cells.firstIndex(where: \.isPadding) ?? column
        let gaps = column - firstPadding
        let insertion = table.rowEndsWithPipe[row]
            ? String(repeating: "  |", count: gaps) + " \(text) |"
            : String(repeating: " | ", count: gaps) + " | \(text)"
        return [TextEdit(range: NSRange(location: NSMaxRange(table.rowLines[row]), length: 0), replacement: insertion)]
    }

    private static func sanitize(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\\|", with: "|")
            .replacingOccurrences(of: "|", with: "\\|")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func lastFirst(_ edits: [TextEdit]) -> [TextEdit] {
        edits.sorted { $0.range.location > $1.range.location }
    }
}
