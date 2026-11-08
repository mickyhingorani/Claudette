import SwiftUI

struct EditorHost: NSViewRepresentable {
    let scrollView: NSScrollView
    func makeNSView(context: Context) -> NSScrollView { scrollView }
    func updateNSView(_ view: NSScrollView, context: Context) {}
}

struct RootView: View {
    @ObservedObject var model: AppModel
    @State private var widthAtDragStart: CGFloat?

    private var theme: Theme { model.theme }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            HStack(spacing: 0) {
                if model.isFileListOpen {
                    FileListView(model: model)
                        .frame(width: model.fileListWidth)
                        .overlay(alignment: .trailing) { resizeHandle }
                        .transition(.move(edge: .leading))
                }
                content
                if model.isGuideOpen {
                    GuideView(model: model)
                        .transition(.move(edge: .trailing))
                }
            }
            .clipped()
        }
        .background(Color(nsColor: theme.background))
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.22), value: model.isFileListOpen)
        .animation(.easeInOut(duration: 0.22), value: model.isGuideOpen)
        .frame(minWidth: 480, minHeight: 360)
        .dropDestination(for: URL.self) { urls, _ in
            model.handleDrop(urls, into: nil)
            return true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            model.flush()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            model.flush()
        }
    }

    /// A thin strip on the tray's edge that drags to resize it.
    private var resizeHandle: some View {
        Color.clear
            .frame(width: 7)
            .contentShape(Rectangle())
            .onHover { isOver in
                if isOver { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = widthAtDragStart ?? model.fileListWidth
                        widthAtDragStart = start
                        model.fileListWidth = start + drag.translation.width
                    }
                    .onEnded { _ in widthAtDragStart = nil }
            )
    }

    @ViewBuilder private var content: some View {
        if model.folders.isEmpty {
            VStack(spacing: 12) {
                Text("Connect a folder to get started")
                    .foregroundStyle(Color(nsColor: theme.soft))
                Button("Connect Folder…") { model.chooseFolderToConnect() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EditorHost(scrollView: model.scrollView)
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            barButton(symbol: "sidebar.left", label: "Files", isOn: model.isFileListOpen) {
                model.isFileListOpen.toggle()
            }
            if let notice = model.notice {
                Text(notice)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(Color(nsColor: theme.dim))
                    .frame(maxWidth: .infinity)
            } else {
                Spacer()
            }
            HStack(spacing: 2) {
                barButton(symbol: "eye", label: "Formatted", isOn: model.viewMode == .formatted) {
                    model.viewMode = .formatted
                }
                barButton(text: "#", label: "Markdown", isOn: model.viewMode == .markdown) {
                    model.viewMode = .markdown
                }
            }
            .padding(2)
            .background(Color(nsColor: theme.chip), in: RoundedRectangle(cornerRadius: 8))
            barButton(symbol: "book.closed", label: "Markdown Guide (⌘/)", isOn: model.isGuideOpen) {
                model.toggleGuide()
            }
        }
        .padding(.leading, 84)
        .padding(.trailing, 12)
        .frame(height: 38)
    }

    private func barButton(symbol: String? = nil, text: String? = nil, label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                } else if let text {
                    Text(text).font(.system(size: 13, weight: .semibold, design: .monospaced))
                }
            }
            .frame(width: 28, height: 22)
            .foregroundStyle(Color(nsColor: isOn ? theme.text : theme.dim))
            .background(isOn ? Color(nsColor: theme.line) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}
