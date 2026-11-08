import AppKit

/// A code block's language name and a Copy button, in the block's top-right corner.
final class CodeLabelView: NSView {
    private(set) var language: String
    private var theme: Theme
    /// Set while the button says "Copied", just after a copy.
    private(set) var showsCopied = false
    private var resetCopied: DispatchWorkItem?
    var onCopy: (() -> Void)?

    private static let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
    private static let buttonFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    private static let gap: CGFloat = 10
    private static let buttonPadding = NSSize(width: 7, height: 2)

    init(language: String, theme: Theme) {
        self.language = language
        self.theme = theme
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    func update(language: String, theme: Theme) {
        guard language != self.language || theme != self.theme else { return }
        self.language = language
        self.theme = theme
        needsDisplay = true
    }

    private var labelText: NSAttributedString {
        NSAttributedString(string: language.uppercased(), attributes: [.font: Self.font, .foregroundColor: theme.dim, .kern: 0.6])
    }

    private var buttonText: NSAttributedString {
        NSAttributedString(string: showsCopied ? "Copied" : "Copy", attributes: [.font: Self.buttonFont, .foregroundColor: theme.soft])
    }

    /// Wide enough for "Copied", so the button doesn't change size when it's clicked.
    private var buttonSize: NSSize {
        let widest = NSAttributedString(string: "Copied", attributes: [.font: Self.buttonFont]).size()
        return NSSize(width: ceil(widest.width) + Self.buttonPadding.width * 2, height: ceil(widest.height) + Self.buttonPadding.height * 2)
    }

    /// The size the label and button need together.
    var contentSize: NSSize {
        let label = labelText.size()
        let button = buttonSize
        return NSSize(width: ceil(label.width) + Self.gap + button.width, height: max(ceil(label.height), button.height))
    }

    private var buttonRect: NSRect {
        let size = buttonSize
        return NSRect(x: bounds.maxX - size.width, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let label = labelText
        let labelSize = label.size()
        label.draw(at: NSPoint(x: buttonRect.minX - Self.gap - labelSize.width, y: (bounds.height - labelSize.height) / 2))
        let shape = NSBezierPath(roundedRect: buttonRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        theme.line.setStroke()
        shape.lineWidth = 1
        shape.stroke()
        let text = buttonText
        let textSize = text.size()
        text.draw(at: NSPoint(x: buttonRect.midX - textSize.width / 2, y: buttonRect.midY - textSize.height / 2))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Only the button takes clicks; the label lets them through to the text.
        buttonRect.contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        onCopy?()
    }

    override func resetCursorRects() {
        addCursorRect(buttonRect, cursor: .pointingHand)
    }

    /// Shows "Copied" for a moment.
    func confirmCopy() {
        showsCopied = true
        needsDisplay = true
        resetCopied?.cancel()
        let reset = DispatchWorkItem { [weak self] in
            self?.showsCopied = false
            self?.needsDisplay = true
        }
        resetCopied = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: reset)
    }
}
