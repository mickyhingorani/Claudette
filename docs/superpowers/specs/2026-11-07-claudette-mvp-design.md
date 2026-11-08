# Claudette MVP Design

Date: 2026-11-07

## Why this exists

Micky gets Markdown files from Claude and has nowhere good to keep them. Google Drive is messy, and these files should stay separate from Obsidian and other existing structure. Claudette is a local Mac home for those files: a calm place to read them and edit them easily.

Success for the MVP: a file from Claude lands in Claudette, reads beautifully, and can be changed in place without thinking about file management.

## Goals

- Read Markdown files in a clean, dark, nicely formatted view.
- Edit in both the formatted view and the Markdown view.
- Keep every file local, in whichever folders Micky connects, such as a folder for a project that Claude is also attached to.
- Bring files in by importing or dragging them.
- Draw tables as real tables, editable in place.
- Pick up files Claude saves into a connected folder without any action from Micky.
- Keep the window nearly free of chrome.

## Non-goals for the MVP

- Search, tags, or favorites
- Sync, sharing, or export
- Creating or moving subfolders inside the app (the folder structure gets its own conversation later)
- Being the default app for opening `.md` files from Finder
- Font choices and a full theme picker
- iPhone or iPad versions
- App Store distribution

## Anti-goals

- **Never damage a file.** Opening, viewing, or switching views must not change a file's text. Only Micky's actual edits change it.
- **Never lose an edit.** No Save button means saving has to be dependable.
- **No clutter.** If a control doesn't earn its place on screen, it goes in the menu bar.

## What Micky decided

- **Layout:** the document fills the window. A file list slides in and out from the left.
- **View switch:** two icons at the top right, an eye for formatted and `#` for Markdown. No words.
- **Editing:** both views are editable.
- **Look:** dark, with strong text contrast. A terminal-style look (monospaced font, green on black) is wanted as an option.
- **Storage:** everything lives locally on the Mac.
- **Folders and import:** the app can connect to any folder and can import files. Files can be dragged in. Files should not all be funneled into one dedicated folder: Micky works in per-project folders and wants to attach both Claudette and Claude to the same project folder.
- **Tables:** real drawn tables from the start.
- **Priority:** MVP first. More look options come later.

## How it behaves

### The window

- Traffic-light buttons, a file list icon, and the view switch sit in one slim top bar with no visible title bar.
- Text sits in a centered column with a comfortable reading width.
- The file list slides over from the left and pushes the text column aside. `⌘\` toggles it.
- `⌘E` switches between formatted and Markdown views.
- The app reopens to the last file, view, and theme.
- There is one window. With no files yet, it opens a new empty file ready for typing or pasting.

### Files

- Claudette works on folders that stay where they are, the way VS Code or iA Writer do. It has no private library, and nothing is moved or copied unless Micky imports it.
- **Connect Folder** (File menu) links any folder on the Mac, such as a project folder Claude is also attached to. Files there are edited in place. Several folders can be connected at once.
- Dragging a folder onto the window connects it. Right-clicking a connected folder offers Disconnect, which leaves its files untouched.
- On first launch, a starter folder, `~/Claudette`, is created and connected so there's somewhere to begin. It behaves like any other folder and can be disconnected. *(Claude's call, see below.)* With no folders connected, the window invites Micky to connect one.
- **The current folder** is the one holding the open file. With nothing open, it's the first folder in the list.
- **Import** (File menu) copies chosen `.md` files into the current folder and opens the first one. Dragging `.md` files onto the window does the same, and dropping them on a folder's section in the file list puts them in that folder.
- The file list has one section per folder. Each section shows every `.md` file in that folder and its subfolders as a flat list, newest first. Names drop the `.md`.
- A file that arrives while the app is open appears within a couple of seconds, with an accent dot until it's opened.
- `⌘N` creates a new file in the current folder. It's named once, from its first line of text when it's first saved, falling back to `Untitled`. Later edits don't rename it, and a repeated name gets a number added. Imports with a repeated name also get a number added.
- Pasting Markdown into a new file is how content comes in from the Claude app.
- Right-clicking a file offers Rename and Move to Trash.

### Editing and saving

- Both views show one shared text, so switching views keeps the cursor position and undo history.
- **Markdown view:** the plain text, in a monospaced font, with the syntax in the accent color.
- **Formatted view:** the same text with headings, bold, italics, links, lists, quotes, and code styled, and the syntax characters hidden. When the cursor enters a styled piece of text, its syntax characters reappear so they can be edited, then hide again when the cursor leaves.
- Formatting shortcuts work in both views: `⌘B` bold, `⌘I` italic, `⌘K` link.
- Edits save automatically about a second after typing stops, and also when switching files, leaving the app, or quitting.
- If another program changes the open file, Claudette reloads it when there are no unsaved edits. If there are, Micky's version stays in the file and the other version is saved beside it as `Name (conflict).md`.

### Markdown coverage

- Fully styled in the formatted view: headings, bold, italic, strikethrough, inline code, code blocks, links, bullet and numbered lists, task lists, quotes, and horizontal rules.
- Task-list checkboxes display as checkboxes, and clicking one toggles it.
- **Tables** draw as real tables in the formatted view, with a header row, cell lines, column alignment, and text that wraps inside cells. Inline styling such as bold and links works in cells.
- **Editing a table:** clicking a cell edits it in place, and `Tab` moves to the next cell. `Tab` in the last cell adds a row. Right-clicking offers add or delete row and column. Only the text that changed is rewritten, so the rest of the file stays as it was. The Markdown view shows the table's plain source.
- **Images** show as their dimmed source text, not as pictures.
- YAML frontmatter shows dimmed at the top.
- `⌘`-click opens a link in the default browser.

### Themes

Two themes ship, switched from the View menu:

| Theme | Background | Text | Accent | Font |
|---|---|---|---|---|
| Ink (default) | `#121212` | `#F7F4EC` | `#FFFFFF` | New York or Georgia serif |
| Terminal | `#050805` | `#4DFF88` | `#D6FFE4` | Menlo |

Terminal keeps heading `#` marks visible in the formatted view, as in the mockup. Themes are defined as data, so more can be added later without reworking the app. Midnight and Ember are the likely next ones. The mockup is at `.superpowers/` locally and is not part of the repo.

## How it gets made (Claude's calls)

- **Native Mac app in Swift:** a SwiftUI shell with an AppKit `NSTextView` for the editor. Native text gives fast scrolling, real undo, spellcheck, and Mac text behavior.
- **One text, two stylings, rather than a web-based rich editor.** Web editors convert Markdown into their own format and write it back, which can quietly rewrite a file (for example changing `*` bullets to `-`). Here the file's text is the only source of truth, and the formatted view only changes how it's drawn. This is what makes the "never damage a file" anti-goal achievable. The cost is more custom work for tables and the image limit above.
- **Tables within that model:** the table's source lines stay in the text but are hidden, and a drawn table takes their place. Each cell maps to its exact position in the source, so a cell edit changes only that cell's text. The file's pipes and spacing are otherwise left alone.
- **Parsing:** Apple's `swift-markdown` package, for its GitHub-flavored Markdown support and source positions.
- **Biggest technical risks:** hiding syntax characters while keeping the cursor and selection behaving well, and drawing editable tables inside the text. The plan should prove both first, before building around them.
- **Starter folder location:** `~/Claudette` rather than `~/Documents`, which avoids macOS privacy prompts and iCloud Documents syncing, and is simple to connect to Claude. Revisit in the folder-structure conversation.
- **Distribution:** built locally and signed with Micky's Apple Development certificate, with App Sandbox off so folders can be watched simply. macOS may still ask permission once for protected places such as Documents or Desktop. No notarization.
- **Minimum macOS:** the version on Micky's Mac is fine. Supporting older versions is not a goal.

## Worth revisiting: library apps versus folder apps

Apps generally handle files in one of two ways.

**Library apps** (Apple Notes, Bear, Photos) keep their own private store, and importing copies files into it.

- Good: simple to use, nothing to organize, and the app can offer fast search, tags, and sync.
- Bad: files are tied to the app, other tools can't easily reach them, and copies drift apart from the originals.

**Folder apps** (VS Code, iA Writer, Obsidian) point at folders you already have, and files stay where they are.

- Good: files stay ordinary files, other tools can work on them, and they fit an existing project structure.
- Bad: you do more of the organizing yourself, and search or tags across folders take more work to build.

**Decision for the MVP:** Claudette is a folder app. Micky works in per-project folders and wants Claudette and Claude attached to the same folder, which only works if files stay in place.

**Why revisit:** a library-style layer could sit on top later, such as a cross-folder recents view, tags, or search, without moving any files. Revisit this alongside the folder-structure conversation.

## Folder structure (decided 8 November)

Micky makes a folder for each project on the Mac, puts the Markdown file from Claude in it, and opens that file in Claudette. So:

- **File › Open… (⌘O)**, Finder's **Open With**, and dragging a file onto the window all open the file where it is. Nothing is copied, and the file's folder is not connected.
- Files opened this way are listed under **Opened files** at the top of the file list, newest first, up to 10. Right-click offers Show in Finder and Remove from List, which never touches the file. A file moved or deleted elsewhere drops off the list.
- Their folders are watched, so an outside change to an opened file is still reloaded or kept as a conflict copy.
- Claudette is an Open With choice for Markdown files, not the default; making it the default is left to Micky in Finder (Get Info › Open with › Change All).
- Connecting folders, the `~/Claudette` starter folder, and Import (which copies) are unchanged. Dropping a file on a folder's section in the list still copies it into that folder.

## Left to the builder

- Project generation, file layout, and folder-watching mechanism
- Exact timing of autosave and animations
- Exact spacing and type sizes, staying close to the mockups
- App icon (a simple placeholder is fine)

## How we'll know it works

- Automated tests cover the parts that can quietly go wrong: opening and saving leaves a file byte-for-byte unchanged, styling finds the right ranges, a table cell edit changes only that cell's text, new-file and import naming, and conflict handling.
- Micky reviews from the phone using screenshots of the real app in both themes and both views.
