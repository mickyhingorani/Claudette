import AppKit
import ClaudetteCore

/// Draws a table in place of its hidden source lines, and edits cells in place.
final class TableOverlayView: NSView, NSTextFieldDelegate {
    private static let padX: CGFloat = 10
    private static let padY: CGFloat = 6
    private static let minColumn: CGFloat = 56

    private(set) var table: TableBlock
    private var theme: Theme
    private var availableWidth: CGFloat
    private(set) var columnWidths: [CGFloat] = []
    private var rowHeights: [CGFloat] = []
    private var strings: [[NSAttributedString]] = []
    private var field: NSTextField?
    var editingField: NSTextField? { field }
    private(set) var editingCell: (row: Int, column: Int)?

    var onEdits: (([TextEdit]) -> Void)?
    var onFinishEditing: (() -> Void)?
    /// Called when the text of an open cell changes, so it can be saved while still open.
    var onDraftChange: (() -> Void)?

    override var isFlipped: Bool { true }
    var gridSize: NSSize { NSSize(width: columnWidths.reduce(0, +), height: rowHeights.reduce(0, +)) }

    init(table: TableBlock, theme: Theme, width: CGFloat) {
        self.table = table
        self.theme = theme
        availableWidth = width
        super.init(frame: .zero)
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError("Not used from a nib") }

    func update(table: TableBlock, theme: Theme, width: CGFloat) {
        guard table != self.table || theme != self.theme || width != availableWidth else { return }
        self.table = table
        self.theme = theme
        availableWidth = width
        rebuild()
        positionField()
        needsDisplay = true
    }

    // MARK: Layout

    private var cellFont: NSFont {
        NSFontManager.shared.convert(theme.bodyFont, toSize: (theme.bodyFont.pointSize * 0.94).rounded())
    }

    private func rebuild() {
        strings = (0..<table.rowCount).map { row in
            (0..<table.columnCount).map { column in
                attributed(table.cell(row: row, column: column).displayText, isHeader: row == 0, column: column)
            }
        }
        let natural = (0..<table.columnCount).map { column in
            let widest = strings.map { $0[column].size().width }.max() ?? 0
            return max(Self.minColumn, ceil(widest) + Self.padX * 2)
        }
        let minimum = (0..<table.columnCount).map { column in
            let longestWord = strings.map { Self.longestWordWidth(in: $0[column]) }.max() ?? 0
            return max(Self.minColumn, ceil(longestWord) + Self.padX * 2)
        }
        columnWidths = fit(natural, minimum: minimum)
        rowHeights = strings.map { row in
            let tallest = zip(row, columnWidths).map { string, width in
                string.boundingRect(with: NSSize(width: width - Self.padX * 2, height: .greatestFiniteMagnitude),
                                    options: [.usesLineFragmentOrigin, .usesFontLeading]).height
            }.max() ?? 0
            return ceil(max(tallest, cellFont.pointSize * 1.3)) + Self.padY * 2
        }
    }

    private static func longestWordWidth(in string: NSAttributedString) -> CGFloat {
        var widest: CGFloat = 0
        let text = string.string as NSString
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: .byWords) { _, range, _, _ in
            widest = max(widest, string.attributedSubstring(from: range).size().width)
        }
        return widest
    }

    /// Shrinks columns to the width available, taking from the room above each column's longest word.
    private func fit(_ natural: [CGFloat], minimum: [CGFloat]) -> [CGFloat] {
        let total = natural.reduce(0, +)
        guard total > availableWidth, availableWidth > 0 else { return natural }
        let room = zip(natural, minimum).map { max(0, $0 - $1) }
        let flexible = room.reduce(0, +)
        guard flexible > 0 else { return natural }
        let ratio = min(1, (total - availableWidth) / flexible)
        return zip(natural, room).map { $0 - $1 * ratio }
    }

    private func attributed(_ text: String, isHeader: Bool, column: Int) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        switch table.alignments[column] {
        case .left: paragraph.alignment = .left
        case .center: paragraph.alignment = .center
        case .right: paragraph.alignment = .right
        }
        let manager = NSFontManager.shared
        let font = isHeader ? manager.convert(cellFont, toHaveTrait: .boldFontMask) : cellFont
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: theme.text, .paragraphStyle: paragraph,
        ])
        // A leading word keeps cell text from parsing as a heading or list.
        let prefix = 2
        let map = MarkdownScanner.scan("a " + text)
        func local(_ range: NSRange) -> NSRange { NSRange(location: range.location - prefix, length: range.length) }
        for span in map.spans where span.range.location >= prefix {
            let range = local(span.range)
            guard NSMaxRange(range) <= result.length else { continue }
            switch span.kind {
            case .strong: result.addAttribute(.font, value: manager.convert(font, toHaveTrait: .boldFontMask), range: range)
            case .emphasis: result.addAttribute(.font, value: manager.convert(font, toHaveTrait: .italicFontMask), range: range)
            case .inlineCode: result.addAttribute(.font, value: manager.convert(theme.monoFont, toSize: font.pointSize * 0.9), range: range)
            case .strikethrough: result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            case .link:
                result.addAttribute(.foregroundColor, value: theme.accent, range: range)
                result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            default: break
            }
        }
        for item in map.hidden.reversed() where item.kind == .inline && item.range.location >= prefix {
            let range = local(item.range)
            if NSMaxRange(range) <= result.length { result.deleteCharacters(in: range) }
        }
        return result
    }

    private func cellRect(row: Int, column: Int) -> NSRect {
        NSRect(x: columnWidths[..<column].reduce(0, +), y: rowHeights[..<row].reduce(0, +),
               width: columnWidths[column], height: rowHeights[row])
    }

    private func cell(at point: NSPoint) -> (row: Int, column: Int)? {
        for row in 0..<table.rowCount {
            for column in 0..<table.columnCount where cellRect(row: row, column: column).contains(point) {
                return (row, column)
            }
        }
        return nil
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let size = gridSize
        guard size.width > 0, size.height > 0 else { return }
        let outline = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        theme.panel.setFill()
        NSRect(x: 0, y: 0, width: size.width, height: rowHeights[0]).fill()
        theme.line.setFill()
        var y: CGFloat = 0
        for height in rowHeights.dropLast() {
            y += height
            NSRect(x: 0, y: y, width: size.width, height: 1).fill()
        }
        var x: CGFloat = 0
        for width in columnWidths.dropLast() {
            x += width
            NSRect(x: x, y: 0, width: 1, height: size.height).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        theme.line.setStroke()
        outline.lineWidth = 1
        outline.stroke()
        for row in 0..<table.rowCount {
            for column in 0..<table.columnCount {
                let rect = cellRect(row: row, column: column).insetBy(dx: Self.padX, dy: Self.padY)
                strings[row][column].draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
            }
        }
    }

    // MARK: Editing

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let target = cell(at: point) else { return }
        commitCurrentEdit()
        beginEditing(row: target.row, column: target.column)
    }

    func beginEditing(row: Int, column: Int) {
        editingCell = (row, column)
        let field = NSTextField(string: table.cell(row: row, column: column).displayText)
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = theme.chip
        field.textColor = theme.text
        field.font = cellFont
        field.focusRingType = .none
        field.usesSingleLineMode = false
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.delegate = self
        addSubview(field)
        self.field = field
        positionField()
        window?.makeFirstResponder(field)
    }

    private func positionField() {
        guard let editing = editingCell, let field else { return }
        guard editing.row < table.rowCount, editing.column < table.columnCount else {
            endField()
            return
        }
        field.frame = cellRect(row: editing.row, column: editing.column).insetBy(dx: Self.padX - 4, dy: Self.padY - 2)
    }

    private func endField() {
        let old = field
        field = nil
        editingCell = nil
        // Delegate first: ending the field must not commit into text that may have changed.
        old?.delegate = nil
        old?.abortEditing()
        old?.removeFromSuperview()
    }

    private var fieldText: String? {
        (field?.currentEditor() as? NSTextView)?.string ?? field?.stringValue
    }

    /// Closes the cell without applying its text, for when the document underneath is replaced.
    func discardEditing() {
        endField()
    }

    /// The edits the open cell would make if it were committed now.
    var draftEdits: [TextEdit] {
        guard let editing = editingCell, let text = fieldText,
              editing.row < table.rowCount, editing.column < table.columnCount else { return [] }
        return TableEditor.setCell(table, row: editing.row, column: editing.column, text: text)
    }

    func controlTextDidChange(_ notification: Notification) {
        onDraftChange?()
    }

    func commitEditing(text: String) {
        guard let editing = editingCell else { return }
        endField()
        guard editing.row < table.rowCount, editing.column < table.columnCount else { return }
        let edits = TableEditor.setCell(table, row: editing.row, column: editing.column, text: text)
        if !edits.isEmpty { onEdits?(edits) }
    }

    func commitCurrentEdit() {
        if let text = fieldText { commitEditing(text: text) }
    }

    func moveToNextCell(committing text: String) {
        guard let editing = editingCell else { return }
        commitEditing(text: text)
        if editing.column + 1 < table.columnCount {
            beginEditing(row: editing.row, column: editing.column + 1)
            return
        }
        if editing.row + 1 >= table.rowCount {
            onEdits?(TableEditor.addRow(table, after: table.rowCount - 1))
        }
        beginEditing(row: editing.row + 1, column: 0)
    }

    private func moveToPreviousCell(committing text: String) {
        guard let editing = editingCell else { return }
        commitEditing(text: text)
        if editing.column > 0 {
            beginEditing(row: editing.row, column: editing.column - 1)
        } else if editing.row > 0 {
            beginEditing(row: editing.row - 1, column: table.columnCount - 1)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        let text = textView.string
        switch selector {
        case #selector(NSResponder.insertTab(_:)):
            moveToNextCell(committing: text)
        case #selector(NSResponder.insertBacktab(_:)):
            moveToPreviousCell(committing: text)
        case #selector(NSResponder.insertNewline(_:)):
            commitEditing(text: text)
            onFinishEditing?()
        case #selector(NSResponder.cancelOperation(_:)):
            endField()
            onDraftChange?()
            onFinishEditing?()
        default:
            return false
        }
        return true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        commitCurrentEdit()
    }

    // MARK: Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        // An open cell's position would go stale if a row or column changes under it.
        commitCurrentEdit()
        guard let target = cell(at: convert(event.locationInWindow, from: nil)) else { return nil }
        let menu = NSMenu()
        func add(_ title: String, enabled: Bool = true, edits: @escaping () -> [TextEdit]) {
            let item = TableMenuItem(title: title, action: #selector(runMenuItem(_:)), keyEquivalent: "")
            item.target = self
            item.edits = edits
            item.isEnabled = enabled
            menu.addItem(item)
        }
        menu.autoenablesItems = false
        let table = self.table
        add("Add Row Below") { TableEditor.addRow(table, after: target.row) }
        add("Delete Row", enabled: target.row > 0) { TableEditor.deleteRow(table, row: target.row) }
        menu.addItem(.separator())
        add("Add Column Right") { TableEditor.addColumn(table, after: target.column) }
        add("Delete Column", enabled: table.columnCount > 1) { TableEditor.deleteColumn(table, column: target.column) }
        return menu
    }

    @objc private func runMenuItem(_ item: TableMenuItem) {
        if let edits = item.edits?(), !edits.isEmpty { onEdits?(edits) }
    }
}

private final class TableMenuItem: NSMenuItem {
    var edits: (() -> [TextEdit])?
}
