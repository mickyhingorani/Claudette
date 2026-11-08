import XCTest
import ClaudetteCore
@testable import Claudette

@MainActor
final class AppModelTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "com.mickyhingorani.Claudette.tests"
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    private var starter: URL { root.appendingPathComponent("Claudette", isDirectory: true) }

    private func makeModel() -> AppModel {
        AppModel(defaults: defaults, starterFolder: starter, watchesFolders: false)
    }

    private func folder(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func write(_ text: String, _ name: String, in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }
    private func type(_ text: String, into model: AppModel) {
        model.editor.setSelectedRange(NSRange(location: model.editor.string.utf16.count, length: 0))
        model.editor.applyEdit(model.editor.selectedRange(), text)
    }

    func testFirstLaunchCreatesStarterFolder() {
        let model = makeModel()
        XCTAssertTrue(FileManager.default.fileExists(atPath: starter.path))
        XCTAssertEqual(model.folders, [starter])
    }

    func testDisconnectedStarterStaysDisconnected() {
        let model = makeModel()
        model.disconnect(starter)
        XCTAssertEqual(makeModel().folders, [])
    }

    func testConnectListsFilesInPlace() throws {
        let project = try folder("Project")
        let file = try write("# Hi", "a.md", in: project)
        let model = makeModel()
        model.connect(project)
        XCTAssertEqual(model.sections.last?.files.map(\.url.lastPathComponent), ["a.md"])
        XCTAssertEqual(try read(file), "# Hi")
    }

    func testConnectSameFolderTwiceAddsOnce() throws {
        let project = try folder("Project")
        let model = makeModel()
        model.connect(project)
        model.connect(project)
        XCTAssertEqual(model.folders.filter { $0 == project }.count, 1)
    }

    func testDisconnectLeavesFiles() throws {
        let project = try folder("Project")
        let file = try write("x", "a.md", in: project)
        let model = makeModel()
        model.connect(project)
        model.open(file)
        model.disconnect(project)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertNil(model.currentFile)
    }

    func testOpenLoadsEditorWithoutChangingFile() throws {
        let project = try folder("Project")
        let file = try write("a\r\nb", "a.md", in: project)
        let model = makeModel()
        model.connect(project)
        model.open(file)
        model.saveNow()
        XCTAssertEqual(model.editor.string, "a\r\nb")
        XCTAssertEqual(try Data(contentsOf: file), Data("a\r\nb".utf8))
    }

    func testEditSavesToFile() throws {
        let project = try folder("Project")
        let file = try write("a", "a.md", in: project)
        let model = makeModel()
        model.connect(project)
        model.open(file)
        type("b", into: model)
        model.saveNow()
        XCTAssertEqual(try read(file), "ab")
    }

    func testSwitchingFilesSavesFirst() throws {
        let project = try folder("Project")
        let one = try write("a", "1.md", in: project)
        let two = try write("z", "2.md", in: project)
        let model = makeModel()
        model.connect(project)
        model.open(one)
        type("b", into: model)
        model.open(two)
        XCTAssertEqual(try read(one), "ab")
        XCTAssertEqual(model.editor.string, "z")
    }

    func testNewFileNamedOnceOnFirstSave() throws {
        let model = makeModel()
        model.newFile()
        type("# Launch plan\n", into: model)
        model.saveNow()
        let saved = starter.appendingPathComponent("Launch plan.md")
        XCTAssertEqual(model.currentFile, saved)
        model.editor.applyEdit(NSRange(location: 2, length: 6), "Other")
        model.saveNow()
        XCTAssertEqual(model.currentFile, saved)
        XCTAssertTrue(try read(saved).contains("Other"))
    }

    func testEmptyNewFileIsNeverSaved() throws {
        let model = makeModel()
        model.newFile()
        model.saveNow()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: starter.path), [])
    }

    func testNewFileGoesToCurrentFolder() throws {
        let project = try folder("Project")
        let file = try write("x", "a.md", in: project)
        let model = makeModel()
        model.connect(project)
        model.open(file)
        model.newFile()
        type("Note", into: model)
        model.saveNow()
        XCTAssertEqual(model.currentFile, project.appendingPathComponent("Note.md"))
    }

    func testImportGoesToCurrentFolder() throws {
        let project = try folder("Project")
        let outside = try folder("Outside")
        let source = try write("hello", "Doc.md", in: outside)
        let file = try write("x", "a.md", in: project)
        let model = makeModel()
        model.connect(project)
        model.open(file)
        model.importFiles([source], into: nil)
        let copy = project.appendingPathComponent("Doc.md")
        XCTAssertEqual(try read(copy), "hello")
        XCTAssertEqual(model.currentFile, copy)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testImportingALinkCopiesTheFileItPointsTo() throws {
        let project = try folder("Project")
        let original = try write("hello", "Doc.md", in: try folder("Outside"))
        let links = try folder("Links")
        let link = links.appendingPathComponent("Linked.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        let model = makeModel()
        model.connect(project)
        model.importFiles([link], into: project)
        let copy = project.appendingPathComponent("Linked.md")
        let type = try FileManager.default.attributesOfItem(atPath: copy.path)[.type] as? FileAttributeType
        XCTAssertEqual(type, .typeRegular)
        model.editor.insertText(" there", replacementRange: NSRange(location: 5, length: 0))
        model.saveNow()
        XCTAssertEqual(try read(original), "hello")
        XCTAssertEqual(try read(copy), "hello there")
    }

    func testImportIntoChosenFolder() throws {
        let project = try folder("Project")
        let source = try write("hello", "Doc.md", in: try folder("Outside"))
        let model = makeModel()
        model.connect(project)
        model.importFiles([source], into: project)
        XCTAssertEqual(model.currentFile, project.appendingPathComponent("Doc.md"))
    }

    func testImportRepeatedNameGetsNumber() throws {
        let source = try write("new", "Doc.md", in: try folder("Outside"))
        try write("old", "Doc.md", in: starter.deletingLastPathComponent())
        let model = makeModel()
        try write("old", "Doc.md", in: starter)
        model.importFiles([source], into: starter)
        XCTAssertEqual(try read(starter.appendingPathComponent("Doc 2.md")), "new")
        XCTAssertEqual(try read(starter.appendingPathComponent("Doc.md")), "old")
    }

    func testImportOfFileAlreadyConnectedJustOpensIt() throws {
        let project = try folder("Project")
        let file = try write("x", "a.md", in: project)
        let model = makeModel()
        model.connect(project)
        model.importFiles([file], into: starter)
        XCTAssertEqual(model.currentFile, file)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: starter.path), [])
    }

    func testImportSkipsOtherFileTypes() throws {
        let source = try write("x", "a.txt", in: try folder("Outside"))
        let model = makeModel()
        model.importFiles([source], into: starter)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: starter.path), [])
    }

    func testDroppedFolderConnects() throws {
        let project = try folder("Project")
        let model = makeModel()
        model.handleDrop([project], into: nil)
        XCTAssertTrue(model.folders.contains(project))
    }

    func testNewFileFromOutsideIsMarkedUnseen() throws {
        let model = makeModel()
        let file = try write("x", "a.md", in: starter)
        model.refresh()
        XCTAssertTrue(model.unseen.contains(file))
        model.open(file)
        XCTAssertFalse(model.unseen.contains(file))
    }

    func testFilesPresentAtConnectAreNotUnseen() throws {
        let project = try folder("Project")
        try write("x", "a.md", in: project)
        let model = makeModel()
        model.connect(project)
        XCTAssertTrue(model.unseen.isEmpty)
    }

    func testOwnNewFileIsNotUnseen() throws {
        let model = makeModel()
        model.newFile()
        type("Note", into: model)
        model.saveNow()
        model.refresh()
        XCTAssertTrue(model.unseen.isEmpty)
    }

    func testExternalChangeReloadsWhenClean() throws {
        let file = try write("a", "a.md", in: try { try FileManager.default.createDirectory(at: starter, withIntermediateDirectories: true); return starter }())
        let model = makeModel()
        model.open(file)
        try write("z", "a.md", in: starter)
        model.refresh()
        XCTAssertEqual(model.editor.string, "z")
    }

    func testExternalChangeWhileEditingKeepsBoth() throws {
        let file = try write("a", "Name.md", in: try { try FileManager.default.createDirectory(at: starter, withIntermediateDirectories: true); return starter }())
        let model = makeModel()
        model.open(file)
        type("mine", into: model)
        try write("theirs", "Name.md", in: starter)
        model.refresh()
        XCTAssertEqual(model.editor.string, "amine")
        XCTAssertEqual(try read(file), "amine")
        XCTAssertEqual(try read(starter.appendingPathComponent("Name (conflict).md")), "theirs")
    }

    func testFileDeletedOutsideWhileCleanCloses() throws {
        let model = makeModel()
        let file = try write("a", "a.md", in: starter)
        model.refresh()
        model.open(file)
        try FileManager.default.removeItem(at: file)
        model.refresh()
        XCTAssertNil(model.currentFile)
    }

    func testFileDeletedOutsideWhileEditingKeepsText() throws {
        let model = makeModel()
        let file = try write("a", "a.md", in: starter)
        model.refresh()
        model.open(file)
        type("b", into: model)
        try FileManager.default.removeItem(at: file)
        model.refresh()
        XCTAssertEqual(try read(file), "ab")
    }

    func testRenameCurrentFile() throws {
        let model = makeModel()
        let file = try write("a", "a.md", in: starter)
        model.refresh()
        model.open(file)
        type("b", into: model)
        model.rename(file, to: "New name")
        let renamed = starter.appendingPathComponent("New name.md")
        XCTAssertEqual(model.currentFile, renamed)
        XCTAssertEqual(try read(renamed), "ab")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testRenameToTakenNameGetsNumber() throws {
        let model = makeModel()
        let file = try write("a", "a.md", in: starter)
        try write("b", "b.md", in: starter)
        model.rename(file, to: "b")
        XCTAssertEqual(try read(starter.appendingPathComponent("b 2.md")), "a")
    }

    func testTrashCurrentFileDoesNotComeBack() throws {
        let model = makeModel()
        let file = try write("a", "a.md", in: starter)
        model.refresh()
        model.open(file)
        type("b", into: model)
        model.trash(file)
        model.saveNow()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertNil(model.currentFile)
    }

    func testTrashingTheOpenFileKeepsItsLastTyping() throws {
        let model = makeModel()
        let file = try write("a", "a.md", in: starter)
        model.refresh()
        model.open(file)
        type("b", into: model)
        let trashed = try XCTUnwrap(model.trash(file))
        defer { try? FileManager.default.removeItem(at: trashed) }
        XCTAssertEqual(try String(contentsOf: trashed, encoding: .utf8), "ab")
    }

    func testFollowingALinkToAnotherNoteOpensIt() throws {
        let model = makeModel()
        let first = try write("[next](Second.md)", "First.md", in: starter)
        let second = try write("two", "Second.md", in: starter)
        model.refresh()
        model.open(first)
        model.editor.followLink("Second.md")
        XCTAssertEqual(model.currentFile, second)
    }

    func testARefusedLinkSaysWhy() throws {
        let model = makeModel()
        model.editor.followLink("ssh://server")
        XCTAssertNotNil(model.notice)
    }

    // MARK: Folder events

    func testOwnSaveDoesNotRescanFolders() throws {
        let model = makeModel()
        let file = try write("a", "a.md", in: starter)
        model.refresh()
        model.open(file)
        type("b", into: model)
        model.saveNow()
        let scans = model.scannedFolders.count
        model.filesChanged(at: [file.path, starter.appendingPathComponent(".dat.nosync1a2b").path])
        XCTAssertEqual(model.scannedFolders.count, scans)
    }

    func testNewNoteRescansOnlyItsFolder() throws {
        let model = makeModel()
        let other = try folder("Other")
        model.connect(other)
        let scans = model.scannedFolders.count
        let note = try write("hi", "New.md", in: other)
        model.filesChanged(at: [note.path])
        XCTAssertEqual(Array(model.scannedFolders.dropFirst(scans)), [other])
        XCTAssertTrue(model.allFiles.contains(note))
        XCTAssertTrue(model.unseen.contains(note))
    }

    func testNonMarkdownChangesAreIgnored() throws {
        let model = makeModel()
        let scans = model.scannedFolders.count
        let text = try write("x", "notes.txt", in: starter)
        model.filesChanged(at: [text.path])
        XCTAssertEqual(model.scannedFolders.count, scans)
    }

    func testNewSubfolderIsScanned() throws {
        let model = makeModel()
        let sub = starter.appendingPathComponent("Sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let note = try write("x", "In.md", in: sub)
        model.filesChanged(at: [sub.path])
        XCTAssertTrue(model.allFiles.contains(note))
    }

    func testRealPathOfALinkedFolderStillMatches() throws {
        let model = makeModel()
        let real = starter.resolvingSymlinksInPath()
        let note = try write("x", "Real.md", in: starter)
        model.filesChanged(at: [real.appendingPathComponent("Real.md").path])
        XCTAssertTrue(model.allFiles.contains(note))
    }

    func testOpenFileChangedElsewhereStillReloads() throws {
        let model = makeModel()
        let file = try write("a", "a.md", in: starter)
        model.refresh()
        model.open(file)
        try "changed".write(to: file, atomically: true, encoding: .utf8)
        model.filesChanged(at: [file.path])
        XCTAssertEqual(model.editor.string, "changed")
    }

    // MARK: Opening files in place

    func testOpeningAFileFromAnywhereEditsItInPlace() throws {
        let project = try folder("Project")
        let file = try write("a", "Plan.md", in: project)
        let model = makeModel()
        let foldersBefore = model.folders
        model.openFromAnywhere(file)
        XCTAssertEqual(model.currentFile, file)
        XCTAssertEqual(model.folders, foldersBefore, "its folder isn't added")
        type("b", into: model)
        model.saveNow()
        XCTAssertEqual(try read(file), "ab")
        XCTAssertFalse(FileManager.default.fileExists(atPath: starter.appendingPathComponent("Plan.md").path))
    }

    func testOpenedFileIsListed() throws {
        let file = try write("a", "Plan.md", in: try folder("Project"))
        let model = makeModel()
        model.openFromAnywhere(file)
        XCTAssertEqual(model.openedFiles, [file])
    }

    func testOpenedListKeepsTheTenNewestFirst() throws {
        let project = try folder("Project")
        let model = makeModel()
        var files: [URL] = []
        for index in 1...12 {
            let file = try write("\(index)", "Note \(index).md", in: project)
            files.append(file)
            model.openFromAnywhere(file)
        }
        XCTAssertEqual(model.openedFiles, Array(files.reversed().prefix(10)))
    }

    func testReopeningMovesAFileToTheTop() throws {
        let project = try folder("Project")
        let first = try write("a", "A.md", in: project)
        let second = try write("b", "B.md", in: project)
        let model = makeModel()
        model.openFromAnywhere(first)
        model.openFromAnywhere(second)
        model.openFromAnywhere(first)
        XCTAssertEqual(model.openedFiles, [first, second])
    }

    func testOpenedFilesAreRememberedOnRelaunch() throws {
        let file = try write("a", "Plan.md", in: try folder("Project"))
        makeModel().openFromAnywhere(file)
        XCTAssertEqual(makeModel().openedFiles, [file])
    }

    func testFileInAConnectedFolderIsNotListedAsOpened() throws {
        let model = makeModel()
        let file = try write("a", "a.md", in: starter)
        model.openFromAnywhere(file)
        XCTAssertEqual(model.currentFile, file)
        XCTAssertTrue(model.openedFiles.isEmpty)
    }

    func testRemovingFromTheListLeavesTheFile() throws {
        let file = try write("a", "Plan.md", in: try folder("Project"))
        let model = makeModel()
        model.openFromAnywhere(file)
        model.removeFromOpened(file)
        XCTAssertTrue(model.openedFiles.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testAMissingOpenedFileDropsOffTheList() throws {
        let project = try folder("Project")
        let kept = try write("a", "Kept.md", in: project)
        let gone = try write("b", "Gone.md", in: project)
        let model = makeModel()
        model.openFromAnywhere(gone)
        model.openFromAnywhere(kept)
        try FileManager.default.removeItem(at: gone)
        model.refresh()
        XCTAssertEqual(model.openedFiles, [kept])
    }

    func testDroppingAFileOnTheWindowOpensItInPlace() throws {
        let file = try write("a", "Plan.md", in: try folder("Project"))
        let model = makeModel()
        model.handleDrop([file], into: nil)
        XCTAssertEqual(model.currentFile, file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: starter.appendingPathComponent("Plan.md").path))
    }

    func testDroppingAFileOnAFolderSectionStillCopiesIt() throws {
        let file = try write("a", "Plan.md", in: try folder("Project"))
        let model = makeModel()
        model.handleDrop([file], into: starter)
        XCTAssertTrue(FileManager.default.fileExists(atPath: starter.appendingPathComponent("Plan.md").path))
    }

    func testOpenedFilesFoldersAreWatched() throws {
        let project = try folder("Project")
        let file = try write("a", "Plan.md", in: project)
        let model = makeModel()
        model.openFromAnywhere(file)
        XCTAssertTrue(model.watchedFolders.contains(project))
    }

    func testOutsideChangeToAnOpenedFileReloadsIt() throws {
        let file = try write("a", "Plan.md", in: try folder("Project"))
        let model = makeModel()
        model.openFromAnywhere(file)
        try "changed".write(to: file, atomically: true, encoding: .utf8)
        model.filesChanged(at: [file.path])
        XCTAssertEqual(model.editor.string, "changed")
    }

    func testFinderOpensOnlyMarkdownFiles() throws {
        let project = try folder("Project")
        let note = try write("a", "Plan.md", in: project)
        let other = try write("x", "image.png", in: project)
        let model = makeModel()
        model.openFromFinder([other, note])
        XCTAssertEqual(model.currentFile, note)
        XCTAssertEqual(model.openedFiles, [note])
    }

    func testStateRestoredOnRelaunch() throws {
        let project = try folder("Project")
        let file = try write("x", "a.md", in: project)
        let first = makeModel()
        first.connect(project)
        first.open(file)
        first.viewMode = .markdown
        first.themeID = "terminal"
        let second = makeModel()
        XCTAssertEqual(second.folders, first.folders)
        XCTAssertEqual(second.currentFile, file)
        XCTAssertEqual(second.viewMode, .markdown)
        XCTAssertEqual(second.editor.theme.id, "terminal")
    }

    func testFirstLaunchUsesSlate() {
        XCTAssertEqual(makeModel().editor.theme.id, "slate")
    }

    func testSavedInkThemeOpensAsSlate() {
        defaults.set("ink", forKey: "theme")
        XCTAssertEqual(makeModel().editor.theme.id, "slate")
    }

    func testMissingLastFileFallsBackCleanly() throws {
        let model = makeModel()
        let file = try write("x", "a.md", in: starter)
        model.refresh()
        model.open(file)
        try FileManager.default.removeItem(at: file)
        XCTAssertNil(makeModel().currentFile)
    }

    func testNonUTF8FileIsReadOnly() throws {
        let model = makeModel()
        let file = starter.appendingPathComponent("a.md")
        try Data([0x63, 0xE9]).write(to: file)
        model.refresh()
        model.open(file)
        XCTAssertFalse(model.editor.isEditable)
        XCTAssertNotNil(model.notice)
        model.saveNow()
        XCTAssertEqual(try Data(contentsOf: file), Data([0x63, 0xE9]))
    }

    func testCurrentFolderPrefersDeepestConnectedFolder() throws {
        let project = try folder("Project")
        let nested = project.appendingPathComponent("Sub", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let file = try write("x", "a.md", in: nested)
        let model = makeModel()
        model.connect(project)
        model.connect(nested)
        model.open(file)
        XCTAssertEqual(model.currentFolder, nested)
    }

    func testDeletedConnectedFolderShowsEmptySection() throws {
        let project = try folder("Project")
        let model = makeModel()
        model.connect(project)
        try FileManager.default.removeItem(at: project)
        model.refresh()
        XCTAssertEqual(model.sections.last?.files.count, 0)
    }

    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 6) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        return condition()
    }

    func testWatcherPicksUpFileFromOutside() throws {
        let model = AppModel(defaults: defaults, starterFolder: starter, watchesFolders: true)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        let file = try write("from Claude", "New.md", in: starter)
        XCTAssertTrue(waitUntil { model.unseen.contains(file) })
    }

    func testAutosaveWritesAfterAPause() throws {
        let model = makeModel()
        let file = try write("a", "a.md", in: starter)
        model.refresh()
        model.open(file)
        type("b", into: model)
        XCTAssertEqual(try read(file), "a")
        XCTAssertTrue(waitUntil { (try? self.read(file)) == "ab" })
    }

    private let tableText = "| A | B |\n|---|---|\n| 1 | 2 |\n"

    func testSwitchingFilesCommitsCellBeingEdited() throws {
        let model = makeModel()
        let one = try write(tableText, "1.md", in: starter)
        let two = try write("z", "2.md", in: starter)
        model.refresh()
        model.open(one)
        let overlay = try XCTUnwrap(model.editor.tableOverlays.first)
        overlay.beginEditing(row: 1, column: 0)
        overlay.editingField?.stringValue = "typed"
        model.open(two)
        XCTAssertTrue(try read(one).contains("| typed | 2 |"))
    }

    func testFlushCommitsCellBeingEdited() throws {
        let model = makeModel()
        let file = try write(tableText, "1.md", in: starter)
        model.refresh()
        model.open(file)
        let overlay = try XCTUnwrap(model.editor.tableOverlays.first)
        overlay.beginEditing(row: 1, column: 0)
        overlay.editingField?.stringValue = "typed"
        model.flush()
        XCTAssertTrue(try read(file).contains("| typed | 2 |"))
    }

    func testFailedSaveKeepsFileOpen() throws {
        let project = try folder("Locked")
        let one = try write("a", "1.md", in: project)
        let two = try write("z", "2.md", in: project)
        let model = makeModel()
        model.connect(project)
        model.open(one)
        type("b", into: model)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: project.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: one.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: project.path)
        }
        model.open(two)
        XCTAssertEqual(model.currentFile, one)
        XCTAssertEqual(model.editor.string, "ab")
        XCTAssertNotNil(model.notice)
    }

    func testFileListWidthStaysInBounds() {
        let model = makeModel()
        model.fileListWidth = 20
        XCTAssertEqual(model.fileListWidth, AppModel.fileListWidths.lowerBound)
        model.fileListWidth = 5000
        XCTAssertEqual(model.fileListWidth, AppModel.fileListWidths.upperBound)
    }

    func testFileListWidthRestoredOnRelaunch() {
        makeModel().fileListWidth = 300
        XCTAssertEqual(makeModel().fileListWidth, 300)
    }
}
