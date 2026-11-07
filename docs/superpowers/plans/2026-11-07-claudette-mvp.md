# Claudette MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native, dark, minimal Mac app for reading and editing Markdown files in place, in folders Micky connects, with editing in both a formatted and a Markdown view, and real drawn tables.

**Architecture:** One text buffer is the only source of truth. A pure Swift package (`ClaudetteCore`) turns text into a `StyleMap` of styled ranges, hidden syntax, and tables, and owns all file logic. The AppKit editor (TextKit 1 `NSTextView`) applies the map: a layout manager delegate hides syntax glyphs, and a table overlay view stands in for a table's hidden source lines. A thin SwiftUI shell holds the window, top bar, file list, and menus.

**Tech Stack:** Swift, SwiftUI, AppKit, TextKit 1, `swift-markdown`, XcodeGen, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-07-claudette-mvp-design.md`

## Global Constraints

- Opening, viewing, or switching views must not change a file's bytes. Only a real edit writes.
- All `NSRange` values are UTF-16 offsets into the document string.
- Formatted view hides syntax; a span's syntax reappears while the cursor is in that span.
- Themes: Ink `#121212` / `#F7F4EC` / accent `#FFFFFF`, serif. Terminal `#050805` / `#4DFF88` / accent `#D6FFE4`, Menlo, heading `#` marks stay visible.
- Shortcuts: `⌘E` switch view, `⌘\` file list, `⌘N` new, `⌘B` bold, `⌘I` italic, `⌘K` link.
- Autosave about 1 second after typing stops, and on file switch, app deactivate, and quit.
- Starter folder `~/Claudette`. App Sandbox off. Signed with the Apple Development certificate.
- Minimum macOS 26. App target in Swift 5 language mode; `ClaudetteCore` in Swift 6.

## Review Focus

- A non-UTF-8 file: opens read-only with a short notice, and is never written.
- A file with CRLF line endings or a BOM: survives open, view switches, and an edit elsewhere without those bytes changing.
- Emoji and other multi-unit characters before a span or in a table cell: ranges stay exact.
- A `|` typed into a table cell, or a pipe inside inline code: the table keeps its shape.
- A file deleted or renamed outside the app while open: no crash, and unsaved text isn't lost.

---

## File Map

```
project.yml                     XcodeGen definition
Core/Package.swift              ClaudetteCore package
Core/Sources/ClaudetteCore/
  LineIndex.swift               line/column to UTF-16 offsets
  StyleMap.swift                StyleMap, StyledSpan, HiddenRange, Substitution types
  MarkdownScanner.swift         text -> StyleMap
  TableBlock.swift              table model and parser
  TableEditor.swift             table edits as TextEdit lists
  TextEdit.swift                TextEdit
  FileNaming.swift              names from first line, unique names
  FolderScanner.swift           list .md files
  DocumentFile.swift            load, save, conflict logic
Core/Tests/ClaudetteCoreTests/  one test file per source file
App/ClaudetteApp.swift          app entry, commands
App/AppModel.swift              folders, current file, view mode, theme, persistence
App/Theme.swift                 Theme values
App/RootView.swift              top bar, slide-in list, editor, drop handling
App/FileListView.swift          sections, rows, context menus
App/FolderWatcher.swift         FSEvents wrapper
App/Editor/EditorView.swift     NSViewRepresentable
App/Editor/EditorTextView.swift NSTextView subclass, shortcuts, checkbox clicks
App/Editor/EditorStyler.swift   StyleMap -> attributes, reveal logic
App/Editor/HidingLayoutManager.swift glyph hiding, code block and rule drawing
App/Editor/TableOverlayView.swift drawn table and cell editing
App/Snapshot.swift              launch-argument PNG rendering for review
```

---

### Task 1: Project skeleton

**Files:** Create `project.yml`, `Core/Package.swift`, `App/ClaudetteApp.swift`, `Core/Sources/ClaudetteCore/TextEdit.swift`, `Core/Sources/ClaudetteCore/LineIndex.swift`, `Core/Tests/ClaudetteCoreTests/LineIndexTests.swift`

**Interfaces:**
- Produces: `struct TextEdit { var range: NSRange; var replacement: String }`; `struct LineIndex { init(_ text: String); func offset(line: Int, utf8Column: Int) -> Int }` with 1-based line and column, returning a UTF-16 offset.

- [ ] **Step 1:** `brew install xcodegen`. Write `project.yml` with the app target, the local `Core` package, `ENABLE_APP_SANDBOX: NO`, and Automatic signing.
- [ ] **Step 2:** Write failing tests `offsetHandlesEmojiBeforeColumn`, `offsetHandlesCRLF`, `offsetAtEndOfFile`. Run `swift test --package-path Core`. Expected: FAIL.
- [ ] **Step 3:** Implement `LineIndex`. Run the tests. Expected: PASS.
- [ ] **Step 4:** `xcodegen generate && xcodebuild -scheme Claudette build`. Expected: `BUILD SUCCEEDED`.
- [ ] **Step 5:** Commit.

### Task 2: Markdown scanner

**Files:** Create `StyleMap.swift`, `MarkdownScanner.swift`, `Core/Tests/ClaudetteCoreTests/MarkdownScannerTests.swift`

**Interfaces:**
- Produces:
  - `enum SpanKind { heading(level: Int), strong, emphasis, strikethrough, inlineCode, codeBlock, link(url: String), blockquote, listItem, thematicBreak, frontmatter, syntax, image }`
  - `struct StyledSpan { range: NSRange; kind: SpanKind }`
  - `struct HiddenRange { range: NSRange; owner: NSRange; kind: HiddenKind }` where `owner` is the span whose cursor presence reveals it and `HiddenKind` is `.inline`, `.headingMark`, or `.fenceLine`
  - `struct Substitution { range: NSRange; glyph: String; owner: NSRange }` for bullets and checkboxes
  - `struct TaskBox { range: NSRange; isChecked: Bool }`
  - `struct StyleMap { spans; hidden; substitutions; taskBoxes; tables: [TableBlock] }`
  - `enum MarkdownScanner { static func scan(_ text: String) -> StyleMap }`

- [ ] **Step 1:** Write failing tests with exact ranges: `strongHidesFourMarkers`, `headingHidesHashAndSpace`, `linkHidesBracketsAndURL`, `inlineCodeHidesBackticks`, `fenceLinesHidden`, `bulletSubstituted`, `taskBoxChecked`, `frontmatterDimmedNotParsed`, `rangesExactAfterEmoji`, `rangesExactWithCRLF`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement with a `MarkupWalker` over `Document(parsing:)`. Blank frontmatter lines before parsing so positions hold. Compute marker lengths from the source text at each node's bounds.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Commit.

### Task 3: Risk proof A, hidden syntax in the editor

**Files:** Create `App/Theme.swift`, `App/Editor/*` except the table overlay, `App/Snapshot.swift`

**Interfaces:**
- Consumes: `MarkdownScanner.scan`.
- Produces:
  - `enum ViewMode { formatted, markdown }`
  - `struct Theme { static let ink, terminal; background, text, soft, accent: NSColor; bodyFont, monoFont: NSFont; keepsHeadingMarks: Bool }`
  - `final class EditorTextView: NSTextView` with `var viewMode`, `var theme`, `func restyle()`
  - Launch arguments `-snapshotFile <md> -snapshotOut <png> -snapshotTheme ink|terminal -snapshotMode formatted|markdown -snapshotCursor <offset>` rendering the window to a PNG, then quitting.

- [ ] **Step 1:** Implement `HidingLayoutManager` using `shouldGenerateGlyphs` with `.null` for hidden characters, `shouldUse:forControlCharacterAt:` returning `.zeroAdvancement` for hidden newlines, and glyph substitution for bullets. Draw code block backgrounds and rules in `drawBackground`.
- [ ] **Step 2:** Implement `EditorStyler`: full attribute pass on text change, hidden-set update on selection change. Attribute changes go straight to text storage so they stay out of undo.
- [ ] **Step 3:** Implement `EditorTextView` with `⌘B`, `⌘I`, `⌘K` wrapping through `insertText` so undo works, `⌘`-click links, and checkbox click toggling.
- [ ] **Step 4:** Render snapshots of a sample file, cursor away and cursor inside bold, in both themes. Expected: markers hidden, then revealed only in the cursor's span.
- [ ] **Step 5:** Add an app-hosted test `cursorMovesThroughHiddenSpanWithoutSticking` and `selectionSurvivesViewSwitch`. Expected: PASS.
- [ ] **Step 6:** Commit.

**Stop point:** if the cursor can't behave well here, stop and report before going on.

### Task 4: Table model and edits

**Files:** Create `TableBlock.swift`, `TableEditor.swift`, tests.

**Interfaces:**
- Produces:
  - `struct TableCell { textRange: NSRange; text: String }`
  - `enum TableAlignment { left, center, right }`
  - `struct TableBlock { range: NSRange; header: [TableCell]; rows: [[TableCell]]; alignments: [TableAlignment] }`
  - `enum TableEditor` with `setCell(_:row:column:text:) -> [TextEdit]`, `addRow(_:after:)`, `deleteRow(_:row:)`, `addColumn(_:after:)`, `deleteColumn(_:column:)`, all taking `TableBlock` and returning `[TextEdit]`. Row `0` is the header.

- [ ] **Step 1:** Write failing tests: `parsesAlignments`, `pipeInCodeSpanStaysInCell`, `escapedPipeStaysInCell`, `shortRowPaddedWithEmptyCells`, `setCellChangesOnlyThatCell` (asserts all other bytes equal), `setCellEscapesPipe`, `setCellFlattensNewlines`, `setEmptyCell`, `addRowMatchesColumnCount`, `deleteLastBodyRow`, `cellRangesExactAfterEmoji`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement, and have `MarkdownScanner` fill `StyleMap.tables` from `Table` nodes.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Commit.

### Task 5: Risk proof B, drawn editable tables

**Files:** Create `App/Editor/TableOverlayView.swift`; modify `HidingLayoutManager`, `EditorStyler`, `EditorTextView`.

**Interfaces:**
- Consumes: `TableBlock`, `TableEditor`.
- Produces: `final class TableOverlayView: NSView` with `init(table:theme:)`, `func height(forWidth:) -> CGFloat`, and `var onEdits: ([TextEdit]) -> Void`.

- [ ] **Step 1:** In the formatted view, hide a table's whole range on one line fragment and set that fragment's height to the overlay's height with `shouldSetLineFragmentRect`.
- [ ] **Step 2:** Implement drawing: header row, cell lines, alignment, wrapping, and inline styling from `MarkdownScanner` on each cell's text with hidden ranges removed.
- [ ] **Step 3:** Implement cell editing: click shows an inline field holding the cell's source, commit on blur or Return, `Tab` to the next cell, `Tab` in the last cell adds a row, right-click for add or delete row and column. Apply `TextEdit`s through `shouldChangeText` so undo works.
- [ ] **Step 4:** Keep the cursor out of a table's hidden range: it skips across in the direction of travel.
- [ ] **Step 5:** Render snapshots of a table in both themes, with long wrapped cells and an emoji. Expected: a real grid, nothing overlapping the text below.
- [ ] **Step 6:** Add an app-hosted test `cellEditThenUndoRestoresBytes`. Expected: PASS.
- [ ] **Step 7:** Commit.

**Stop point:** if tables can't work this way, stop and report before going on.

### Task 6: Files and folders logic

**Files:** Create `FileNaming.swift`, `FolderScanner.swift`, `DocumentFile.swift`, tests.

**Interfaces:**
- Produces:
  - `enum FileNaming { static func name(fromFirstLineOf text: String) -> String; static func uniqueURL(for name: String, in folder: URL) -> URL; static func conflictURL(for url: URL) -> URL }`
  - `struct ListedFile { url: URL; displayName: String; modified: Date }`
  - `enum FolderScanner { static func scan(_ folder: URL) throws -> [ListedFile] }`, newest first, recursive, skipping hidden folders
  - `final class DocumentFile` with `init(url:) throws`, `var text: String`, `var isReadOnly: Bool`, `func save(_ text: String) throws`, `func checkDisk() -> DiskChange` where `enum DiskChange { unchanged, changed(String), missing }`, and `func saveConflictCopy(_ diskText: String) throws -> URL`

- [ ] **Step 1:** Write failing tests: `nameStripsHeadingMarks`, `nameFallsBackToUntitled`, `nameRemovesSlashes`, `uniqueURLAddsNumber`, `conflictNameFormat` (expects `Name (conflict).md`), `scanFindsNestedNewestFirst`, `scanSkipsHiddenFolders`, `loadWithoutSaveLeavesBytes`, `saveKeepsCRLFAndBOM`, `nonUTF8IsReadOnly`, `readOnlySaveThrows`, `checkDiskSeesExternalChange`, `checkDiskSeesMissingFile`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement. Writes are atomic. Decode with `String(data:encoding:.utf8)`, keeping the BOM in the string.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Commit.

### Task 7: App shell

**Files:** Create `AppModel.swift`, `RootView.swift`, `FileListView.swift`, `FolderWatcher.swift`; modify `ClaudetteApp.swift`.

**Interfaces:**
- Consumes: Task 3, 5, and 6 types.
- Produces: `@MainActor final class AppModel: ObservableObject` with `folders`, `sections`, `currentFile`, `viewMode`, `themeName`, `isFileListOpen`, `connect(_:)`, `disconnect(_:)`, `open(_:)`, `newFile()`, `importFiles(_:into:)`, `rename(_:to:)`, `trash(_:)`.

- [ ] **Step 1:** Add tests in the app test target: `importGoesToCurrentFolder`, `importRepeatedNameGetsNumber`, `newFileNamedOnceOnFirstSave`, `disconnectLeavesFiles`, `firstLaunchCreatesStarterFolder`. Run. Expected: FAIL.
- [ ] **Step 2:** Implement `AppModel`, persistence, autosave, and disk conflict handling. Implement `FolderWatcher` with FSEvents, and the accent dot for new files.
- [ ] **Step 3:** Implement `RootView` per the spec's window section, with eye and `#` icons, the slide-in list, drops, and an empty state. Add commands and the View menu theme picker.
- [ ] **Step 4:** Run tests. Expected: PASS.
- [ ] **Step 5:** Commit.

### Task 8: End-to-end check

**Files:** Modify `README.md`.

- [ ] **Step 1:** Build and run. Exercise a sample project folder: connect, external file arrives, edit in both views, table edit, import, drag, conflict, rename, trash.
- [ ] **Step 2:** Run all tests with `swift test --package-path Core` and `xcodebuild test -scheme Claudette`. Expected: all pass.
- [ ] **Step 3:** Render final screenshots in both themes and both views, and send them.
- [ ] **Step 4:** Update `README.md` with how to build and run. Commit.
