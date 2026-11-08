# Claudette

A native macOS Markdown reader and editor for files Micky gets from Claude. Start with [docs/roadmap.md](docs/roadmap.md): it covers what's been built, where things stand, and what's next.

## Ground rules

- **The file's text is the only source of truth.** The formatted view only changes how the text is drawn. Opening or viewing a file must never change its bytes, and an edit must never be lost (autosave, conflict copies, saving before trash or quit).
- Changes are test-first. Watch the new test fail before writing the fix, then run the full suites.
- Behavior changes go on a branch (`claude/<topic>`). Commit, push, open a PR, or merge only when Micky asks.

## Build and test

```bash
xcodegen generate                      # after adding, removing or renaming files (project.yml is the source)
(cd Core && swift test)                # core: parsing, tables, lists, links, files
xcodebuild test -project Claudette.xcodeproj -scheme Claudette -derivedDataPath build -only-testing:ClaudetteTests
xcodebuild build -project Claudette.xcodeproj -scheme Claudette -derivedDataPath build
```

The app builds to `build/Build/Products/Debug/Claudette.app`. That's the copy Micky runs.

For timing, use a release build: add `-configuration Release ENABLE_TESTABILITY=YES` and a separate derived data folder.

### Seeing the app without a screen

The app binary renders a PNG and quits:

```bash
APP=build/Build/Products/Debug/Claudette.app/Contents/MacOS/Claudette
$APP -snapshotFile doc.md -snapshotOut out.png -snapshotTheme slate -snapshotHeight 900   # one document
$APP -snapshotFolder dir -snapshotOut out.png -snapshotList YES -snapshotGuide YES         # whole window
```

Other options: `-snapshotMode markdown`, `-snapshotCursor <offset>`, `-snapshotOpenedFile <path>`. Snapshots wait for web pictures to load.

### Restarting Micky's copy

Quitting saves first, so this is safe. Check that Micky isn't mid-edit first, by looking at recent file times in `~/Claudette`.

```bash
osascript -e 'tell application id "com.mickyhingorani.Claudette" to quit'
open build/Build/Products/Debug/Claudette.app
```

Don't touch Micky's files, `~/Claudette` or app settings unless asked. Tests use scratch settings and temporary folders.

## How the code fits together

- **`Core/` (ClaudetteCore, Swift 6), plain logic with no UI:**
  - `MarkdownScanner`: text → `StyleMap` (spans, hidden syntax, substitutions, tables, code blocks, images, callouts, paragraph breaks).
  - `TableBlock` / `TableEditor`, `ListEditing`, `LinkTarget`, `MarkdownGuide`: editing rules that return `TextEdit`s.
  - `CodeHighlighter`: bundled highlight.js run in JavaScriptCore.
  - `DocumentFile`, `FileNaming`, `FolderScanner`, `LineIndex`.
- **`App/` (Swift 5 mode):**
  - `AppModel`: folders, the file list, opened files, notices.
  - `DocumentSession`: every save, reload, conflict, rename and trash rule.
  - `Theme`: colors and bundled fonts in `App/Fonts`.
  - `GuideView`.
  - `App/AppIcon.icon`: an Icon Composer file.
- **`App/Editor/`:**
  - `EditorTextView`: a TextKit 1 `NSTextView`. It handles cursor rules around hidden syntax, Return/Tab/Backspace, and overlays.
  - `EditorStyler`: `StyleMap` → attributes. It restyles only the region an edit affects and is checked against a full restyle by a random-edit test.
  - `HidingLayoutManager`: hides syntax, reserves space for tables and pictures, and draws code backgrounds, callouts, checkboxes and underlines.
  - Overlay views: tables, pictures, code labels.

## Lessons that cost time

- **Hidden glyphs:** hidden text uses the `.controlCharacter` glyph property, not `.null`. Null glyphs at a line start join the previous line, which breaks the cursor and arrow keys.
- **No layout while editing:** never lay out or invalidate during `didProcessEditing`. Pass `invalidate: false` there, or you get "invalid glyph index" errors.
- **Cursor height:** the cursor takes its height from the line's used rect, which is trimmed to the text. Only the full line rect grows for gaps, tables and pictures.
- **Glyph ranges:** `glyphRange(forCharacterRange:)` runs on through following hidden glyphs, so map characters to glyphs one at a time.
- **Empty list items:** an item like `  - ` with nothing after it isn't a list item to the parser. While scanning, it gets an invisible filler character at its line end, and `LineIndex` clamps columns to their line.
- **Theme fonts:** they lack `◦` and `▪`, so bullet substitutions fall back to the system font or Apple Symbols.
- **Watcher paths:** FSEvents reports `/private/var` where folders may be stored as `/var`. Compare resolved paths.
- **Test setup:** main-thread test classes use a plain `setUp()`, not `setUpWithError()`. The throwing version crashed XCTest twice.

## Working with Micky

- Micky often steers from a phone. Send visuals as PNG screenshots with `SendUserFile`, never local links.
- Keep [docs/review-2026-11-07.md](docs/review-2026-11-07.md) and [docs/roadmap.md](docs/roadmap.md) current as work lands. Mark each item fixed, partly fixed or not fixed, with the proving test.
- Say plainly what was checked by hand and what wasn't.
- Commit messages end with the co-author line, and PR bodies with the Claude Code line. Both are given in session instructions.
