import ClaudetteCore
import SwiftUI

struct FileListView: View {
    @ObservedObject var model: AppModel
    @State private var renaming: URL?
    @State private var newName = ""

    private var theme: Theme { model.theme }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if !model.openedFiles.isEmpty {
                        title("Opened files")
                        ForEach(model.openedFiles, id: \.self) { url in
                            openedRow(url)
                        }
                    }
                    ForEach(model.sections) { section in
                        header(section)
                        if section.files.isEmpty {
                            Text("No Markdown files")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(nsColor: theme.dim))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                        }
                        ForEach(section.files, id: \.url) { file in
                            row(file)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            HStack {
                Button { model.chooseFolderToConnect() } label: {
                    Label("Connect Folder", systemImage: "plus")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(nsColor: theme.dim))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(10)
        }
        .background(Color(nsColor: theme.sidePanel))
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let renaming { model.rename(renaming, to: newName) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(nsColor: theme.dim))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A file opened from outside the connected folders, with the folder it's in.
    private func openedRow(_ url: URL) -> some View {
        let isCurrent = url == model.currentFile
        return Button { model.openFromAnywhere(url) } label: {
            HStack(spacing: 6) {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .foregroundStyle(Color(nsColor: isCurrent ? theme.text : theme.soft))
                Text(url.deletingLastPathComponent().lastPathComponent)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(Color(nsColor: theme.dim))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isCurrent ? Color(nsColor: theme.selection) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(url.path)
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Remove from List") { model.removeFromOpened(url) }
        }
    }

    private func header(_ section: FolderSection) -> some View {
        Text(section.name)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(nsColor: theme.dim))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .contextMenu {
                Button("Disconnect") { model.disconnect(section.folder) }
            }
            .dropDestination(for: URL.self) { urls, _ in
                model.handleDrop(urls, into: section.folder)
                return true
            }
    }

    private func row(_ file: ListedFile) -> some View {
        let isCurrent = file.url == model.currentFile
        return Button { model.open(file.url) } label: {
            HStack(spacing: 6) {
                if model.unseen.contains(file.url) {
                    Circle()
                        .fill(Color(nsColor: theme.accent))
                        .frame(width: 6, height: 6)
                }
                Text(file.displayName)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .foregroundStyle(Color(nsColor: isCurrent ? theme.text : theme.soft))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isCurrent ? Color(nsColor: theme.selection) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename…") {
                newName = file.displayName
                renaming = file.url
            }
            Button("Move to Trash") { model.trash(file.url) }
        }
    }
}
