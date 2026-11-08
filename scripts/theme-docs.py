# Writes docs/themes.md from App/Theme.swift. Run from the repository root:
#   python3 scripts/theme-docs.py App/Theme.swift docs/themes.md
# Screenshots: for each theme id,
#   $APP -snapshotFile docs/images/themes/sample.md -snapshotOut docs/images/themes/<id>.png -snapshotTheme <id> -snapshotHeight 600
import re, sys
src = open(sys.argv[1]).read()
order = re.search(r'static let all = \[(.*?)\]', src).group(1).replace(' ','').split(',')
blocks = {}
for m in re.finditer(r'static let (\w+) = Theme\((.*?)\)\)\s*\n', src, re.S):
    blocks[m.group(1)] = m.group(2)

def colors(b): return {k: '#'+v.upper() for k, v in re.findall(r'(\w+): color\(0x([0-9A-Fa-f]{6})', b)}
def fonts(b): return {k: (f, float(sz)) for k, f, sz in re.findall(r'(\w+): font\("([^"]+)", size: ([\d.]+)\)', b)}

about = {
 'slate': 'The default. Warm coral, peach and gold on a blue-grey night.',
 'nord': 'Cool and quiet: frost blues and soft greens, after the Nord palette.',
 'solarized': 'The classic Solarized dark colors on deep blue-green.',
 'harbor': 'Deep teal with gold and pink, after a developer docs site. The only theme with serif titles, outlined code and a blue Note callout.',
 'harborLight': 'Harbor by day: warm paper, near-black text, teal and pink, after the same docs site in its light mode. Window controls and scroll bars turn light with it.',
 'terminal': 'Green on black, one coding font for everything.',
}
page_roles = [
 ('background','Page background'),('text','Body text'),('soft','Softer text: quotes, finished tasks, the file list'),
 ('dim','Faint text: Markdown marks, dividers, code language labels'),('accent','Cursor, list bullets and numbers'),('chip','Inline code background'),
 ('panel','Code block background (and the file list and guide, unless set below)'),('line','Table lines (and selected text, unless set below)'),('selectionColor','Selected text and the current file'),('sidePanelColor','File list and guide background'),('outline','Outline around inline code and code blocks'),
]
text_roles = [
 ('heading1','`#` titles'),('heading2','`##` headings'),('heading3','`###` and smaller'),('strong','**Bold**'),
 ('emphasis','*Italics*'),('link','Links and their underline'),('check','Checkboxes'),('inlineCode','Inline code text'),
 ('quoteBar','Quote bar'),('tableHeader','Table header background'),('tableHeaderText','Table header text'),
]
code_roles = [
 ('keyword','Keywords (`func`, `return`)'),('string','Strings'),('number','Numbers'),('comment','Comments'),
 ('function','Function names'),('tag','HTML tags'),('attribute','Attributes and JSON keys'),('type','Types'),
]
def row(c, key, use): return f'| {use} | `{c[key]}` |' if key in c else None
out = []
out.append('''# Themes

Claudette has six themes: five dark and one light. Each has its own fonts and colors, chosen together. Pick one under View → Theme.

All fonts ship inside the app under the SIL Open Font License; their licenses are in [App/Fonts](../App/Fonts). The colors are checked by tests: body text, links, bold, italics and code colors are at least 4.5 to 1 against their background (the WCAG AA level), and headings and comments at least 3 to 1.

The source of truth is [App/Theme.swift](../App/Theme.swift). A test fails if a theme changes there and this page doesn't.

**Sizes, in every theme:** body text is 16 points (15 in Terminal) and code 14. Headings are 1.7×, 1.35× and 1.15× the body size for `#`, `##` and `###`.

**Callouts** borrow colors that already mean something in each theme: Note uses the link color (Harbor has its own blue), Tip the checkbox color, Important italics, Warning bold, and Caution inline code.

| Theme | Text | Code |
|---|---|---|''')
for t in order:
    b = blocks[t]; f = fonts(b); name = re.search(r'name: "([^"]+)"', b).group(1)
    title = f['titleFace'][0] + ' (titles), ' if 'titleFace' in f else ''
    out.append(f'| [{name}](#{name.lower().replace(" ", "-")}) | {title}{f["bodyFont"][0]} | {f["monoFont"][0]} |')
for t in order:
    b = blocks[t]; c = colors(b); f = fonts(b); name = re.search(r'name: "([^"]+)"', b).group(1)
    tid = re.search(r'id: "([^"]+)"', b).group(1)
    out.append(f'\n## {name}\n\n{about[t]}\n\n![{name}](images/themes/{tid}.png)\n')
    out.append('**Fonts**\n\n| Used for | Font |\n|---|---|')
    if 'titleFace' in f: out.append(f'| `#` titles (regular weight) | {f["titleFace"][0]} |')
    out.append(f'| {"Smaller headings (bold)" if "titleFace" in f else "Headings (bold)"} | {f["headingFont"][0]} |')
    out.append(f'| Body text | {f["bodyFont"][0]} |')
    out.append(f'| Code | {f["monoFont"][0]} |')
    for heading, roles in [('Page', page_roles), ('Text', text_roles), ('Code', code_roles)]:
        out.append(f'\n**{heading} colors**\n\n| Used for | Color |\n|---|---|')
        out += [r for r in (row(c, k, u) for k, u in roles) if r]
        if heading == 'Text' and 'note' in c: out.append(f'| Note callouts | `{c["note"]}` |')
open(sys.argv[2], 'w').write('\n'.join(out) + '\n')
