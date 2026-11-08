import AppKit
import XCTest
@testable import Claudette

/// docs/themes.md lists every theme's fonts and colors. These tests keep it in step with the code.
final class ThemeDocsTests: XCTestCase {
    private func docs() throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/themes.md")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// One theme's part of the page: from its heading to the next theme's.
    private func section(for theme: Theme, in page: String) -> String? {
        guard let start = page.range(of: "\n## \(theme.name)\n") else { return nil }
        let rest = page[start.upperBound...]
        let end = rest.range(of: "\n## ")?.lowerBound ?? rest.endIndex
        return String(rest[..<end])
    }

    private func hex(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB)!
        return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }

    /// Every color a theme sets, found by looking through its properties.
    private func colors(of theme: Theme) -> [(String, NSColor)] {
        let page = Mirror(reflecting: theme).children.compactMap { child -> (String, NSColor)? in
            guard let label = child.label else { return nil }
            if let color = child.value as? NSColor { return (label, color) }
            if let color = child.value as? NSColor?, let color { return (label, color) }
            return nil
        }
        let palette = Mirror(reflecting: theme.palette).children.compactMap { child -> (String, NSColor)? in
            guard let label = child.label else { return nil }
            if let color = child.value as? NSColor { return (label, color) }
            if let color = child.value as? NSColor?, let color { return (label, color) }
            return nil
        }
        return page + palette
    }

    func testEveryThemeHasASection() throws {
        let page = try docs()
        for theme in Theme.all {
            XCTAssertNotNil(section(for: theme, in: page), theme.name)
        }
    }

    func testEveryThemeColorIsListed() throws {
        let page = try docs()
        for theme in Theme.all {
            let text = section(for: theme, in: page) ?? ""
            for (name, color) in colors(of: theme) {
                XCTAssertTrue(text.contains("`\(hex(color))`"), "\(theme.name) \(name) \(hex(color))")
            }
        }
    }

    func testEveryThemeFontIsListed() throws {
        let page = try docs()
        for theme in Theme.all {
            let text = section(for: theme, in: page) ?? ""
            for font in [theme.titleFont, theme.headingFont, theme.bodyFont, theme.monoFont] {
                XCTAssertTrue(text.contains(font.familyName ?? "?"), "\(theme.name) \(font.familyName ?? "?")")
            }
        }
    }
}
