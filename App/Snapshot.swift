import AppKit
import SwiftUI

/// Renders a file to a PNG and quits, so the app can be reviewed without a screen.
enum Snapshot {
    static func runIfRequested() {
        let defaults = UserDefaults.standard
        if let folder = defaults.string(forKey: "snapshotFolder"), let out = defaults.string(forKey: "snapshotOut") {
            guard FileManager.default.fileExists(atPath: folder) else { exit(1) }
            MainActor.assumeIsolated { renderApp(folder: folder, out: out, defaults: defaults) }
            exit(0)
        }
        guard let file = defaults.string(forKey: "snapshotFile"),
              let out = defaults.string(forKey: "snapshotOut") else { return }
        // A snapshot request must never fall through to a normal launch.
        guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { exit(1) }
        _ = NSApplication.shared
        let (scroll, editor) = EditorTextView.makeInScrollView()
        editor.theme = Theme.named(defaults.string(forKey: "snapshotTheme") ?? Theme.default.id)
        editor.viewMode = ViewMode(rawValue: defaults.string(forKey: "snapshotMode") ?? "") ?? .formatted
        let size = NSSize(width: 900, height: CGFloat(defaults.object(forKey: "snapshotHeight") == nil ? 900 : defaults.integer(forKey: "snapshotHeight")))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = scroll
        scroll.frame = NSRect(origin: .zero, size: size)
        editor.load(text: text)
        let cursor = defaults.object(forKey: "snapshotCursor") == nil ? (text as NSString).length : defaults.integer(forKey: "snapshotCursor")
        editor.setSelectedRange(NSRange(location: cursor, length: 0))
        window.layoutIfNeeded()
        editor.positionTableOverlays()
        write(scroll, to: out)
        exit(0)
    }

    /// Renders the whole window, top bar and file list included.
    @MainActor private static func renderApp(folder: String, out: String, defaults: UserDefaults) {
        _ = NSApplication.shared
        let store = AppModel.scratchDefaults()
        store.set([folder], forKey: "folders")
        store.set(defaults.string(forKey: "snapshotTheme") ?? Theme.default.id, forKey: "theme")
        store.set(defaults.string(forKey: "snapshotMode") ?? "formatted", forKey: "viewMode")
        let model = AppModel(defaults: store, starterFolder: URL(fileURLWithPath: folder), watchesFolders: false)
        model.isFileListOpen = defaults.bool(forKey: "snapshotList")
        let size = NSSize(width: 980, height: 760)
        let host = NSHostingView(rootView: RootView(model: model))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        window.orderBack(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.6))
        model.editor.positionTableOverlays()
        write(host, to: out)
    }

    static func write(_ view: NSView, to path: String) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
