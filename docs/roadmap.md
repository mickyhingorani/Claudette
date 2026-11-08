# Claudette roadmap

Where Claudette has been, where it is, and what's next. Updated as work lands.

## Why it exists

Micky gets Markdown files from Claude and wanted a calm place on the Mac to read and edit them. The files stay out of Obsidian and Google Drive, and live in local project folders. See the [design document](superpowers/specs/2026-11-07-claudette-mvp-design.md) for the full intent.

## Where we've been

| PR | Merged | What it added |
|---|---|---|
| [#1](https://github.com/mickyhingorani/Claudette/pull/1) | 7 Nov | The MVP: formatted and Markdown views, both editable, real drawn tables, connected folders, import and drag-in, autosave, conflict copies |
| [#2](https://github.com/mickyhingorani/Claudette/pull/2) | 7 Nov | Themes with their own colors, syntax colors for code, a resizable file list, hidden heading marks, Return starting a new paragraph |
| [#3](https://github.com/mickyhingorani/Claudette/pull/3) | 7 Nov | Bundled fonts for each theme; Ink removed; Slate made the default |
| [#4](https://github.com/mickyhingorani/Claudette/pull/4) | 8 Nov | Pictures, callouts, drawn checkboxes, the app icon, the Markdown guide, list continuation and sub-bullets, all 15 code-review fixes, faster typing, and two cleanups |
| [#5](https://github.com/mickyhingorani/Claudette/pull/5) | 8 Nov | A language label and Copy button on code blocks |
| [#6](https://github.com/mickyhingorani/Claudette/pull/6) | 8 Nov | Opening a Markdown file from anywhere, in place, with an "Opened files" list |
| [#7](https://github.com/mickyhingorani/Claudette/pull/7) | 8 Nov | Emoji and symbols draw again; this roadmap and `CLAUDE.md` |
| [#8](https://github.com/mickyhingorani/Claudette/pull/8) | 8 Nov | The Harbor theme: deep teal, gold and pink, serif titles, a blue Note callout, outlined code |
| [#9](https://github.com/mickyhingorani/Claudette/pull/9) | 8 Nov | Harbor Light, the first light theme; window controls that follow the theme; a themes page listing every font and color |

Decisions along the way:
- **Folder app, not library app.** Claudette works on folders and files where they are, and keeps no private copy. A write-up of the two approaches is in the design document.
- **Folder structure:** a folder for each project, with the file from Claude inside, opened in Claudette.
- **Return** starts a new paragraph (Markdown's blank line, hidden as a half-line gap); **Shift-Return** breaks a line.

## Where we are

Claudette reads and edits Markdown with:
- **Views:** a formatted view and a Markdown view (`⌘E`), both editable. The formatted view hides Markdown syntax except where the cursor is.
- **Themes:** Slate (the default), Solarized, Nord, Harbor, Harbor Light and Terminal, each with its own fonts and colors; [docs/themes.md](themes.md) lists them all. Harbor Light is the one light theme, and the window's controls turn light with it. Harbor (deep teal, gold and pink, after a developer docs site) adds serif titles, a blue Note callout and outlined code.
- **Text and code:** headings, bold, italics, links, strikethrough, inline code, quotes and dividers. Code blocks get syntax colors, a language label and a Copy button.
- **Tables:** drawn as real tables and edited in place.
- **Pictures:** from the Mac or the web.
- **Callouts:** `> [!NOTE]` and its four siblings draw as tinted boxes.
- **Lists:** they continue on Return and nest with Tab, with hollow sub-bullets. Checkboxes are drawn as boxes and tick when clicked.
- **Markdown guide:** a panel (`⌘/`) where clicking an example inserts it.
- **Files:**
  - Connected folders.
  - Opening any file in place (`⌘O`, Finder's Open With, or drag-in).
  - Autosave, conflict copies, and reloading when a file changes outside the app.
- **Links:** ⌘-click opens web and email links, and links to other Markdown notes.

The code is on `main`, and 546 tests pass. The app runs from Xcode's build folder; it isn't installed in Applications yet.

## What's next

Nothing is in progress. Saved for later, roughly in order of usefulness:

1. **Two bugs you could hit in normal use:**
   - Clicking the file that's already open clears its undo history and jumps to the top.
   - Pausing partway through a new file's first line can lock in a partial file name.
2. **Install Claudette properly:** a release build in Applications, so it opens from Spotlight.
3. **Split the two largest code files** (`EditorTextView`, `HidingLayoutManager`). No visible change, about 20 to 30 minutes.
4. **Small options:**
   - A Copy button on code blocks with no language named.
   - A slightly bigger hollow bullet.
5. **One "can edit" check** shared by text, table cells and checkboxes.
6. **The rest of [known issues](known-issues.md):** table edge cases, rename quirks, backslash escapes, Finder tags lost on save, and similar minor items.

## Dropped, by choice

- **Font picker:** each theme has its own chosen fonts instead.
- **Focus mode.**
- **Pictures for images in the middle of a sentence:** these still show as Markdown text.
- **Re-reading only the edited part of a document on each keystroke:** restyling is already limited to the edit. The remaining re-read is about 13 ms at 43,000 characters, so it isn't worth the risk unless book-length files come up.
- **Library features** (search, tags, recents across folders): not needed while files live in project folders.

## Other records

- [Design document](superpowers/specs/2026-11-07-claudette-mvp-design.md): intent, goals, decisions, and the library-versus-folder write-up.
- [Code review, 7 November](review-2026-11-07.md): every finding, its fix and its test.
- [Themes](themes.md): every theme's fonts and colors, with screenshots.
- [Known issues](known-issues.md): minor bugs left for later.
- [MVP plan](superpowers/plans/2026-11-07-claudette-mvp.md): how the first version was built, now finished.
