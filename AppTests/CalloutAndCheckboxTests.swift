import AppKit
import XCTest
import ClaudetteCore
@testable import Claudette

@MainActor
final class CalloutTests: XCTestCase {
    private func makeEditor(_ text: String, theme: Theme = .slate) -> EditorTextView {
        let (_, editor) = EditorTextView.makeInScrollView()
        editor.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        editor.theme = theme
        editor.load(text: text)
        editor.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        return editor
    }

    private func color(_ editor: EditorTextView, at index: Int) -> NSColor? {
        editor.textStorage!.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
    }

    private let note = "> [!NOTE]\n> Read this.\n\nafter\n"

    func testMarkerIsHiddenAwayFromTheCaret() {
        let editor = makeEditor(note)
        XCTAssertTrue(editor.hidingLayoutManager.isHidden(at: 2))
    }

    func testCalloutIsDrawnAsACalloutNotAQuote() {
        let editor = makeEditor(note)
        let decorations = editor.styler.decorations
        XCTAssertEqual(decorations.callouts.map(\.kind), [.note])
        XCTAssertTrue(decorations.quotes.isEmpty)
    }

    func testOrdinaryQuoteStillHasItsBar() {
        let editor = makeEditor("> plain\n")
        XCTAssertEqual(editor.styler.decorations.quotes.count, 1)
        XCTAssertTrue(editor.styler.decorations.callouts.isEmpty)
    }

    func testCalloutTextUsesTheNormalTextColor() {
        let editor = makeEditor(note)
        XCTAssertEqual(color(editor, at: 12), Theme.slate.text)
    }

    func testCustomTitleIsBoldInTheCalloutColor() {
        let editor = makeEditor("> [!WARNING] Mind the gap\n> x\n")
        XCTAssertEqual(color(editor, at: 14), Theme.slate.palette.callout(.warning))
        let font = editor.textStorage!.attribute(.font, at: 14, effectiveRange: nil) as! NSFont
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
    }

    func testFirstLineLeavesRoomForTheIcon() {
        let editor = makeEditor(note)
        let style = editor.textStorage!.attribute(.paragraphStyle, at: 2, effectiveRange: nil) as! NSParagraphStyle
        XCTAssertGreaterThan(style.firstLineHeadIndent, style.headIndent)
    }

    func testDefaultTitleIsShownOnlyWithoutACustomOne() {
        XCTAssertEqual(makeEditor(note).styler.decorations.callouts.first?.showsDefaultTitle, true)
        XCTAssertEqual(makeEditor("> [!TIP] Mine\n> x\n").styler.decorations.callouts.first?.showsDefaultTitle, false)
    }

    func testEveryThemeHasReadableCalloutColors() {
        for theme in Theme.all {
            for kind in CalloutKind.allCases {
                XCTAssertGreaterThanOrEqual(ThemeContrast.ratio(theme.palette.callout(kind), theme.background), 3, "\(theme.name) \(kind)")
            }
        }
    }

    func testMarkdownViewDrawsNoCallout() {
        let editor = makeEditor(note)
        editor.viewMode = .markdown
        XCTAssertTrue(editor.styler.decorations.callouts.isEmpty)
    }
}

@MainActor
final class CheckboxTests: XCTestCase {
    private func makeEditor(_ text: String) -> EditorTextView {
        let (_, editor) = EditorTextView.makeInScrollView()
        editor.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        editor.theme = .slate
        editor.load(text: text)
        editor.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        return editor
    }

    func testBoxesAreDrawnNotTyped() {
        let editor = makeEditor("- [ ] open\n- [x] done\n\nend\n")
        XCTAssertEqual(editor.styler.decorations.checkboxes.map(\.isChecked), [false, true])
        XCTAssertEqual(editor.styler.decorations.checkboxes.map(\.location), [0, 11])
    }

    func testBoxOnTheCaretLineShowsItsSourceInstead() {
        let editor = makeEditor("- [ ] open\n\nend\n")
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        XCTAssertTrue(editor.styler.decorations(selection: editor.selectedRange()).checkboxes.isEmpty)
    }

    func testCheckedTaskTextIsDimmed() {
        let editor = makeEditor("- [x] done\n- [ ] open\n")
        let checked = editor.textStorage!.attribute(.foregroundColor, at: 7, effectiveRange: nil) as? NSColor
        let open = editor.textStorage!.attribute(.foregroundColor, at: 18, effectiveRange: nil) as? NSColor
        XCTAssertEqual(checked, Theme.slate.soft)
        XCTAssertEqual(open, Theme.slate.text)
    }

    func testBoxIsSizedToTheText() throws {
        let editor = makeEditor("- [ ] open\n\nend\n")
        let rect = try XCTUnwrap(editor.hidingLayoutManager.checkboxRect(at: 0))
        let font = editor.textStorage!.attribute(.font, at: 6, effectiveRange: nil) as! NSFont
        XCTAssertEqual(rect.width, rect.height)
        XCTAssertGreaterThan(rect.width, font.capHeight)
        XCTAssertLessThan(rect.width, font.ascender - font.descender)
    }
}

@MainActor
final class CalloutSpacingTests: XCTestCase {
    func testStackedCalloutsStayApart() throws {
        let text = "> [!NOTE]\n> One.\n\n> [!TIP]\n> Two.\n"
        let (_, editor) = EditorTextView.makeInScrollView()
        editor.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        editor.load(text: text)
        let layout = editor.hidingLayoutManager
        layout.ensureLayout(for: editor.textContainer!)
        let callouts = editor.styler.decorations.callouts
        let first = try XCTUnwrap(layout.calloutRect(of: callouts[0].range))
        let second = try XCTUnwrap(layout.calloutRect(of: callouts[1].range))
        XCTAssertGreaterThanOrEqual(second.minY - first.maxY, 8)
    }

    func testTextBelowACalloutClearsItsBox() throws {
        let text = "> [!NOTE]\n> One.\n\nafter\n"
        let (_, editor) = EditorTextView.makeInScrollView()
        editor.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        editor.load(text: text)
        let layout = editor.hidingLayoutManager
        layout.ensureLayout(for: editor.textContainer!)
        let box = try XCTUnwrap(layout.calloutRect(of: editor.styler.decorations.callouts[0].range))
        let after = layout.lineFragmentUsedRect(forGlyphAt: layout.glyphIndexForCharacter(at: 18), effectiveRange: nil)
        XCTAssertGreaterThanOrEqual(after.minY - box.maxY, 8)
    }
}
