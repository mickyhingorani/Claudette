import AppKit
import ClaudetteCore

final class EditorTextView: NSTextView, NSTextStorageDelegate {
    private static let columnWidth: CGFloat = 680

    let styler = EditorStyler()
    private let documentUndo = UndoManager()
    var onTextChange: ((String) -> Void)?
    private(set) var tableOverlays: [TableOverlayView] = []

    var hidingLayoutManager: HidingLayoutManager { layoutManager as! HidingLayoutManager }

    var viewMode: ViewMode {
        get { styler.mode }
        set {
            guard newValue != styler.mode else { return }
            styler.mode = newValue
            restyle()
        }
    }

    var theme: Theme {
        get { styler.theme }
        set {
            guard newValue != styler.theme else { return }
            styler.theme = newValue
            applyThemeChrome()
            restyle()
        }
    }

    static func makeInScrollView() -> (NSScrollView, EditorTextView) {
        let storage = NSTextStorage()
        let layout = HidingLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)

        let editor = EditorTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), textContainer: container)
        storage.delegate = editor
        editor.configure()

        let scroll = NSScrollView()
        scroll.documentView = editor
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        return (scroll, editor)
    }

    private func configure() {
        isRichText = false
        importsGraphics = false
        usesFontPanel = false
        allowsUndo = true
        isEditable = true
        isSelectable = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = true
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        minSize = NSSize(width: 0, height: 0)
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        applyThemeChrome()
        restyle()
    }

    private func applyThemeChrome() {
        let theme = styler.theme
        backgroundColor = theme.background
        drawsBackground = true
        insertionPointColor = theme.accent
        selectedTextAttributes = [.backgroundColor: theme.line]
        hidingLayoutManager.codeBackground = theme.panel
        hidingLayoutManager.ruleColor = theme.line
        hidingLayoutManager.quoteBarColor = theme.line
    }

    override var undoManager: UndoManager? { documentUndo }

    /// Replaces the document. Not an edit: undo history is cleared.
    func load(text: String) {
        guard let storage = textStorage else { return }
        documentUndo.disableUndoRegistration()
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
        documentUndo.enableUndoRegistration()
        documentUndo.removeAllActions()
        setSelectedRange(NSRange(location: 0, length: 0))
        refreshDisplay()
        positionTableOverlays()
    }

    func restyle() {
        guard let storage = textStorage else { return }
        styler.rescan(storage.string)
        storage.beginEditing()
        styler.apply(to: storage)
        storage.endEditing()
        typingAttributes = styler.typingAttributes
        syncTables(invalidate: true)
        refreshDisplay()
        positionTableOverlays()
        needsDisplay = true
    }

    private func refreshDisplay(invalidate: Bool = true) {
        let display = styler.display(selection: selectedRange())
        hidingLayoutManager.decorations = styler.decorations
        hidingLayoutManager.setDisplay(hidden: display.hidden, substitutions: display.substitutions, invalidate: invalidate)
    }

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        styler.rescan(textStorage.string)
        styler.apply(to: textStorage)
        syncTables(invalidate: false)
        refreshDisplay(invalidate: false)
    }

    // MARK: Tables

    private var tableWidth: CGFloat {
        max(120, bounds.width - textContainerInset.width * 2 - (textContainer?.lineFragmentPadding ?? 0) * 2)
    }

    /// Matches overlays to the tables in the text, reusing views so cell editing carries on.
    private func syncTables(invalidate: Bool) {
        let tables = viewMode == .formatted ? styler.map.tables : []
        while tableOverlays.count > tables.count {
            tableOverlays.removeLast().removeFromSuperview()
        }
        for (index, table) in tables.enumerated() {
            if index < tableOverlays.count {
                tableOverlays[index].update(table: table, theme: theme, width: tableWidth)
            } else {
                let overlay = TableOverlayView(table: table, theme: theme, width: tableWidth)
                overlay.onEdits = { [weak self] edits in self?.applyEdits(edits) }
                overlay.onFinishEditing = { [weak self] in
                    guard let self else { return }
                    self.window?.makeFirstResponder(self)
                }
                addSubview(overlay)
                tableOverlays.append(overlay)
            }
        }
        let reserved = zip(tables, tableOverlays).map { (range: $0.range, height: $1.gridSize.height) }
        hidingLayoutManager.setReservedTables(reserved, invalidate: invalidate)
    }

    func positionTableOverlays() {
        guard let layout = layoutManager, let storage = textStorage else { return }
        for overlay in tableOverlays where NSMaxRange(overlay.table.range) <= storage.length {
            let glyph = layout.glyphIndexForCharacter(at: overlay.table.range.location)
            let rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let padding = textContainer?.lineFragmentPadding ?? 0
            let frame = NSRect(x: rect.minX + textContainerOrigin.x + padding, y: rect.minY + textContainerOrigin.y,
                               width: overlay.gridSize.width, height: overlay.gridSize.height)
            if overlay.frame != frame { overlay.frame = frame }
        }
    }

    override func viewWillDraw() {
        positionTableOverlays()
        super.viewWillDraw()
    }

    /// Where the caret goes instead of landing inside a table's hidden source.
    private func caretOutsideTables(_ location: Int) -> Int {
        guard viewMode == .formatted,
              let table = styler.map.tables.first(where: { location >= $0.range.location && location <= NSMaxRange($0.range) })
        else { return location }
        let ns = string as NSString
        let forward = location >= selectedRange().location || table.range.location == 0
        if forward {
            let line = ns.lineRange(for: NSRange(location: NSMaxRange(table.range), length: 0))
            return min(NSMaxRange(line), ns.length)
        }
        var before = table.range.location - 1
        if before > 0, ns.character(at: before) == 0x0A, ns.character(at: before - 1) == 0x0D { before -= 1 }
        return before
    }

    override func didChangeText() {
        super.didChangeText()
        typingAttributes = styler.typingAttributes
        onTextChange?(string)
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        var ranges = ranges
        if ranges.count == 1, ranges[0].rangeValue.length == 0, textStorage != nil {
            ranges = [NSValue(range: NSRange(location: caretOutsideTables(ranges[0].rangeValue.location), length: 0))]
        }
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if textStorage != nil, layoutManager != nil { refreshDisplay() }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let side = max(28, (newSize.width - Self.columnWidth) / 2)
        if textContainerInset.width != side {
            textContainerInset = NSSize(width: side, height: 14)
        }
        if textStorage != nil, layoutManager != nil { syncTables(invalidate: true) }
    }

    // MARK: Editing commands

    @discardableResult
    func applyEdit(_ range: NSRange, _ replacement: String) -> Bool {
        guard shouldChangeText(in: range, replacementString: replacement), let storage = textStorage else { return false }
        storage.replaceCharacters(in: range, with: replacement)
        didChangeText()
        return true
    }

    /// Applies several edits as one undo step.
    func applyEdits(_ edits: [TextEdit]) {
        var selection = selectedRange()
        documentUndo.beginUndoGrouping()
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
            guard applyEdit(edit.range, edit.replacement) else { continue }
            if edit.range.location < selection.location {
                selection.location += (edit.replacement as NSString).length - edit.range.length
            }
        }
        documentUndo.endUndoGrouping()
        setSelectedRange(selection)
    }

    func toggleWrap(marker: String) {
        let ns = string as NSString
        let selection = selectedRange()
        let length = (marker as NSString).length
        let before = selection.location - length
        let after = NSMaxRange(selection)
        if before >= 0, after + length <= ns.length,
           ns.substring(with: NSRange(location: before, length: length)) == marker,
           ns.substring(with: NSRange(location: after, length: length)) == marker {
            let whole = NSRange(location: before, length: selection.length + length * 2)
            applyEdit(whole, ns.substring(with: selection))
            setSelectedRange(NSRange(location: before, length: selection.length))
        } else {
            applyEdit(selection, marker + ns.substring(with: selection) + marker)
            setSelectedRange(NSRange(location: selection.location + length, length: selection.length))
        }
    }

    func insertLink() {
        let selection = selectedRange()
        let label = (string as NSString).substring(with: selection)
        applyEdit(selection, "[\(label)](url)")
        let labelLength = (label as NSString).length
        setSelectedRange(NSRange(location: selection.location + labelLength + 3, length: 3))
    }

    func toggleTaskBox(at location: Int) {
        guard let box = styler.map.taskBoxes.first(where: { NSLocationInRange(location, $0.owner) }) else { return }
        applyEdit(NSRange(location: box.range.location + 1, length: 1), box.isChecked ? " " : "x")
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers {
        case "b": toggleWrap(marker: "**"); return true
        case "i": toggleWrap(marker: "*"); return true
        case "k": insertLink(); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    // MARK: Clicks

    private func characterIndex(at point: NSPoint) -> Int? {
        guard let container = textContainer, let layout = layoutManager else { return nil }
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let glyph = layout.glyphIndex(for: local, in: container, fractionOfDistanceThroughGlyph: &fraction)
        guard layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).contains(local) else { return nil }
        return layout.characterIndexForGlyph(at: glyph)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = characterIndex(at: point), let storage = textStorage, index < storage.length {
            if event.modifierFlags.contains(.command),
               let value = storage.attribute(.claudetteURL, at: index, effectiveRange: nil) as? String,
               let url = URL(string: value) {
                NSWorkspace.shared.open(url)
                return
            }
            if viewMode == .formatted, hidingLayoutManager.substitutions[index] != nil,
               styler.map.taskBoxes.contains(where: { NSLocationInRange(index, $0.owner) }) {
                toggleTaskBox(at: index)
                return
            }
        }
        super.mouseDown(with: event)
    }
}
