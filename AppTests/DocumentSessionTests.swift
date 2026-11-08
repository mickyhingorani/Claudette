import Foundation
import XCTest
import ClaudetteCore
@testable import Claudette

/// The rules that keep edits safe, tested without any editor or window.
@MainActor
final class DocumentSessionTests: XCTestCase {
    private var folder: URL!
    private var text = ""
    private var session: DocumentSession!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("SessionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        text = ""
        session = DocumentSession(autosaveDelay: 60) { [unowned self] in self.text }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func file(_ name: String, _ contents: String) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

    func testEditThenSaveWritesTheText() throws {
        let url = try file("a.md", "a")
        try session.open(url)
        text = "ab"
        session.markEdited()
        XCTAssertTrue(session.isDirty)
        XCTAssertEqual(session.saveNow(), .saved)
        XCTAssertEqual(try read(url), "ab")
        XCTAssertFalse(session.isDirty)
    }

    func testNothingToSaveWithoutAnEdit() throws {
        try session.open(try file("a.md", "a"))
        XCTAssertEqual(session.saveNow(), .nothingToSave)
    }

    func testOutsideChangePlusEditKeepsBothVersions() throws {
        let url = try file("a.md", "a")
        try session.open(url)
        text = "mine"
        session.markEdited()
        try "theirs".write(to: url, atomically: true, encoding: .utf8)
        guard case .savedWithConflictCopy(let copy) = session.saveNow() else { return XCTFail("expected a conflict copy") }
        XCTAssertEqual(try read(url), "mine")
        XCTAssertEqual(try read(copy), "theirs")
    }

    func testUndoneEditsTakeTheOutsideVersion() throws {
        let url = try file("a.md", "a")
        try session.open(url)
        text = "a"
        session.markEdited()
        try "theirs".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(session.saveNow(), .reloaded("theirs"))
        XCTAssertEqual(try read(url), "theirs")
    }

    func testCheckingDiskReloadsAnOutsideChange() throws {
        let url = try file("a.md", "a")
        try session.open(url)
        try "theirs".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(session.checkDisk(), .reloaded("theirs"))
        XCTAssertTrue(session.matchesDisk)
    }

    func testCheckingDiskSavesPendingEditsFirst() throws {
        let url = try file("a.md", "a")
        try session.open(url)
        text = "ab"
        session.markEdited()
        XCTAssertEqual(session.checkDisk(), .saved)
        XCTAssertEqual(try read(url), "ab")
    }

    func testCheckingDiskNoticesADeletedFile() throws {
        let url = try file("a.md", "a")
        try session.open(url)
        try FileManager.default.removeItem(at: url)
        XCTAssertEqual(session.checkDisk(), .missing)
    }

    func testDraftBecomesAFileNamedFromItsFirstLine() throws {
        session.startDraft(in: folder)
        text = "# Trip notes\nbody"
        session.markEdited()
        guard case .created(let url) = session.saveNow() else { return XCTFail("expected a new file") }
        XCTAssertEqual(url.lastPathComponent, "Trip notes.md")
        XCTAssertEqual(session.currentFile, url)
        XCTAssertEqual(try read(url), "# Trip notes\nbody")
    }

    func testBlankDraftIsNotSaved() throws {
        session.startDraft(in: folder)
        text = "  \n"
        session.markEdited()
        XCTAssertEqual(session.saveNow(), .nothingToSave)
        XCTAssertFalse(session.isDirty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
    }

    func testReadOnlyFileIsNeverWritten() throws {
        let url = folder.appendingPathComponent("latin.md")
        try Data([0x63, 0x61, 0x66, 0xE9]).write(to: url)
        try session.open(url)
        XCTAssertTrue(session.isReadOnly)
        text = "changed"
        session.markEdited()
        XCTAssertEqual(session.saveNow(), .readOnly)
        XCTAssertEqual(try Data(contentsOf: url), Data([0x63, 0x61, 0x66, 0xE9]))
    }

    func testFailedSaveKeepsTheEditPending() throws {
        let url = try file("a.md", "a")
        try session.open(url)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }
        try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: url.path)
        text = "ab"
        session.markEdited()
        XCTAssertEqual(session.saveNow(), .failed)
        XCTAssertTrue(session.isDirty)
    }

    func testRenamingTheOpenFileFollowsIt() throws {
        let url = try file("a.md", "a")
        try session.open(url)
        let renamed = try XCTUnwrap(try session.rename(url, to: "Better name"))
        XCTAssertEqual(renamed.lastPathComponent, "Better name.md")
        XCTAssertEqual(session.currentFile, renamed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testRenamingToTheSameNameDoesNothing() throws {
        let url = try file("a.md", "a")
        XCTAssertNil(try session.rename(url, to: "a.md"))
    }

    func testTrashingReturnsWhereTheFileWent() throws {
        let url = try file("gone.md", "x")
        let trashed = try session.trash(url)
        defer { try? FileManager.default.removeItem(at: trashed) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try read(trashed), "x")
    }

    func testAutosaveSavesAfterAPause() throws {
        let url = try file("a.md", "a")
        let quick = DocumentSession(autosaveDelay: 0.1) { [unowned self] in self.text }
        try quick.open(url)
        var outcomes: [DocumentSession.SaveOutcome] = []
        quick.onAutosave = { outcomes.append($0) }
        text = "ab"
        quick.markEdited()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        XCTAssertEqual(outcomes, [.saved])
        XCTAssertEqual(try read(url), "ab")
    }
}
