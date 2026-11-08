# Known issues

Minor items from the independent code review of the MVP, left for later.

## Tables

- A cell ending in a backslash in a compact table (`|a\|b|`) escapes the next pipe and merges two cells. Spaced tables are fine.
- A U+2028 character in a cell splits it into two displayed rows.
- Very wide tables run past a narrow window, with no way to scroll sideways.
- `⌘`-click on a link in a cell starts editing the cell instead of opening the link.
- `⌘B`, `⌘I`, and `⌘K` do nothing inside a cell.

## Editing

- Clicking the file that's already open clears its undo history and moves the cursor to the top.
- A checkbox toggle right after typing undoes together with the typing.
- Return in a CRLF file inserts a bare LF. Existing line endings are untouched.
- `⌘I` on selected bold text turns `**bold**` into `*bold*`.
- Backslash escapes like `\*` still show in the formatted view.
- The whole document is re-read and restyled on every keystroke: about 66 ms at 43,000 characters in a release build, so very large files feel slow.
- Backspace on the line right below a table merges that line into the table's last row. Undo restores it.

## Files

- Each save drops Finder tags, breaks hard links, and can overwrite a read-only file.
- Rename quirks: `foo` to `Foo` gives `Foo 2.md`, `_draft-` gives `draft`, and blank gives `Untitled`.
- A one-second pause partway through a new file's title fixes a partial file name permanently.
- Drops land on a folder's header in the file list, not its whole section.
- A file already in another connected folder isn't copied when dropped on a section.

## Look

- An image in the middle of a sentence shows as its Markdown text, not as a picture.
- Animated GIFs show only their first frame.

- No app icon yet.
- An inline code chip that wraps across two lines runs a little past its text on the first line.
