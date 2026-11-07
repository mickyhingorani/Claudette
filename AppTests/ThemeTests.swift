import AppKit
import XCTest
@testable import Claudette

final class ThemeTests: XCTestCase {
    private func luminance(_ color: NSColor) -> CGFloat {
        let c = color.usingColorSpace(.sRGB)!
        func channel(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(c.redComponent) + 0.7152 * channel(c.greenComponent) + 0.0722 * channel(c.blueComponent)
    }

    private func contrast(_ a: NSColor, _ b: NSColor) -> CGFloat {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    func testAllThemesAreOffered() {
        XCTAssertEqual(Theme.all.map(\.name), ["Ink", "Slate", "Nord", "Solarized", "Terminal"])
    }

    func testEachThemeHasItsOwnFont() {
        XCTAssertEqual(Set(Theme.all.map { $0.bodyFont.familyName }).count, Theme.all.count)
    }

    func testThemeFontsAreTheOnesAskedFor() {
        XCTAssertEqual(Theme.named("nord").bodyFont.familyName, "Avenir Next")
        XCTAssertEqual(Theme.named("solarized").bodyFont.familyName, "Charter")
    }

    func testTextIsReadableInEveryTheme() {
        for theme in Theme.all {
            XCTAssertGreaterThanOrEqual(contrast(theme.text, theme.background), 4.5, theme.name)
            XCTAssertGreaterThanOrEqual(contrast(theme.soft, theme.background), 4.5, theme.name)
            XCTAssertGreaterThanOrEqual(contrast(theme.accent, theme.background), 4.5, theme.name)
            XCTAssertGreaterThanOrEqual(contrast(theme.text, theme.panel), 4.5, theme.name)
        }
    }

    func testEveryThemeCanBeBoldAndItalic() {
        let manager = NSFontManager.shared
        for theme in Theme.all {
            XCTAssertTrue(manager.traits(of: manager.convert(theme.bodyFont, toHaveTrait: .boldFontMask)).contains(.boldFontMask), theme.name)
        }
    }

    func testEveryColorIsReadable() {
        for theme in Theme.all {
            let p = theme.palette
            for color in [p.strong, p.emphasis, p.link, p.check] {
                XCTAssertGreaterThanOrEqual(contrast(color, theme.background), 4.5, theme.name)
            }
            for color in [p.heading1, p.heading2, p.heading3] {
                XCTAssertGreaterThanOrEqual(contrast(color, theme.background), 3, theme.name)
            }
            XCTAssertGreaterThanOrEqual(contrast(p.inlineCode, theme.chip), 4.5, theme.name)
            XCTAssertGreaterThanOrEqual(contrast(p.tableHeaderText, p.tableHeader), 4.5, theme.name)
            for color in [p.keyword, p.string, p.number, p.function, p.tag, p.attribute, p.type] {
                XCTAssertGreaterThanOrEqual(contrast(color, theme.panel), 4.5, theme.name)
            }
            XCTAssertGreaterThanOrEqual(contrast(p.comment, theme.panel), 3, theme.name)
        }
    }

    func testEachThemeHasItsOwnColors() {
        XCTAssertEqual(Set(Theme.all.map { $0.palette.heading1 }).count, Theme.all.count)
    }
}
