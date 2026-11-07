import AppKit
import ClaudetteCore
import SwiftUI

struct FolderSection: Identifiable {
    let folder: URL
    let files: [ListedFile]
    var id: URL { folder }
    var name: String { folder.lastPathComponent }
}

@MainActor
final class AppModel: ObservableObject {
    private enum Key {
        static let folders = "folders"
        static let lastFile = "lastFile"
        static let viewMode = "viewMode"
        static let theme = "theme"
        static let fileListWidth = "fileListWidth"
    }

    private static let autosaveDelay: TimeInterval = 1
    private static let saveFailedNotice = "Couldn't save. Your text is still here."
    private static let readOnlyNotice = "Read-only: this file isn't UTF-8 text"

    /// The model behind the running app, for the app delegate.
    private(set) static weak var current: AppModel?

    @Published private(set) var folders: [URL] = []
    @Published private(set) var sections: [FolderSection] = []
    @Published private(set) var currentFile: URL?
    @Published private(set) var unseen: Set<URL> = []
    @Published private(set) var notice: String?
    @Published var isFileListOpen = false
    static let fileListWidths: ClosedRange<CGFloat> = 180...420
    @Published var fileListWidth: CGFloat = 250 {
        didSet {
            let clamped = min(max(fileListWidth, Self.fileListWidths.lowerBound), Self.fileListWidths.upperBound)
            if clamped != fileListWidth { fileListWidth = clamped }
            defaults.set(Double(fileListWidth), forKey: Key.fileListWidth)
        }
    }
    @Published var viewMode = ViewMode.formatted {
        didSet {
            editor.viewMode = viewMode
            defaults.set(viewMode.rawValue, forKey: Key.viewMode)
        }
    }
    @Published var themeID = Theme.ink.id {
        didSet {
            editor.theme = theme
            defaults.set(themeID, forKey: Key.theme)
        }
    }

    var theme: Theme { Theme.named(themeID) }

    let scrollView: NSScrollView
    let editor: EditorTextView

    private let defaults: UserDefaults
    private var document: DocumentFile?
    private var draftFolder: URL?
    private var isDirty = false
    private var knownFiles: Set<URL> = []
    private var autosave: DispatchWorkItem?
    private var watcher: FolderWatcher?

    init(defaults: UserDefaults, starterFolder: URL, watchesFolders: Bool) {
        self.defaults = defaults
        (scrollView, editor) = EditorTextView.makeInScrollView()
        themeID = defaults.string(forKey: Key.theme) ?? Theme.ink.id
        viewMode = ViewMode(rawValue: defaults.string(forKey: Key.viewMode) ?? "") ?? .formatted
        if defaults.object(forKey: Key.fileListWidth) != nil {
            fileListWidth = CGFloat(defaults.double(forKey: Key.fileListWidth))
        }
        editor.theme = theme
        editor.viewMode = viewMode
        editor.onTextChange = { [weak self] _ in self?.textDidChange() }
        editor.onDropURLs = { [weak self] urls in self?.handleDrop(urls, into: nil) }

        if let stored = defaults.stringArray(forKey: Key.folders) {
            folders = stored.map { Self.folderURL($0) }
        } else {
            try? FileManager.default.createDirectory(at: starterFolder, withIntermediateDirectories: true)
            folders = [Self.folderURL(starterFolder.path)]
            persistFolders()
        }
        if watchesFolders {
            watcher = FolderWatcher { [weak self] in
                MainActor.assumeIsolated { self?.refresh() }
            }
            watcher?.watch(folders)
        }
        scan()
        knownFiles = allFiles

        if let last = defaults.string(forKey: Key.lastFile), FileManager.default.fileExists(atPath: last) {
            open(URL(fileURLWithPath: last))
        } else {
            showNextFile()
        }
    }

    /// One reused, emptied store for tests and snapshots, so they never touch real settings.
    static func scratchDefaults() -> UserDefaults {
        let name = "com.mickyhingorani.Claudette.scratch"
        let store = UserDefaults(suiteName: name) ?? .standard
        store.removePersistentDomain(forName: name)
        return store
    }

    static func live() -> AppModel {
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if isTesting {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            return AppModel(defaults: scratchDefaults(), starterFolder: folder, watchesFolders: false)
        }
        let starter = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Claudette", isDirectory: true)
        let model = AppModel(defaults: .standard, starterFolder: starter, watchesFolders: true)
        current = model
        return model
    }

    // MARK: Folders

    private var allFiles: Set<URL> { Set(sections.flatMap { $0.files.map(\.url) }) }

    /// The folder holding the open file, or the first folder.
    var currentFolder: URL? {
        if let currentFile {
            let containing = folders.filter { currentFile.path.hasPrefix(Self.prefix(of: $0)) }
            if let deepest = containing.max(by: { $0.path.count < $1.path.count }) { return deepest }
        }
        return draftFolder ?? folders.first
    }

    private static func folderURL(_ path: String) -> URL { URL(fileURLWithPath: path, isDirectory: true) }

    func connect(_ url: URL) {
        let folder = Self.folderURL(url.path)
        guard !folders.contains(folder) else { return }
        folders.append(folder)
        foldersChanged()
        knownFiles.formUnion(allFiles)
    }

    func disconnect(_ url: URL) {
        let folder = Self.folderURL(url.path)
        flush()
        guard !isDirty else { return }
        folders.removeAll { $0 == folder }
        foldersChanged()
        if let currentFile, !isInConnectedFolder(currentFile) {
            closeDocument()
            showNextFile()
        } else if draftFolder == folder {
            draftFolder = folders.first
        }
    }

    private func foldersChanged() {
        persistFolders()
        watcher?.watch(folders)
        scan()
    }

    private func persistFolders() {
        defaults.set(folders.map(\.path), forKey: Key.folders)
    }

    private static func prefix(of folder: URL) -> String {
        folder.path.hasSuffix("/") ? folder.path : folder.path + "/"
    }

    private func isInConnectedFolder(_ url: URL) -> Bool {
        folders.contains { url.path.hasPrefix(Self.prefix(of: $0)) }
    }

    private func scan() {
        sections = folders.map { FolderSection(folder: $0, files: (try? FolderScanner.scan($0)) ?? []) }
    }

    /// Picks up whatever changed on disk.
    func refresh() {
        checkOpenFile()
        scan()
        let files = allFiles
        var arrivals = files.subtracting(knownFiles)
        if let currentFile { arrivals.remove(currentFile) }
        unseen.formUnion(arrivals)
        unseen.formIntersection(files)
        knownFiles = files
    }

    private func checkOpenFile() {
        guard let document else { return }
        if isDirty {
            saveNow()
            return
        }
        switch document.checkDisk() {
        case .unchanged:
            break
        case .changed:
            reloadFromDisk(document)
        case .missing:
            closeDocument()
            scan()
            showNextFile()
        }
    }

    private func reloadFromDisk(_ document: DocumentFile) {
        document.acceptDisk()
        let selection = editor.selectedRange()
        editor.load(text: document.text)
        applyEditability(of: document)
        let length = (document.text as NSString).length
        editor.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
    }

    // MARK: Opening and creating

    func open(_ file: URL) {
        let url = URL(fileURLWithPath: file.path)
        flush()
        guard !isDirty else { return }
        do {
            let file = try DocumentFile(url: url)
            document = file
            draftFolder = nil
            currentFile = url
            isDirty = false
            editor.load(text: file.text)
            applyEditability(of: file)
            unseen.remove(url)
            defaults.set(url.path, forKey: Key.lastFile)
            editor.window?.makeFirstResponder(editor)
        } catch {
            notice = "Couldn't open \(url.lastPathComponent)"
        }
    }

    private func applyEditability(of file: DocumentFile) {
        editor.isEditable = !file.isReadOnly
        notice = file.isReadOnly ? Self.readOnlyNotice : nil
    }

    func newFile() {
        flush()
        guard !isDirty, let folder = currentFolder else { return }
        closeDocument()
        draftFolder = folder
        editor.window?.makeFirstResponder(editor)
    }

    private func closeDocument() {
        autosave?.cancel()
        document = nil
        currentFile = nil
        draftFolder = folders.first
        isDirty = false
        notice = nil
        editor.load(text: "")
        editor.isEditable = true
        defaults.removeObject(forKey: Key.lastFile)
    }

    /// Opens the newest file in the first folder that has one, or starts empty.
    private func showNextFile() {
        if let next = sections.lazy.compactMap({ $0.files.first }).first {
            open(next.url)
        } else {
            draftFolder = folders.first
        }
    }

    // MARK: Saving

    private func textDidChange() {
        isDirty = true
        autosave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        autosave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autosaveDelay, execute: work)
    }

    /// Saves, and asks before quitting only if some text still couldn't be saved.
    func shouldQuit(confirm: () -> Bool) -> Bool {
        flush()
        return !isDirty || confirm()
    }

    /// Saves everything, including a table cell still being typed in.
    func flush() {
        editor.commitCellEdits()
        saveNow()
    }

    func saveNow() {
        autosave?.cancel()
        guard isDirty else { return }
        let text = editor.textWithCellDrafts
        do {
            if let document {
                try saveExisting(document, text: text)
            } else {
                try saveDraft(text: text)
            }
            if notice == Self.saveFailedNotice { notice = nil }
        } catch DocumentFile.SaveError.readOnly {
            isDirty = false
            notice = Self.readOnlyNotice
        } catch {
            notice = Self.saveFailedNotice
        }
    }

    private func saveExisting(_ document: DocumentFile, text: String) throws {
        if case .changed = document.checkDisk() {
            if text == document.text {
                // The edits were undone, so nothing of Micky's is at stake.
                reloadFromDisk(document)
                isDirty = false
                return
            }
            let copy = try document.saveConflictCopy()
            notice = "Changed elsewhere too: saved the other version as \(copy.lastPathComponent)"
        }
        try document.save(text)
        isDirty = false
    }

    private func saveDraft(text: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // A blank new file has nothing worth keeping.
            isDirty = false
            return
        }
        guard let folder = draftFolder ?? folders.first else { return }
        let url = FileNaming.uniqueURL(for: FileNaming.name(fromFirstLineOf: text), in: folder)
        try Data(text.utf8).write(to: url, options: .atomic)
        document = try DocumentFile(url: url)
        draftFolder = nil
        currentFile = url
        isDirty = false
        knownFiles.insert(url)
        defaults.set(url.path, forKey: Key.lastFile)
        scan()
    }

    // MARK: Bringing files in

    func importFiles(_ urls: [URL], into folder: URL?) {
        guard let target = folder ?? currentFolder else { return }
        var first: URL?
        for source in urls where source.pathExtension.lowercased() == "md" {
            if isInConnectedFolder(source) {
                first = first ?? source
                continue
            }
            let name = source.deletingPathExtension().lastPathComponent
            let destination = FileNaming.uniqueURL(for: name, in: target)
            do {
                try FileManager.default.copyItem(at: source, to: destination)
                knownFiles.insert(destination)
                first = first ?? destination
            } catch {
                notice = "Couldn't import \(source.lastPathComponent)"
            }
        }
        scan()
        if let first { open(first) }
    }

    func handleDrop(_ urls: [URL], into folder: URL?) {
        var files: [URL] = []
        for url in urls {
            var isFolder: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder)
            if isFolder.boolValue {
                connect(url)
            } else {
                files.append(url)
            }
        }
        if !files.isEmpty { importFiles(files, into: folder) }
    }

    func chooseFolderToConnect() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Connect"
        if panel.runModal() == .OK, let url = panel.url { connect(url) }
    }

    func chooseFilesToImport() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.init(filenameExtension: "md")].compactMap { $0 }
        panel.prompt = "Import"
        if panel.runModal() == .OK { importFiles(panel.urls, into: nil) }
    }

    // MARK: Rename and trash

    func rename(_ url: URL, to name: String) {
        flush()
        var clean = name.trimmingCharacters(in: .whitespaces)
        if clean.lowercased().hasSuffix(".md") { clean = String(clean.dropLast(3)) }
        clean = FileNaming.name(fromFirstLineOf: clean)
        guard clean != url.deletingPathExtension().lastPathComponent else { return }
        let destination = FileNaming.uniqueURL(for: clean, in: url.deletingLastPathComponent())
        do {
            try FileManager.default.moveItem(at: url, to: destination)
            knownFiles.remove(url)
            knownFiles.insert(destination)
            if currentFile == url {
                document?.url = destination
                currentFile = destination
                defaults.set(destination.path, forKey: Key.lastFile)
            }
            scan()
        } catch {
            notice = "Couldn't rename \(url.lastPathComponent)"
        }
    }

    func trash(_ url: URL) {
        let isCurrent = currentFile == url
        if isCurrent { autosave?.cancel() }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            knownFiles.remove(url)
            unseen.remove(url)
            scan()
            if isCurrent {
                closeDocument()
                showNextFile()
            }
        } catch {
            notice = "Couldn't move \(url.lastPathComponent) to the Trash"
            if isCurrent, isDirty { textDidChange() }
        }
    }
}
