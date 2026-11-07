# Claudette

A simple, dark Markdown app for macOS, with minimal chrome. It's a calm place to read and edit Markdown files, especially ones Claude writes, right where they live on your Mac.

- Edit in a formatted view or a plain Markdown view (`⌘E`). Both show the same text, so viewing a file never changes it.
- Tables are drawn as real tables. Click a cell to edit it.
- Connect any folder, such as a project folder Claude also works in. New files appear on their own.
- Import files, or drag them onto the window. Drag a folder in to connect it.
- Edits save automatically.
- Four themes, each with its own colors and fonts:
  - Slate (the default): Atkinson Hyperlegible Next, with JetBrains Mono code
  - Solarized: IBM Plex Sans, with IBM Plex Mono code
  - Nord: Geist, with Geist Mono code
  - Terminal: JetBrains Mono throughout
- Code blocks are syntax highlighted for about 190 languages, in each theme's colors.

## Build and run

Open `Claudette.xcodeproj` in Xcode and press Run, or:

```bash
xcodebuild -scheme Claudette -destination 'platform=macOS' -derivedDataPath build build
open build/Build/Products/Debug/Claudette.app
```

`project.yml` is the source of truth for the Xcode project. After changing it, run `xcodegen generate`.

## Test

```bash
swift test --package-path Core
xcodebuild -scheme Claudette -destination 'platform=macOS' -derivedDataPath build test
```

## Credits

Syntax highlighting uses [highlight.js](https://highlightjs.org), bundled under its BSD 3-Clause license.

The fonts are bundled under the SIL Open Font License 1.1, with each license in `App/Fonts`: [Atkinson Hyperlegible Next](https://www.brailleinstitute.org/freefont/), [Geist and Geist Mono](https://github.com/vercel/geist-font), [IBM Plex Sans and IBM Plex Mono](https://github.com/IBM/plex), and [JetBrains Mono](https://github.com/JetBrains/JetBrainsMono).

## Shortcuts

| Action | Shortcut |
|---|---|
| New file | `⌘N` |
| Connect folder | `⇧⌘O` |
| Import | `⇧⌘I` |
| Show or hide file list | `⌘\` |
| Switch view | `⌘E` |
| Bold, italic, link | `⌘B`, `⌘I`, `⌘K` |
| New paragraph (formatted view) | `Return` |
| Line break inside a paragraph | `⇧Return` |
