import Foundation
import ClaudetteCore

/// The open document and every rule that keeps its edits safe: autosave, conflict copies,
/// reloading outside changes, noticing a deleted file, rename and trash. It knows nothing
/// about windows or the editor; it reports what happened and the app shows it.
@MainActor
final class DocumentSession {
    enum SaveOutcome: Equatable {
        case nothingToSave
        case saved
        /// The file changed elsewhere too: the other version was kept beside it.
        case savedWithConflictCopy(URL)
        /// The edits had been undone, so the outside version was taken instead.
        case reloaded(String)
        /// A new file was made from a draft.
        case created(URL)
        case readOnly
        /// Nothing was written and the edits are still pending.
        case failed
    }

    enum DiskOutcome: Equatable {
        case unchanged
        case saved
        case savedWithConflictCopy(URL)
        case reloaded(String)
        case missing
        case readOnly
        case failed
    }

    private(set) var document: DocumentFile?
    /// Where a new file goes when a draft is first saved.
    private(set) var draftFolder: URL?
    private(set) var isDirty = false
    /// Called with the result of each autosave.
    var onAutosave: ((SaveOutcome) -> Void)?

    private let autosaveDelay: TimeInterval
    private let currentText: () -> String
    private var autosave: DispatchWorkItem?

    /// `currentText` is the document as it should be saved, including any unfinished table cell.
    init(autosaveDelay: TimeInterval, currentText: @escaping () -> String) {
        self.autosaveDelay = autosaveDelay
        self.currentText = currentText
    }

    var currentFile: URL? { document?.url }
    var isReadOnly: Bool { document?.isReadOnly ?? false }
    /// True when the file on disk holds exactly what was last read or written.
    var matchesDisk: Bool { document?.checkDisk() == .unchanged }

    // MARK: Opening and closing

    func open(_ url: URL) throws {
        let file = try DocumentFile(url: url)
        cancelAutosave()
        document = file
        draftFolder = nil
        isDirty = false
    }

    /// A blank document that becomes a file in `folder` once it has text.
    func startDraft(in folder: URL?) {
        cancelAutosave()
        document = nil
        draftFolder = folder
        isDirty = false
    }

    /// Changes where an unsaved draft will go. An open file isn't affected.
    func moveDraft(to folder: URL?) {
        if document == nil { draftFolder = folder }
    }

    // MARK: Editing and saving

    func markEdited() {
        isDirty = true
        cancelAutosave()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.onAutosave?(self.saveNow())
        }
        autosave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + autosaveDelay, execute: work)
    }

    private func cancelAutosave() {
        autosave?.cancel()
        autosave = nil
    }

    func saveNow() -> SaveOutcome {
        cancelAutosave()
        guard isDirty else { return .nothingToSave }
        let text = currentText()
        do {
            if let document {
                return try saveExisting(document, text: text)
            }
            return try saveDraft(text: text)
        } catch DocumentFile.SaveError.readOnly {
            isDirty = false
            return .readOnly
        } catch {
            return .failed
        }
    }

    private func saveExisting(_ document: DocumentFile, text: String) throws -> SaveOutcome {
        var copy: URL?
        if case .changed = document.checkDisk() {
            if text == document.text {
                // The edits were undone, so nothing of the writer's is at stake.
                document.acceptDisk()
                isDirty = false
                return .reloaded(document.text)
            }
            copy = try document.saveConflictCopy()
        }
        try document.save(text)
        isDirty = false
        return copy.map { .savedWithConflictCopy($0) } ?? .saved
    }

    private func saveDraft(text: String) throws -> SaveOutcome {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // A blank new file has nothing worth keeping.
            isDirty = false
            return .nothingToSave
        }
        guard let folder = draftFolder else { return .failed }
        let url = FileNaming.uniqueURL(for: FileNaming.name(fromFirstLineOf: text), in: folder)
        try Data(text.utf8).write(to: url, options: .atomic)
        document = try DocumentFile(url: url)
        draftFolder = nil
        isDirty = false
        return .created(url)
    }

    /// After something changed on disk: saves pending edits, or takes in an outside change,
    /// or reports that the file is gone.
    func checkDisk() -> DiskOutcome {
        guard let document else { return .unchanged }
        if isDirty {
            switch saveNow() {
            case .nothingToSave, .saved, .created: return .saved
            case .savedWithConflictCopy(let copy): return .savedWithConflictCopy(copy)
            case .reloaded(let text): return .reloaded(text)
            case .readOnly: return .readOnly
            case .failed: return .failed
            }
        }
        switch document.checkDisk() {
        case .unchanged:
            return .unchanged
        case .changed:
            document.acceptDisk()
            return .reloaded(document.text)
        case .missing:
            return .missing
        }
    }

    // MARK: Rename and trash

    /// Renames a file, following it if it's the open one. Nil when the name is unchanged.
    func rename(_ url: URL, to name: String) throws -> URL? {
        var clean = name.trimmingCharacters(in: .whitespaces)
        if clean.lowercased().hasSuffix(".md") { clean = String(clean.dropLast(3)) }
        clean = FileNaming.name(fromFirstLineOf: clean)
        guard clean != url.deletingPathExtension().lastPathComponent else { return nil }
        let destination = FileNaming.uniqueURL(for: clean, in: url.deletingLastPathComponent())
        try FileManager.default.moveItem(at: url, to: destination)
        if document?.url == url { document?.url = destination }
        return destination
    }

    /// Moves a file to the Trash and returns where it went. Save the open file first.
    func trash(_ url: URL) throws -> URL {
        var trashed: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
        return (trashed as URL?) ?? url
    }
}
