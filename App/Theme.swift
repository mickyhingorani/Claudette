import AppKit
import ClaudetteCore

enum ViewMode: String {
    case formatted, markdown
}

/// What each kind of thing in a document is colored in a theme.
struct Palette: Equatable {
    let heading1: NSColor
    let heading2: NSColor
    let heading3: NSColor
    let strong: NSColor
    let emphasis: NSColor
    let link: NSColor
    let check: NSColor
    let inlineCode: NSColor
    let quoteBar: NSColor
    let tableHeader: NSColor
    let tableHeaderText: NSColor
    let keyword: NSColor
    let string: NSColor
    let number: NSColor
    let comment: NSColor
    let function: NSColor
    let tag: NSColor
    let attribute: NSColor
    let type: NSColor

    func color(for kind: CodeTokenKind) -> NSColor {
        switch kind {
        case .keyword: return keyword
        case .string: return string
        case .number: return number
        case .comment: return comment
        case .function: return function
        case .tag: return tag
        case .attribute: return attribute
        case .type: return type
        }
    }

    func heading(level: Int) -> NSColor {
        switch level {
        case 1: return heading1
        case 2: return heading2
        default: return heading3
        }
    }
}

struct Theme: Equatable {
    let id: String
    let name: String
    let background: NSColor
    let text: NSColor
    let soft: NSColor
    let dim: NSColor
    let accent: NSColor
    let chip: NSColor
    let panel: NSColor
    let line: NSColor
    let bodyFont: NSFont
    let monoFont: NSFont
    let palette: Palette

    fileprivate static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    private static func serif(size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    private static func menlo(size: CGFloat) -> NSFont { named("Menlo", size: size) }

    private static func named(_ name: String, size: CGFloat) -> NSFont {
        NSFont(name: name, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static let ink = Theme(
        id: "ink", name: "Ink",
        background: color(0x121212), text: color(0xF7F4EC), soft: color(0xE4E0D6), dim: color(0x9A968C),
        accent: color(0xFFFFFF), chip: color(0x262626), panel: color(0x222222), line: color(0x3A3A3A),
        bodyFont: serif(size: 17), monoFont: menlo(size: 14),
        palette: Palette(
            heading1: color(0xE8C48A), heading2: color(0xD9B98C), heading3: color(0xC9B79C),
            strong: color(0xF2D9A6), emphasis: color(0xC7B8E0), link: color(0x8FC7FF), check: color(0x9CCB8F), inlineCode: color(0xE6A57E),
            quoteBar: color(0xC9A26B), tableHeader: color(0x332E26), tableHeaderText: color(0xE8C48A),
            keyword: color(0xC7B8E0), string: color(0xA9CF9A), number: color(0xE6A57E), comment: color(0x8A867C),
            function: color(0x8FC7FF), tag: color(0xE8C48A), attribute: color(0xE6A57E), type: color(0xE6C07B)))

    static let slate = Theme(
        id: "slate", name: "Slate",
        background: color(0x1B1F2B), text: color(0xECEEF3), soft: color(0xC8CCD6), dim: color(0x878D9B),
        accent: color(0xF0826F), chip: color(0x272C3A), panel: color(0x151925), line: color(0x343A49),
        bodyFont: .systemFont(ofSize: 16), monoFont: .monospacedSystemFont(ofSize: 14, weight: .regular),
        palette: Palette(
            heading1: color(0xF0826F), heading2: color(0xE8A87C), heading3: color(0xE3B7A0),
            strong: color(0xF6C177), emphasis: color(0xC4A7E7), link: color(0x8CCFE0), check: color(0x9BD1A0), inlineCode: color(0xF0A48F),
            quoteBar: color(0xF0826F), tableHeader: color(0x3B2D33), tableHeaderText: color(0xF0826F),
            keyword: color(0xC4A7E7), string: color(0xA8D8A0), number: color(0xF6C177), comment: color(0x7E8595),
            function: color(0x8CCFE0), tag: color(0xF0826F), attribute: color(0xF6C177), type: color(0xE8A87C)))

    static let nord = Theme(
        id: "nord", name: "Nord",
        background: color(0x2E3440), text: color(0xECEFF4), soft: color(0xD8DEE9), dim: color(0x8F9BB3),
        accent: color(0x88C0D0), chip: color(0x3B4252), panel: color(0x272C36), line: color(0x4C566A),
        bodyFont: named("Avenir Next", size: 16), monoFont: menlo(size: 14),
        palette: Palette(
            heading1: color(0x88C0D0), heading2: color(0x81A1C1), heading3: color(0x8FBCBB),
            strong: color(0xEBCB8B), emphasis: color(0xB691AF), link: color(0x8FBCBB), check: color(0xA3BE8C), inlineCode: color(0xDBA391),
            quoteBar: color(0xB48EAD), tableHeader: color(0x3F5068), tableHeaderText: color(0x99C9D7),
            keyword: color(0xB48EAD), string: color(0xA3BE8C), number: color(0xD08770), comment: color(0x8391A8),
            function: color(0x88C0D0), tag: color(0x81A1C1), attribute: color(0x8FBCBB), type: color(0xEBCB8B)))

    static let solarized = Theme(
        id: "solarized", name: "Solarized",
        background: color(0x002B36), text: color(0xEEE8D5), soft: color(0x93A1A1), dim: color(0x657B83),
        accent: color(0x2AA198), chip: color(0x073642), panel: color(0x00212B), line: color(0x0E4A59),
        bodyFont: named("Charter", size: 17), monoFont: named("Monaco", size: 13),
        palette: Palette(
            heading1: color(0xB58900), heading2: color(0x2AA198), heading3: color(0x4C9FDC),
            strong: color(0xC99A10), emphasis: color(0xE0679F), link: color(0x2AA198), check: color(0x859900), inlineCode: color(0xE38050),
            quoteBar: color(0x268BD2), tableHeader: color(0x0A4B5C), tableHeaderText: color(0xD4AE40),
            keyword: color(0x859900), string: color(0x2AA198), number: color(0xE0679F), comment: color(0x657B83),
            function: color(0x4C9FDC), tag: color(0x4C9FDC), attribute: color(0xC99A10), type: color(0xE0733F)))

    static let terminal = Theme(
        id: "terminal", name: "Terminal",
        background: color(0x050805), text: color(0x4DFF88), soft: color(0x3FE878), dim: color(0x2BA857),
        accent: color(0xD6FFE4), chip: color(0x10210F), panel: color(0x0B140B), line: color(0x1F4A2A),
        bodyFont: menlo(size: 15), monoFont: menlo(size: 14),
        palette: Palette(
            heading1: color(0xD6FFE4), heading2: color(0x9CFFBE), heading3: color(0x7AF0A0),
            strong: color(0xD6FFE4), emphasis: color(0x8FE8B0), link: color(0xD6FFE4), check: color(0x4DFF88), inlineCode: color(0x9CFFBE),
            quoteBar: color(0x2BA857), tableHeader: color(0x14301C), tableHeaderText: color(0x9CFFBE),
            keyword: color(0xD6FFE4), string: color(0x9CFFBE), number: color(0x7AF0A0), comment: color(0x2BA857),
            function: color(0x4DFF88), tag: color(0xD6FFE4), attribute: color(0x7AF0A0), type: color(0x9CFFBE)))

    static let all = [ink, slate, nord, solarized, terminal]

    static func named(_ id: String) -> Theme { all.first { $0.id == id } ?? ink }
}
