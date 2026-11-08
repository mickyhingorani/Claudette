import AppKit
import ClaudetteCore
import SwiftUI

/// A Markdown cheat sheet that slides in from the right. Clicking an example inserts it.
struct GuideView: View {
    @ObservedObject var model: AppModel
    private var theme: Theme { model.theme }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Markdown guide")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(nsColor: theme.text))
                Text("Click an example to insert it.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: theme.dim))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(MarkdownGuide.sections) { section in
                        sectionTitle(section.title)
                        ForEach(section.entries) { entry in
                            GuideRow(entry: entry, theme: theme) { model.insert(entry) }
                        }
                    }
                    sectionTitle("Typing")
                    tip("Return", "Starts a new paragraph.")
                    tip("⇧ Return", "Breaks the line inside a paragraph.")
                    tip("⌘E", "Shows the Markdown itself, or the formatted view.")
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
        }
        .frame(width: 320)
        .background(Color(nsColor: theme.sidePanel))
        .overlay(alignment: .leading) {
            Rectangle().fill(Color(nsColor: theme.line)).frame(width: 1)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Color(nsColor: theme.dim))
            .padding(.top, 10)
            .padding(.leading, 2)
    }

    private func tip(_ keys: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(keys)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(nsColor: theme.accent))
                .frame(width: 70, alignment: .leading)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: theme.soft))
        }
        .padding(.horizontal, 10)
    }
}

/// One example: its name and shortcut, what you type, and how it looks.
private struct GuideRow: View {
    let entry: GuideEntry
    let theme: Theme
    let insert: () -> Void
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(nsColor: theme.soft))
                Spacer()
                if let shortcut = entry.shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(nsColor: theme.dim))
                }
            }
            Text(entry.markdown)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color(nsColor: theme.accent))
                .fixedSize(horizontal: false, vertical: true)
            GuidePreview(markdown: entry.markdown, theme: theme)
        }
        .padding(10)
        .background(Color(nsColor: isHovering ? theme.line : theme.chip), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture(perform: insert)
        .onHover { isHovering = $0 }
        .help("Insert \(entry.title.lowercased())")
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Insert \(entry.title)")
    }
}

/// The example drawn by Claudette's own formatted view, so it looks the way the document will.
private struct GuidePreview: NSViewRepresentable {
    let markdown: String
    let theme: Theme

    final class Container: NSView {
        let editor: EditorTextView
        init(editor: EditorTextView) {
            self.editor = editor
            super.init(frame: .zero)
            addSubview(editor)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
        override var isFlipped: Bool { true }
        /// Clicks go to the row, which inserts the example.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func layout() {
            super.layout()
            editor.frame = bounds
            editor.positionOverlays()
        }
    }

    func makeNSView(context: Context) -> Container {
        let (_, editor) = EditorTextView.makeInScrollView()
        editor.sideInset = 0
        editor.isEditable = false
        editor.isSelectable = false
        editor.theme = theme
        editor.load(text: markdown)
        return Container(editor: editor)
    }

    func updateNSView(_ view: Container, context: Context) {
        if view.editor.theme != theme { view.editor.theme = theme }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: Container, context: Context) -> CGSize? {
        let width = proposal.width ?? 280
        let editor = view.editor
        editor.setFrameSize(NSSize(width: width, height: editor.frame.height))
        guard let layout = editor.layoutManager, let container = editor.textContainer else { return nil }
        layout.ensureLayout(for: container)
        let height = layout.usedRect(for: container).height
        return CGSize(width: width, height: ceil(height) + 4)
    }
}
