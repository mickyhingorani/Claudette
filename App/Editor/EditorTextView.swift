import AppKit
import ClaudetteCore

final class EditorTextView: NSTextView, NSTextStorageDelegate {
    private static let columnWidth: CGFloat = 680

    let styler = EditorStyler()
    private let documentUndo = UndoManager()
    /// True until the cursor first moves, so a file opens with all its syntax hidden.
    private var isFreshlyLoaded = false
    var onTextChange: ((String) -> Void)?
    var onDropURLs: (([URL]) -> Void)?
    private(set) var tableOverlays: [TableOverlayView] = []

    override var isEditable: Bool {
        didSet {
            tableOverlays.forEach { $0.isEditable = isEditable }
            if !isEditable { tableOverlays.forEach { $0.discardEditing() } }
        }
    }
    private(set) var imageOverlays: [ImageOverlayView] = []
    /// The folder of the open file, for image paths written relative to it.
    var documentFolder: URL?

    /// Opens Markdown files linked from the document.
    var onOpenDocument: ((URL) -> Void)?
    /// Told about a link Claudette won't open, such as a script or another app.
    var onRefusedLink: ((String) -> Void)?
    var openExternally: (URL) -> Void = { NSWorkspace.shared.open($0) }

    /// ⌘-click on a link: web and email links open outside, Markdown files open here,
    /// and anything else, like an app or a script, is refused.
    func followLink(_ link: String) {
        switch LinkTarget.resolve(link, relativeTo: documentFolder) {
        case .external(let url): openExternally(url)
        case .document(let url): onOpenDocument?(url)
        case .none: break
        case .refused: onRefusedLink?(link)
        }
    }
    var imageLoader = ImageLoader.shared {
        didSet { observeImageLoader() }
    }
    private var imageObserver: NSObjectProtocol?

    var hidingLayoutManager: HidingLayoutManager { layoutManager as! HidingLayoutManager }

    var viewMode: ViewMode {
        get { styler.mode }
        set {
            guard newValue != styler.mode else { return }
            commitCellEdits()
            styler.mode = newValue
            restyle()
            let selection = selectedRange()
            if newValue == .formatted, selection.length == 0 { setSelectedRange(selection) }
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
        registerForDraggedTypes([.fileURL, .string])
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
        hidingLayoutManager.chipBackground = theme.chip
        hidingLayoutManager.ruleColor = theme.line
        hidingLayoutManager.quoteBarColor = theme.palette.quoteBar
        hidingLayoutManager.palette = theme.palette
        hidingLayoutManager.pageBackground = theme.background
        hidingLayoutManager.underlineColor = theme.palette.link
        hidingLayoutManager.strikeColor = theme.soft
    }

    override var undoManager: UndoManager? { documentUndo }

    // The window answers undo: with its own manager unless the text view does first.

    private var openCell: TableOverlayView? { tableOverlays.first { $0.editingCell != nil } }

    /// An open cell has its own field, with the window's undo history.
    private var activeUndo: UndoManager? { openCell != nil ? window?.undoManager : documentUndo }

    @objc func undo(_ sender: Any?) {
        activeUndo?.undo()
        if openCell == nil { onTextChange?(string) }
    }

    @objc func redo(_ sender: Any?) {
        activeUndo?.redo()
        if openCell == nil { onTextChange?(string) }
    }

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)):
            item.title = activeUndo?.undoMenuItemTitle ?? "Undo"
            return activeUndo?.canUndo ?? false
        case #selector(redo(_:)):
            item.title = activeUndo?.redoMenuItemTitle ?? "Redo"
            return activeUndo?.canRedo ?? false
        default:
            return super.validateMenuItem(item)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        // After the current update, so this holds once the window has finished setting up.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, window.firstResponder === window else { return }
            window.makeFirstResponder(self)
        }
    }

    /// Replaces the document. Not an edit: undo history is cleared.
    func load(text: String) {
        guard let storage = textStorage else { return }
        tableOverlays.forEach { $0.discardEditing() }
        styler.forgetGuessedLanguages()
        documentUndo.disableUndoRegistration()
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
        documentUndo.enableUndoRegistration()
        documentUndo.removeAllActions()
        setSelectedRange(NSRange(location: 0, length: 0))
        isFreshlyLoaded = true
        syncImages(invalidate: true)
        refreshDisplay()
        positionOverlays()
    }

    func restyle() {
        guard let storage = textStorage else { return }
        styler.rescan(storage.string)
        storage.beginEditing()
        styler.apply(to: storage)
        storage.endEditing()
        typingAttributes = styler.typingAttributes
        syncTables(invalidate: true)
        syncImages(invalidate: true)
        refreshDisplay()
        positionOverlays()
        needsDisplay = true
    }

    private func refreshDisplay(invalidate: Bool = true) {
        let selection = isFreshlyLoaded ? NSRange(location: NSNotFound, length: 0) : selectedRange()
        let display = styler.display(selection: selection)
        hidingLayoutManager.decorations = styler.decorations(selection: selection)
        hidingLayoutManager.emptyLineFont = styler.emptyLineFont
        hidingLayoutManager.paragraphGap = styler.paragraphGap
        hidingLayoutManager.setDisplay(hidden: display.hidden, substitutions: display.substitutions, invalidate: invalidate)
    }

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        let region = styler.rescan(textStorage.string, edited: editedRange, delta: delta)
        styler.apply(to: textStorage, in: region)
        syncTables(invalidate: false)
        syncImages(invalidate: false)
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
            let overlay = tableOverlays.removeLast()
            overlay.discardEditing()
            overlay.removeFromSuperview()
        }
        for (index, table) in tables.enumerated() {
            if index < tableOverlays.count {
                tableOverlays[index].update(table: table, theme: theme, width: tableWidth)
            } else {
                let overlay = TableOverlayView(table: table, theme: theme, width: tableWidth)
                overlay.isEditable = isEditable
                overlay.onEdits = { [weak self] edits in self?.applyEdits(edits) }
                overlay.onDraftChange = { [weak self] in
                    guard let self else { return }
                    self.onTextChange?(self.string)
                }
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

    // MARK: Images

    private func observeImageLoader() {
        if let imageObserver { NotificationCenter.default.removeObserver(imageObserver) }
        imageObserver = NotificationCenter.default.addObserver(forName: ImageLoader.didLoad, object: imageLoader, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.textStorage != nil else { return }
                self.syncImages(invalidate: true)
                self.positionOverlays()
            }
        }
    }

    /// Matches picture views to the block images in the text.
    private func syncImages(invalidate: Bool) {
        if imageObserver == nil { observeImageLoader() }
        let images = viewMode == .formatted ? styler.map.images.filter(\.isBlock) : []
        while imageOverlays.count > images.count {
            imageOverlays.removeLast().removeFromSuperview()
        }
        for (index, info) in images.enumerated() {
            var picture: NSImage?
            if let url = ImageLoader.url(for: info.source, relativeTo: documentFolder),
               case .loaded(let image) = imageLoader.state(for: url, startLoading: invalidate) {
                picture = image
            }
            if index < imageOverlays.count {
                imageOverlays[index].update(info: info, image: picture, theme: theme)
            } else {
                let overlay = ImageOverlayView(info: info, image: picture, theme: theme)
                addSubview(overlay)
                imageOverlays.append(overlay)
            }
            let overlay = imageOverlays[index]
            overlay.onClick = { [weak self, weak overlay] in
                guard let self, let overlay else { return }
                self.window?.makeFirstResponder(self)
                self.setSelectedRange(NSRange(location: NSMaxRange(overlay.info.range), length: 0))
            }
        }
        let reserved = imageOverlays.map { (range: $0.info.range, height: $0.displaySize(maxWidth: tableWidth).height) }
        hidingLayoutManager.setReservedImages(reserved, invalidate: invalidate)
        // While typing, web pictures wait until the address stops changing.
        if !invalidate, !images.isEmpty { scheduleImageLoading() }
    }

    private var imageLoadTimer: Timer?

    private func scheduleImageLoading() {
        imageLoadTimer?.invalidate()
        imageLoadTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.textStorage != nil else { return }
                self.syncImages(invalidate: true)
                self.positionOverlays()
            }
        }
    }

    func commitCellEdits() {
        tableOverlays.forEach { $0.commitCurrentEdit() }
    }

    /// The document as it will be once any open cell is committed, for saving while it's open.
    var textWithCellDrafts: String {
        let edits = tableOverlays.flatMap(\.draftEdits)
        guard !edits.isEmpty else { return string }
        let text = NSMutableString(string: string)
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
            text.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        return text as String
    }

    func positionOverlays() {
        guard let layout = layoutManager, let storage = textStorage else { return }
        for overlay in tableOverlays where NSMaxRange(overlay.table.range) <= storage.length {
            let glyph = layout.glyphIndexForCharacter(at: overlay.table.range.location)
            let rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let padding = textContainer?.lineFragmentPadding ?? 0
            let frame = NSRect(x: rect.minX + textContainerOrigin.x + padding, y: rect.minY + textContainerOrigin.y + hidingLayoutManager.tableOffset(at: overlay.table.range.location),
                               width: overlay.gridSize.width, height: overlay.gridSize.height)
            if overlay.frame != frame { overlay.frame = frame }
        }
        for overlay in imageOverlays where NSMaxRange(overlay.info.range) <= storage.length && overlay.info.range.length > 0 {
            let glyph = layout.glyphIndexForCharacter(at: NSMaxRange(overlay.info.range) - 1)
            let rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let padding = textContainer?.lineFragmentPadding ?? 0
            let size = overlay.displaySize(maxWidth: tableWidth)
            let frame = NSRect(x: rect.minX + textContainerOrigin.x + padding,
                               y: rect.minY + textContainerOrigin.y + hidingLayoutManager.imageOffset(at: overlay.info.range.location),
                               width: size.width, height: size.height)
            if overlay.frame != frame { overlay.frame = frame }
        }
    }

    override func viewWillDraw() {
        positionOverlays()
        super.viewWillDraw()
    }

    /// Heading marks that stay hidden in this view. The caret never goes inside one.
    private var hiddenHeadingMarks: [NSRange] {
        guard viewMode == .formatted else { return [] }
        return styler.map.hidden.filter { $0.kind == .headingMark }.map(\.range)
    }

    /// Where the caret goes instead of landing inside a heading's hidden mark.
    private func caretOutsideHeadingMarks(_ location: Int) -> Int {
        guard let mark = hiddenHeadingMarks.first(where: { NSLocationInRange(location, $0) }) else { return location }
        let isSteppingLeft = selectedRange().location == NSMaxRange(mark) && location == NSMaxRange(mark) - 1
        guard isSteppingLeft, mark.location > 0 else { return NSMaxRange(mark) }
        let ns = string as NSString
        var before = mark.location - 1
        if before > 0, ns.character(at: before) == 0x0A, ns.character(at: before - 1) == 0x0D { before -= 1 }
        return before
    }

    // MARK: Paragraphs

    /// A hidden paragraph break, and where the paragraph after it starts.
    private struct ParagraphBreak {
        let range: NSRange
        let nextParagraph: Int
    }

    private var paragraphBreaks: [ParagraphBreak] {
        guard viewMode == .formatted else { return [] }
        let ns = string as NSString
        return styler.map.paragraphBreaks.compactMap { range in
            guard NSMaxRange(range) <= ns.length else { return nil }
            let blank = ns.lineRange(for: NSRange(location: NSMaxRange(range), length: 0))
            return ParagraphBreak(range: range, nextParagraph: NSMaxRange(blank))
        }
    }

    /// The caret never rests on a hidden break or the blank line after it: both are drawn at the
    /// end of the paragraph. A step right from that end goes to the next paragraph.
    private func caretOutsideParagraphBreaks(_ location: Int) -> Int {
        guard let item = paragraphBreaks.first(where: { location > $0.range.location && location < $0.nextParagraph }) else { return location }
        let isSteppingRight = selectedRange().location == item.range.location
        // Ending a paragraph inside a table's hidden source would hide the caret.
        let endIsInTable = styler.map.tables.contains { item.range.location >= $0.range.location && item.range.location <= NSMaxRange($0.range) }
        return isSteppingRight || endIsInTable ? item.nextParagraph : item.range.location
    }

    /// Return starts a new paragraph in the formatted view, except where lines matter on their own.
    private var startsParagraphOnReturn: Bool {
        guard viewMode == .formatted else { return false }
        let ns = string as NSString
        let location = selectedRange().location
        let line = ns.lineRange(for: NSRange(location: location, length: 0))
        let isBlank = ns.substring(with: line).allSatisfy(\.isNewline)
        let inCode = styler.map.codeBlocks.contains { NSLocationInRange(location, $0.range) || location == NSMaxRange($0.range) }
        let inList = styler.map.spans.contains { $0.kind == .listItem && NSLocationInRange($0.range.location, line) }
        return !isBlank && !inCode && !inList
    }

    /// Shift-Return: a line break inside the paragraph.
    override func insertLineBreak(_ sender: Any?) {
        insertText(lineEnding, replacementRange: selectedRange())
    }

    /// Whether the line at `location` starts with Markdown that only works at a line's start.
    private func startsBlock(at location: Int) -> Bool {
        let ns = string as NSString
        guard location < ns.length else { return false }
        let line = ns.substring(with: ns.lineRange(for: NSRange(location: location, length: 0)))
        let text = line.drop { $0 == " " }
        if let first = text.first, "-*+".contains(first), text.dropFirst().first == " " { return true }
        if [">", "#", "|"].contains(where: { text.hasPrefix($0) }) || text.hasPrefix("```") || text.hasPrefix("~~~") { return true }
        let digits = text.prefix { $0.isNumber }
        if !digits.isEmpty, let mark = text.dropFirst(digits.count).first, ".)".contains(mark) { return true }
        return false
    }

    override func deleteForward(_ sender: Any?) {
        let selection = selectedRange()
        if selection.length == 0, let item = paragraphBreaks.first(where: { $0.range.location == selection.location }) {
            let keepsMarker = startsBlock(at: item.nextParagraph)
            let start = keepsMarker ? NSMaxRange(item.range) : item.range.location
            applyEdit(NSRange(location: start, length: item.nextParagraph - start), "")
            setSelectedRange(NSRange(location: item.range.location, length: 0))
            return
        }
        super.deleteForward(sender)
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
        refreshDisplay()
        onTextChange?(string)
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        var ranges = ranges
        if ranges.count == 1, ranges[0].rangeValue.length == 0, textStorage != nil {
            let location = caretOutsideHeadingMarks(caretOutsideParagraphBreaks(caretOutsideTables(ranges[0].rangeValue.location)))
            ranges = [NSValue(range: NSRange(location: location, length: 0))]
        }
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        isFreshlyLoaded = false
        if textStorage != nil, layoutManager != nil {
            refreshDisplay()
            // Revealing syntax can move the text after the caret was placed.
            if window != nil, !stillSelecting, selectedRange().length == 0 { updateInsertionPointStateAndRestartTimer(true) }
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        // The view also grows taller as text is typed; only a new width changes what fits.
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        let side = max(28, (newSize.width - Self.columnWidth) / 2)
        if textContainerInset.width != side {
            textContainerInset = NSSize(width: side, height: 14)
        }
        if widthChanged, textStorage != nil, layoutManager != nil {
            syncTables(invalidate: true)
            syncImages(invalidate: true)
        }
    }

    // MARK: Editing commands

    /// A line typed right under a table would join it as a row, so it needs a blank line first.
    private func paragraphBreak(beforeTypingAt location: Int) -> String? {
        guard viewMode == .formatted else { return nil }
        let ns = string as NSString
        for table in styler.map.tables {
            let end = NSMaxRange(table.range)
            if location == end, end == ns.length { return table.lineEnding + table.lineEnding }
            if end < ns.length, location == NSMaxRange(ns.lineRange(for: NSRange(location: end, length: 0))) {
                return table.lineEnding
            }
        }
        return nil
    }

    /// Backspace at the start of a heading removes its hidden mark, making it plain text.
    override func deleteBackward(_ sender: Any?) {
        let selection = selectedRange()
        // At the start of a paragraph, joins it to the one before. A list item, quote or other
        // block would lose its marker that way, so for those only the blank line goes.
        if selection.length == 0, let item = paragraphBreaks.first(where: { $0.nextParagraph == selection.location }) {
            if startsBlock(at: item.nextParagraph) {
                let blank = NSRange(location: NSMaxRange(item.range), length: item.nextParagraph - NSMaxRange(item.range))
                applyEdit(blank, "")
                setSelectedRange(NSRange(location: blank.location, length: 0))
            } else {
                applyEdit(NSRange(location: item.range.location, length: item.nextParagraph - item.range.location), "")
                setSelectedRange(NSRange(location: item.range.location, length: 0))
            }
            return
        }
        guard selection.length == 0, let mark = hiddenHeadingMarks.first(where: { NSMaxRange($0) == selection.location }) else {
            super.deleteBackward(sender)
            return
        }
        applyEdit(mark, "")
        setSelectedRange(NSRange(location: mark.location, length: 0))
    }

    /// Return at the end of an opening fence with no closing one adds the closing fence below.
    override func insertNewline(_ sender: Any?) {
        guard let fence = fenceToClose() else {
            if startsParagraphOnReturn {
                insertText(lineEnding + lineEnding, replacementRange: selectedRange())
            } else {
                super.insertNewline(sender)
            }
            return
        }
        let selection = selectedRange()
        let newline = lineEnding
        insertText(newline + newline + fence, replacementRange: selection)
        setSelectedRange(NSRange(location: selection.location + (newline as NSString).length, length: 0))
    }

    /// The fence to add when the caret ends an opening fence line of a block left open.
    private func fenceToClose() -> String? {
        let selection = selectedRange()
        guard selection.length == 0 else { return nil }
        let ns = string as NSString
        let line = ns.lineRange(for: selection)
        var contentEnd = NSMaxRange(line)
        while contentEnd > line.location, [0x0A, 0x0D].contains(ns.character(at: contentEnd - 1)) { contentEnd -= 1 }
        guard selection.location == contentEnd,
              let block = styler.map.codeBlocks.first(where: { $0.range.location >= line.location && $0.range.location < contentEnd }),
              !block.isClosed
        else { return nil }
        let text = ns.substring(with: NSRange(location: line.location, length: contentEnd - line.location))
        let indent = text.prefix { $0 == " " }
        let rest = text.dropFirst(indent.count)
        guard let mark = rest.first, mark == "`" || mark == "~" else { return nil }
        return String(indent) + String(rest.prefix { $0 == mark })
    }

    /// The line ending the document already uses.
    private var lineEnding: String { string.contains("\r\n") ? "\r\n" : "\n" }

    override func insertText(_ text: Any, replacementRange: NSRange) {
        let target = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
        let typed = (text as? String) ?? (text as? NSAttributedString)?.string ?? ""
        if target.length == 0, !typed.isEmpty, !typed.allSatisfy(\.isNewline), let lead = paragraphBreak(beforeTypingAt: target.location) {
            super.insertText(lead + typed, replacementRange: target)
        } else {
            super.insertText(text, replacementRange: replacementRange)
        }
    }

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
               let value = storage.attribute(.claudetteURL, at: index, effectiveRange: nil) as? String {
                followLink(value)
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

    // MARK: Dropped files

    private func droppedURLs(_ sender: NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedURLs(sender).isEmpty ? super.draggingEntered(sender) : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedURLs(sender).isEmpty ? super.draggingUpdated(sender) : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = droppedURLs(sender)
        guard !urls.isEmpty else { return super.performDragOperation(sender) }
        onDropURLs?(urls)
        return true
    }
}
