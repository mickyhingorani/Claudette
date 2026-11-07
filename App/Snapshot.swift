import AppKit

/// Renders a file to a PNG and quits, so the app can be reviewed without a screen.
enum Snapshot {
    static func runIfRequested() {
        let defaults = UserDefaults.standard
        guard let file = defaults.string(forKey: "snapshotFile"),
              let out = defaults.string(forKey: "snapshotOut"),
              let text = try? String(contentsOfFile: file, encoding: .utf8) else { return }
        _ = NSApplication.shared
        let (scroll, editor) = EditorTextView.makeInScrollView()
        editor.theme = Theme.named(defaults.string(forKey: "snapshotTheme") ?? "ink")
        editor.viewMode = ViewMode(rawValue: defaults.string(forKey: "snapshotMode") ?? "") ?? .formatted
        let size = NSSize(width: 900, height: CGFloat(defaults.object(forKey: "snapshotHeight") == nil ? 900 : defaults.integer(forKey: "snapshotHeight")))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = scroll
        scroll.frame = NSRect(origin: .zero, size: size)
        editor.load(text: text)
        let cursor = defaults.object(forKey: "snapshotCursor") == nil ? (text as NSString).length : defaults.integer(forKey: "snapshotCursor")
        editor.setSelectedRange(NSRange(location: cursor, length: 0))
        window.layoutIfNeeded()
        write(scroll, to: out)
        exit(0)
    }

    static func write(_ view: NSView, to path: String) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
