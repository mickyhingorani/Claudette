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

    func testDroppedFileImports() throws {
        let source = try write("x", "a.md", in: try folder("Outside"))
        let model = makeModel()
        model.handleDrop([source], into: nil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: starter.appendingPathComponent("a.md").path))
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
