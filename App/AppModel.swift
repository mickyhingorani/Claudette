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
        static let openedFiles = "openedFiles"
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
    /// Files opened from outside the connected folders, newest first, so they're easy to reopen.
    @Published private(set) var openedFiles: [URL] = []
    private static let openedFilesLimit = 10
    @Published private(set) var notice: String?
    @Published var isFileListOpen = false
    /// The Markdown guide panel on the right.
    @Published var isGuideOpen = false
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
    @Published var themeID = Theme.default.id {
        didSet {
            editor.theme = theme
            defaults.set(themeID, forKey: Key.theme)
        }
    }

    var theme: Theme { Theme.named(themeID) }

    let scrollView: NSScrollView
    let editor: EditorTextView

    private let defaults: UserDefaults
    /// The open document and the rules that keep its edits safe.
    private var session: DocumentSession!
    private var isDirty: Bool { session.isDirty }
    private var knownFiles: Set<URL> = []
    private var watcher: FolderWatcher?

    init(defaults: UserDefaults, starterFolder: URL, watchesFolders: Bool) {
        self.defaults = defaults
        (scrollView, editor) = EditorTextView.makeInScrollView()
        session = DocumentSession(autosaveDelay: Self.autosaveDelay) { [editor] in editor.textWithCellDrafts }
        session.onAutosave = { [weak self] outcome in self?.handle(outcome) }
        themeID = defaults.string(forKey: Key.theme) ?? Theme.default.id
        viewMode = ViewMode(rawValue: defaults.string(forKey: Key.viewMode) ?? "") ?? .formatted
        if defaults.object(forKey: Key.fileListWidth) != nil {
            fileListWidth = CGFloat(defaults.double(forKey: Key.fileListWidth))
        }
        editor.theme = theme
        editor.viewMode = viewMode
        editor.onTextChange = { [weak self] _ in self?.textDidChange() }
        editor.onOpenDocument = { [weak self] url in self?.openLinked(url) }
        editor.onRefusedLink = { [weak self] _ in
            self?.notice = "Claudette opens only web, email and Markdown links"
        }
        editor.onDropURLs = { [weak self] urls in self?.handleDrop(urls, into: nil) }

        if let stored = defaults.stringArray(forKey: Key.folders) {
            folders = stored.map { Self.folderURL($0) }
        } else {
            try? FileManager.default.createDirectory(at: starterFolder, withIntermediateDirectories: true)
            folders = [Self.folderURL(starterFolder.path)]
            persistFolders()
        }
        openedFiles = (defaults.stringArray(forKey: Key.openedFiles) ?? [])
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        if watchesFolders {
            watcher = FolderWatcher { [weak self] paths in
                MainActor.assumeIsolated { self?.filesChanged(at: paths) }
            }
            watcher?.watch(watchedFolders)
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

    var allFiles: Set<URL> { Set(sections.flatMap { $0.files.map(\.url) }) }

    /// The folder holding the open file, or the first folder.
    var currentFolder: URL? {
        if let currentFile {
            let containing = folders.filter { currentFile.path.hasPrefix(Self.prefix(of: $0)) }
            if let deepest = containing.max(by: { $0.path.count < $1.path.count }) { return deepest }
        }
        return session.draftFolder ?? folders.first
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
        } else if session.draftFolder == folder {
            session.moveDraft(to: folders.first)
        }
    }

    private func foldersChanged() {
        persistFolders()
        watcher?.watch(watchedFolders)
        scan()
    }

    /// The connected folders, plus the folders of files opened from elsewhere, so a change
    /// made to one of those files outside the app is still noticed.
    var watchedFolders: [URL] {
        var result = folders
        for file in openedFiles {
            let folder = Self.folderURL(file.deletingLastPathComponent().path)
            if !result.contains(folder) { result.append(folder) }
        }
        return result
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

    /// Every folder scanned, in order, so tests can check scans stay rare.
    private(set) var scannedFolders: [URL] = []

    private func scan() {
        scan(folders)
    }

    /// Rescans some folders and keeps the others' lists as they are.
    private func scan(_ chosen: [URL]) {
        let known = Dictionary(sections.map { ($0.folder, $0.files) }, uniquingKeysWith: { first, _ in first })
        sections = folders.map { folder in
            guard chosen.contains(folder) else { return FolderSection(folder: folder, files: known[folder] ?? []) }
            scannedFolders.append(folder)
            return FolderSection(folder: folder, files: (try? FolderScanner.scan(folder)) ?? [])
        }
    }

    /// Picks up whatever changed on disk.
    func refresh() {
        checkOpenFile()
        scan()
        noteArrivals()
        dropMissingOpenedFiles()
    }

    private static let markdownExtensions: Set<String> = ["md", "markdown"]

    /// Handles changes the folder watcher saw. The app's own saves and non-Markdown files
    /// don't rescan anything, and only folders with a change in them are rescanned.
    func filesChanged(at paths: [String]) {
        dropMissingOpenedFiles()
        let openPath = currentFile.map { URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path }
        let ownSave = session.matchesDisk
        checkOpenFile()
        let relevant = paths.filter { path in
            let url = URL(fileURLWithPath: path)
            if ownSave, url.resolvingSymlinksInPath().path == openPath { return false }
            if Self.markdownExtensions.contains(url.pathExtension.lowercased()) { return true }
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            // A folder that appeared or vanished can hold notes; a missing extensionless path may have been one.
            return isDirectory.boolValue || (!exists && url.pathExtension.isEmpty)
        }
        // The watcher reports real paths, which may differ from a folder's linked path (/var and /private/var).
        let resolved = relevant.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        let touched = folders.filter { folder in
            let real = folder.resolvingSymlinksInPath()
            return resolved.contains { $0 == real.path || $0.hasPrefix(Self.prefix(of: real)) }
        }
        guard !touched.isEmpty else { return }
        scan(touched)
        noteArrivals()
    }

    private func noteArrivals() {
        let files = allFiles
        var arrivals = files.subtracting(knownFiles)
        if let currentFile { arrivals.remove(currentFile) }
        unseen.formUnion(arrivals)
        unseen.formIntersection(files)
        knownFiles = files
    }

    private func checkOpenFile() {
        guard session.document != nil else { return }
        if isDirty {
            saveNow()
            return
        }
        switch session.checkDisk() {
        case .reloaded(let text):
            showReloaded(text)
        case .missing:
            closeDocument()
            scan()
            showNextFile()
        default:
            break
        }
    }

    /// Shows the open file's new text from disk, keeping the caret where it was.
    private func showReloaded(_ text: String) {
        let selection = editor.selectedRange()
        editor.documentFolder = session.currentFile?.deletingLastPathComponent()
        editor.load(text: text)
        applyEditability()
        let length = (text as NSString).length
        editor.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
    }

    // MARK: Opening and creating

    func open(_ file: URL) {
        let url = URL(fileURLWithPath: file.path)
        flush()
        guard !isDirty else { return }
        do {
            try session.open(url)
            currentFile = url
            editor.documentFolder = url.deletingLastPathComponent()
            editor.load(text: session.document?.text ?? "")
            applyEditability()
            unseen.remove(url)
            defaults.set(url.path, forKey: Key.lastFile)
            editor.window?.makeFirstResponder(editor)
        } catch {
            notice = "Couldn't open \(url.lastPathComponent)"
        }
    }

    private func applyEditability() {
        editor.isEditable = !session.isReadOnly
        notice = session.isReadOnly ? Self.readOnlyNotice : nil
    }

    // MARK: Files opened from anywhere

    private static let markdownFileExtensions: Set<String> = ["md", "markdown"]

    /// Opens a file where it is. One outside the connected folders joins the opened files
    /// list; its folder isn't connected.
    func openFromAnywhere(_ file: URL) {
        let url = URL(fileURLWithPath: file.path)
        open(url)
        guard currentFile == url, !isInConnectedFolder(url) else { return }
        remember(url)
    }

    /// Markdown files handed over by Finder, through Open With or a double-click.
    func openFromFinder(_ urls: [URL]) {
        let notes = urls.filter { Self.markdownFileExtensions.contains($0.pathExtension.lowercased()) }
        for note in notes.dropFirst().reversed() where !isInConnectedFolder(note) { remember(URL(fileURLWithPath: note.path)) }
        if let first = notes.first { openFromAnywhere(first) }
    }

    func removeFromOpened(_ url: URL) {
        openedFiles.removeAll { $0 == url }
        openedFilesChanged()
    }

    private func remember(_ url: URL) {
        openedFiles.removeAll { $0 == url }
        openedFiles.insert(url, at: 0)
        openedFiles = Array(openedFiles.prefix(Self.openedFilesLimit))
        openedFilesChanged()
    }

    /// A file moved or deleted elsewhere drops off the list.
    private func dropMissingOpenedFiles() {
        let existing = openedFiles.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard existing != openedFiles else { return }
        openedFiles = existing
        openedFilesChanged()
    }

    private func openedFilesChanged() {
        defaults.set(openedFiles.map(\.path), forKey: Key.openedFiles)
        watcher?.watch(watchedFolders)
    }

    func chooseFileToOpen() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.markdownFileExtensions.compactMap { .init(filenameExtension: $0) }
        panel.prompt = "Open"
        if panel.runModal() == .OK, let url = panel.url { openFromAnywhere(url) }
    }

    /// A linked note opens like a file picked from the list, if it exists.
    private func openLinked(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            notice = "Couldn't find \(url.lastPathComponent)"
            return
        }
        open(url)
    }

    func toggleGuide() {
        isGuideOpen.toggle()
    }

    /// Inserts a guide example into the open document and puts the cursor back in it.
    func insert(_ entry: GuideEntry) {
        editor.insertGuideEntry(entry)
        editor.window?.makeFirstResponder(editor)
    }

    func newFile() {
        flush()
        guard !isDirty, let folder = currentFolder else { return }
        closeDocument()
        session.moveDraft(to: folder)
        editor.window?.makeFirstResponder(editor)
    }

    private func closeDocument() {
        session.startDraft(in: folders.first)
        currentFile = nil
        notice = nil
        editor.documentFolder = session.draftFolder
        editor.load(text: "")
        editor.isEditable = true
        defaults.removeObject(forKey: Key.lastFile)
    }

    /// Opens the newest file in the first folder that has one, or starts empty.
    private func showNextFile() {
        if let next = sections.lazy.compactMap({ $0.files.first }).first {
            open(next.url)
        } else {
            session.moveDraft(to: folders.first)
        }
    }

    // MARK: Saving

    private func textDidChange() {
        session.markEdited()
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
        handle(session.saveNow())
    }

    /// Shows what a save did.
    private func handle(_ outcome: DocumentSession.SaveOutcome) {
        switch outcome {
        case .nothingToSave, .saved:
            clearSaveFailure()
        case .savedWithConflictCopy(let copy):
            notice = "Changed elsewhere too: saved the other version as \(copy.lastPathComponent)"
        case .reloaded(let text):
            showReloaded(text)
            clearSaveFailure()
        case .created(let url):
            currentFile = url
            knownFiles.insert(url)
            defaults.set(url.path, forKey: Key.lastFile)
            scan()
            clearSaveFailure()
        case .readOnly:
            notice = Self.readOnlyNotice
        case .failed:
            notice = Self.saveFailedNotice
        }
    }

    private func clearSaveFailure() {
        if notice == Self.saveFailedNotice { notice = nil }
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
                // A link would be copied as a link, and edits would then change the original.
                try FileManager.default.copyItem(at: source.resolvingSymlinksInPath(), to: destination)
                knownFiles.insert(destination)
                first = first ?? destination
            } catch {
                notice = "Couldn't import \(source.lastPathComponent)"
            }
        }
        scan()
        if let first { open(first) }
    }

    /// A folder dropped anywhere is connected. Files dropped on the window open where they
    /// are; files dropped on a folder's section in the list are copied into that folder.
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
        guard !files.isEmpty else { return }
        if folder != nil {
            importFiles(files, into: folder)
        } else {
            openFromFinder(files)
        }
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
        do {
            guard let destination = try session.rename(url, to: name) else { return }
            knownFiles.remove(url)
            knownFiles.insert(destination)
            if currentFile == url {
                currentFile = destination
                defaults.set(destination.path, forKey: Key.lastFile)
            }
            scan()
        } catch {
            notice = "Couldn't rename \(url.lastPathComponent)"
        }
    }

    /// Moves a file to the Trash, saving the open file's last edits first. Returns where it went.
    @discardableResult
    func trash(_ url: URL) -> URL? {
        let isCurrent = currentFile == url
        if isCurrent { flush() }
        do {
            let trashed = try session.trash(url)
            knownFiles.remove(url)
            unseen.remove(url)
            scan()
            if isCurrent {
                closeDocument()
                showNextFile()
            }
            return trashed
        } catch {
            notice = "Couldn't move \(url.lastPathComponent) to the Trash"
            if isCurrent, isDirty { textDidChange() }
            return nil
        }
    }
}
