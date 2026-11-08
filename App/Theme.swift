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
    /// A Note callout's color, when a theme wants one other than its link color.
    var note: NSColor? = nil

    /// Each callout kind borrows a color the theme already uses for meaning.
    func callout(_ kind: CalloutKind) -> NSColor {
        switch kind {
        case .note: return note ?? link
        case .tip: return check
        case .important: return emphasis
        case .warning: return strong
        case .caution: return inlineCode
        }
    }

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
    let headingFont: NSFont
    let bodyFont: NSFont
    let monoFont: NSFont
    let palette: Palette
    /// A font for big (`#`) titles, drawn at regular weight, when a theme pairs one in.
    var titleFace: NSFont? = nil
    /// A thin outline around inline code and code blocks, for themes that draw one.
    var outline: NSColor? = nil

    /// Big (`#`) titles: the title face if the theme has one, else the heading font.
    var titleFont: NSFont { titleFace ?? headingFont }

    fileprivate static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// Fonts that ship inside the app, loaded the first time a theme needs one.
    private static let bundledFontsLoaded: Void = {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }()

    private static func font(_ family: String, size: CGFloat) -> NSFont {
        _ = bundledFontsLoaded
        let descriptor = NSFontDescriptor(fontAttributes: [.family: family])
        guard let font = NSFont(descriptor: descriptor, size: size), font.familyName == family else {
            return .systemFont(ofSize: size)
        }
        return font.isFixedPitch ? showingOperatorsAsTyped(font) : font
    }

    /// Coding fonts draw `=>` and `!=` as arrows and symbols. Claudette shows the text as typed.
    static func showingOperatorsAsTyped(_ font: NSFont) -> NSFont {
        let off: [NSFontDescriptor.FeatureKey: Int] = [.typeIdentifier: kContextualAlternatesType, .selectorIdentifier: kContextualAlternatesOffSelector]
        let descriptor = font.fontDescriptor.addingAttributes([.featureSettings: [off]])
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }

    static let slate = Theme(
        id: "slate", name: "Slate",
        background: color(0x1B1F2B), text: color(0xECEEF3), soft: color(0xC8CCD6), dim: color(0x878D9B),
        accent: color(0xF0826F), chip: color(0x272C3A), panel: color(0x151925), line: color(0x343A49),
        headingFont: font("Atkinson Hyperlegible Next", size: 16), bodyFont: font("Atkinson Hyperlegible Next", size: 16),
        monoFont: font("JetBrains Mono", size: 14),
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
        headingFont: font("Geist", size: 16), bodyFont: font("Geist", size: 16), monoFont: font("Geist Mono", size: 14),
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
        headingFont: font("IBM Plex Sans", size: 16), bodyFont: font("IBM Plex Sans", size: 16), monoFont: font("IBM Plex Mono", size: 14),
        palette: Palette(
            heading1: color(0xB58900), heading2: color(0x2AA198), heading3: color(0x4C9FDC),
            strong: color(0xC99A10), emphasis: color(0xE0679F), link: color(0x2AA198), check: color(0x859900), inlineCode: color(0xE38050),
            quoteBar: color(0x268BD2), tableHeader: color(0x0A4B5C), tableHeaderText: color(0xD4AE40),
            keyword: color(0x859900), string: color(0x2AA198), number: color(0xE0679F), comment: color(0x657B83),
            function: color(0x4C9FDC), tag: color(0x4C9FDC), attribute: color(0xC99A10), type: color(0xE0733F)))

    /// Deep teal with gold and pink, after a developer docs site Micky liked.
    static let harbor = Theme(
        id: "harbor", name: "Harbor",
        background: color(0x002635), text: color(0xFFFEFF), soft: color(0xB9C4CB), dim: color(0x8093A0),
        accent: color(0xECC271), chip: color(0x0A1E27), panel: color(0x0B2F3B), line: color(0x1E414B),
        headingFont: font("Hanken Grotesk", size: 16), bodyFont: font("Hanken Grotesk", size: 16),
        monoFont: font("JetBrains Mono", size: 14),
        palette: Palette(
            heading1: color(0xFFFEFF), heading2: color(0xF2C878), heading3: color(0xFF8FDA),
            strong: color(0xFFFEFF), emphasis: color(0xFF8FDA), link: color(0xECC271), check: color(0xFF5ECA), inlineCode: color(0xECC271),
            quoteBar: color(0xFF5ECA), tableHeader: color(0x0F3946), tableHeaderText: color(0xFFFEFF),
            keyword: color(0xFF8FDA), string: color(0xC3E88D), number: color(0xF78C6C), comment: color(0x7D96A3),
            function: color(0x82AAFF), tag: color(0x89DDFF), attribute: color(0xC792EA), type: color(0xECC271),
            note: color(0x6CB6F0)),
        titleFace: font("Newsreader", size: 16), outline: color(0x24505C))

    static let terminal = Theme(
        id: "terminal", name: "Terminal",
        background: color(0x050805), text: color(0x4DFF88), soft: color(0x3FE878), dim: color(0x2BA857),
        accent: color(0xD6FFE4), chip: color(0x10210F), panel: color(0x0B140B), line: color(0x1F4A2A),
        headingFont: font("JetBrains Mono", size: 15), bodyFont: font("JetBrains Mono", size: 15), monoFont: font("JetBrains Mono", size: 14),
        palette: Palette(
            heading1: color(0xD6FFE4), heading2: color(0x9CFFBE), heading3: color(0x7AF0A0),
            strong: color(0xD6FFE4), emphasis: color(0x8FE8B0), link: color(0xD6FFE4), check: color(0x4DFF88), inlineCode: color(0x9CFFBE),
            quoteBar: color(0x2BA857), tableHeader: color(0x14301C), tableHeaderText: color(0x9CFFBE),
            keyword: color(0xD6FFE4), string: color(0x9CFFBE), number: color(0x7AF0A0), comment: color(0x2BA857),
            function: color(0x4DFF88), tag: color(0xD6FFE4), attribute: color(0x7AF0A0), type: color(0x9CFFBE)))

    static let all = [slate, nord, solarized, harbor, terminal]
    static let `default` = slate

    static func named(_ id: String) -> Theme { all.first { $0.id == id } ?? .default }
}
