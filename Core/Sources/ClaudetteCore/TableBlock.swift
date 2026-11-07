import Foundation

public struct TableCell: Equatable, Sendable {
    /// The cell's text without surrounding spaces.
    public var textRange: NSRange
    public var text: String
    /// Everything between the cell's pipes.
    public var cellRange: NSRange
    /// True for a cell the row doesn't have in its source.
    public var isPadding: Bool

    /// The text with escaped pipes shown as plain pipes.
    public var displayText: String { text.replacingOccurrences(of: "\\|", with: "|") }
}

public enum TableAlignment: Equatable, Sendable {
    case left, center, right
}

public struct TableBlock: Equatable, Sendable {
    public var range: NSRange
    public var header: [TableCell]
    public var rows: [[TableCell]]
    public var alignments: [TableAlignment]
    public var delimiterCells: [TableCell]
    /// Content range of each row line without its line ending. Index 0 is the header.
    public var rowLines: [NSRange]
    public var delimiterLine: NSRange
    public var rowEndsWithPipe: [Bool]
    public var lineEnding: String
    /// Text before a row's first cell on lines inside a blockquote.
    public var linePrefix: String

    public var columnCount: Int { header.count }
    /// Row 0 is the header.
    public func cell(row: Int, column: Int) -> TableCell { row == 0 ? header[column] : rows[row - 1][column] }
    public var rowCount: Int { rows.count + 1 }
}

extension TableBlock {
    func shifted(by base: Int) -> TableBlock {
        func shift(_ range: NSRange) -> NSRange { NSRange(location: range.location + base, length: range.length) }
        func shiftCell(_ cell: TableCell) -> TableCell {
            var cell = cell
            cell.textRange = shift(cell.textRange)
            cell.cellRange = shift(cell.cellRange)
            return cell
        }
        var block = self
        block.range = shift(range)
        block.header = header.map(shiftCell)
        block.rows = rows.map { $0.map(shiftCell) }
        block.delimiterCells = delimiterCells.map(shiftCell)
        block.rowLines = rowLines.map(shift)
        block.delimiterLine = shift(delimiterLine)
        return block
    }

    static func parse(_ ns: NSString, range: NSRange) -> TableBlock? {
        var lines: [(content: NSRange, cells: [TableCell], endsWithPipe: Bool)] = []
        var lineEnding = "\n"
        var linePrefix = ""
        var location = range.location
        while location < NSMaxRange(range) {
            let full = ns.lineRange(for: NSRange(location: location, length: 0))
            var end = min(NSMaxRange(full), NSMaxRange(range))
            let lineEnd = end
            while end > location, isNewline(ns.character(at: end - 1)) { end -= 1 }
            if lines.isEmpty, NSMaxRange(full) > end {
                lineEnding = ns.substring(with: NSRange(location: end, length: NSMaxRange(full) - end))
            }
            let content = NSRange(location: location, length: end - location)
            let start = cellsStart(ns, in: content)
            if !lines.isEmpty, linePrefix.isEmpty {
                linePrefix = ns.substring(with: NSRange(location: location, length: start - location))
            }
            let (cells, endsWithPipe) = splitCells(ns, from: start, to: end)
            lines.append((content, cells, endsWithPipe))
            location = max(NSMaxRange(full), lineEnd)
        }
        // The parser's range can start at a paragraph directly above the table.
        // The real table starts one line above its delimiter row.
        guard let delimiter = lines.indices.dropFirst().first(where: { isDelimiterRow(lines[$0].cells) }) else { return nil }
        lines.removeFirst(delimiter - 1)
        let tableStart = lines[0].content.location
        let tableRange = NSRange(location: tableStart, length: NSMaxRange(range) - tableStart)
        let header = lines[0].cells
        let bodies = lines.dropFirst(2).map { line -> [TableCell] in
            var cells = Array(line.cells.prefix(header.count))
            let end = NSMaxRange(line.content)
            while cells.count < header.count {
                let empty = NSRange(location: end, length: 0)
                cells.append(TableCell(textRange: empty, text: "", cellRange: empty, isPadding: true))
            }
            return cells
        }
        let rowLines = [lines[0]] + lines.dropFirst(2)
        return TableBlock(
            range: tableRange, header: header, rows: bodies,
            alignments: (0..<header.count).map { index in
                index < lines[1].cells.count ? alignment(of: lines[1].cells[index].text) : .left
            },
            delimiterCells: lines[1].cells,
            rowLines: rowLines.map(\.content), delimiterLine: lines[1].content,
            rowEndsWithPipe: rowLines.map(\.endsWithPipe),
            lineEnding: lineEnding, linePrefix: linePrefix)
    }

    private static func isDelimiterRow(_ cells: [TableCell]) -> Bool {
        !cells.isEmpty && cells.allSatisfy { cell in
            cell.text.contains("-") && cell.text.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private static func isNewline(_ unit: unichar) -> Bool { unit == 0x0A || unit == 0x0D }
    private static func isSpace(_ unit: unichar) -> Bool { unit == 0x20 || unit == 0x09 }

    /// Skips spaces and blockquote marks at the start of a line.
    private static func cellsStart(_ ns: NSString, in content: NSRange) -> Int {
        var offset = content.location
        while offset < NSMaxRange(content), isSpace(ns.character(at: offset)) || ns.character(at: offset) == 0x3E {
            offset += 1
        }
        return offset
    }

    private static func alignment(of delimiter: String) -> TableAlignment {
        switch (delimiter.hasPrefix(":"), delimiter.hasSuffix(":")) {
        case (true, true): return .center
        case (false, true): return .right
        default: return .left
        }
    }

    private static func splitCells(_ ns: NSString, from start: Int, to lineEnd: Int) -> ([TableCell], Bool) {
        var end = lineEnd
        while end > start, isSpace(ns.character(at: end - 1)) { end -= 1 }
        var segmentStart = start
        if segmentStart < end, ns.character(at: segmentStart) == 0x7C { segmentStart += 1 }
        var bounds: [NSRange] = []
        var offset = segmentStart
        var endsWithPipe = false
        while offset < end {
            let unit = ns.character(at: offset)
            if unit == 0x5C {
                offset += 2
                continue
            }
            if unit == 0x7C {
                bounds.append(NSRange(location: segmentStart, length: offset - segmentStart))
                segmentStart = offset + 1
                endsWithPipe = segmentStart == end
            }
            offset += 1
        }
        if !endsWithPipe { bounds.append(NSRange(location: segmentStart, length: end - segmentStart)) }
        return (bounds.map { cell(ns, in: $0) }, endsWithPipe)
    }

    private static func cell(_ ns: NSString, in bounds: NSRange) -> TableCell {
        var start = bounds.location
        var end = NSMaxRange(bounds)
        while start < end, isSpace(ns.character(at: start)) { start += 1 }
        while end > start, isSpace(ns.character(at: end - 1)) { end -= 1 }
        let text = NSRange(location: start, length: end - start)
        return TableCell(textRange: text, text: ns.substring(with: text), cellRange: bounds, isPadding: false)
    }
}
