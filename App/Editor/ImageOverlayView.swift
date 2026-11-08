import AppKit
import ClaudetteCore

/// Draws a block image's picture over its hidden source line, or a placeholder until it's ready.
final class ImageOverlayView: NSView {
    private(set) var info: ImageInfo
    private(set) var image: NSImage?
    private var theme: Theme
    var onClick: (() -> Void)?

    var isPlaceholder: Bool { image == nil }

    /// The file or address name, shown on the placeholder.
    var label: String {
        let name = (info.source as NSString).lastPathComponent
        return name.isEmpty ? info.source : (name.removingPercentEncoding ?? name)
    }

    init(info: ImageInfo, image: NSImage?, theme: Theme) {
        self.info = info
        self.image = image
        self.theme = theme
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    func update(info: ImageInfo, image: NSImage?, theme: Theme) {
        self.info = info
        self.image = image
        self.theme = theme
        needsDisplay = true
    }

    /// The picture's size, shrunk to fit the column but never enlarged.
    func displaySize(maxWidth: CGFloat) -> NSSize {
        guard let image, image.size.width > 0, image.size.height > 0 else {
            return NSSize(width: min(maxWidth, 280), height: 44)
        }
        let scale = min(1, maxWidth / image.size.width)
        return NSSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
    }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        if let image {
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            NSGraphicsContext.restoreGraphicsState()
            return
        }
        theme.panel.setFill()
        shape.fill()
        let font = NSFont.systemFont(ofSize: 13)
        var x: CGFloat = 12
        if let symbol = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular).applying(.init(paletteColors: [theme.dim]))) {
            symbol.draw(in: NSRect(x: x, y: (bounds.height - symbol.size.height) / 2, width: symbol.size.width, height: symbol.size.height),
                        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            x += symbol.size.width + 8
        }
        let text = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: theme.dim])
        text.draw(at: NSPoint(x: x, y: (bounds.height - text.size().height) / 2))
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
}
