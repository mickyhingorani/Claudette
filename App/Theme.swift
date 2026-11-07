import AppKit

enum ViewMode: String {
    case formatted, markdown
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
    let keepsHeadingMarks: Bool

    private static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    private static func serif(size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    private static func menlo(size: CGFloat) -> NSFont {
        NSFont(name: "Menlo", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static let ink = Theme(
        id: "ink", name: "Ink",
        background: color(0x121212), text: color(0xF7F4EC), soft: color(0xE4E0D6), dim: color(0x9A968C),
        accent: color(0xFFFFFF), chip: color(0x262626), panel: color(0x222222), line: color(0x3A3A3A),
        bodyFont: serif(size: 17), monoFont: menlo(size: 14), keepsHeadingMarks: false)

    static let terminal = Theme(
        id: "terminal", name: "Terminal",
        background: color(0x050805), text: color(0x4DFF88), soft: color(0x3FE878), dim: color(0x2BA857),
        accent: color(0xD6FFE4), chip: color(0x10210F), panel: color(0x0B140B), line: color(0x1F4A2A),
        bodyFont: menlo(size: 15), monoFont: menlo(size: 14), keepsHeadingMarks: true)

    static let all = [ink, terminal]

    static func named(_ id: String) -> Theme { all.first { $0.id == id } ?? ink }
}
