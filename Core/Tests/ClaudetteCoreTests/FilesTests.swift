import Foundation
import Testing
@testable import ClaudetteCore

private func tempFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func write(_ text: String, _ name: String, in folder: URL, age: TimeInterval = 0) throws -> URL {
    let url = folder.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -age)], ofItemAtPath: url.path)
    return url
}

@Suite struct FileNamingTests {
    @Test func nameStripsHeadingMarks() { #expect(FileNaming.name(fromFirstLineOf: "## Launch plan\nmore") == "Launch plan") }
    @Test func nameSkipsBlankLines() { #expect(FileNaming.name(fromFirstLineOf: "\n\nHello") == "Hello") }
    @Test func nameFallsBackToUntitled() { #expect(FileNaming.name(fromFirstLineOf: "  \n") == "Untitled") }
    @Test func nameSkipsLinesWithOnlySyntax() { #expect(FileNaming.name(fromFirstLineOf: "---\nReal") == "Real") }
    @Test func nameRemovesSlashes() { #expect(FileNaming.name(fromFirstLineOf: "a/b:c") == "a-b-c") }
    @Test func nameNeverStartsWithDot() { #expect(FileNaming.name(fromFirstLineOf: ".hidden") == "hidden") }
    @Test func nameIsCapped() { #expect(FileNaming.name(fromFirstLineOf: String(repeating: "a", count: 200)).count == 60) }

    @Test func uniqueURLUsesPlainNameWhenFree() throws {
        let folder = try tempFolder()
        #expect(FileNaming.uniqueURL(for: "A", in: folder).lastPathComponent == "A.md")
    }

    @Test func uniqueURLAddsNumber() throws {
        let folder = try tempFolder()
        _ = try write("", "A.md", in: folder)
        _ = try write("", "A 2.md", in: folder)
        #expect(FileNaming.uniqueURL(for: "A", in: folder).lastPathComponent == "A 3.md")
    }

    @Test func conflictNameFormat() throws {
        let file = try write("", "Name.md", in: try tempFolder())
        #expect(FileNaming.conflictURL(for: file).lastPathComponent == "Name (conflict).md")
    }

    @Test func secondConflictGetsNumber() throws {
        let folder = try tempFolder()
        let file = try write("", "Name.md", in: folder)
        _ = try write("", "Name (conflict).md", in: folder)
        #expect(FileNaming.conflictURL(for: file).lastPathComponent == "Name (conflict 2).md")
    }
}

@Suite struct FolderScannerTests {
    @Test func scanFindsNestedNewestFirst() throws {
        let folder = try tempFolder()
        _ = try write("", "old.md", in: folder, age: 100)
        _ = try write("", "sub/new.md", in: folder)
        #expect(try FolderScanner.scan(folder).map(\.displayName) == ["new", "old"])
    }

    @Test func scanURLsEqualPlainFileURLs() throws {
        let folder = try tempFolder()
        let file = try write("", "sub/a.md", in: folder)
        #expect(try FolderScanner.scan(folder).first?.url == URL(fileURLWithPath: file.path))
    }

    @Test func scanListsSymlinkUnderItsOwnURL() throws {
        let folder = try tempFolder()
        let real = try write("", "real.md", in: folder)
        let link = folder.appendingPathComponent("link.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let urls = Set(try FolderScanner.scan(folder).map(\.url.lastPathComponent))
        #expect(urls == ["real.md", "link.md"])
    }

    @Test func scanIgnoresOtherFiles() throws {
        let folder = try tempFolder()
        _ = try write("", "a.txt", in: folder)
        #expect(try FolderScanner.scan(folder).isEmpty)
    }

    @Test func scanMatchesExtensionInAnyCase() throws {
        let folder = try tempFolder()
        _ = try write("", "A.MD", in: folder)
        #expect(try FolderScanner.scan(folder).count == 1)
    }

    @Test func scanSkipsHiddenFolders() throws {
        let folder = try tempFolder()
        _ = try write("", ".git/a.md", in: folder)
        #expect(try FolderScanner.scan(folder).isEmpty)
    }

    @Test func scanSkipsNodeModules() throws {
        let folder = try tempFolder()
        _ = try write("", "node_modules/x/README.md", in: folder)
        #expect(try FolderScanner.scan(folder).isEmpty)
    }

    @Test func scanOfMissingFolderThrows() {
        #expect(throws: (any Error).self) { try FolderScanner.scan(URL(fileURLWithPath: "/nonexistent/\(UUID())")) }
    }
}

@Suite struct DocumentFileTests {
    @Test func loadWithoutSaveLeavesBytes() throws {
        let file = try write("a\r\nb", "a.md", in: try tempFolder())
        let before = try Data(contentsOf: file)
        let date = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
        let document = try DocumentFile(url: file)
        try document.save(document.text)
        #expect(try Data(contentsOf: file) == before)
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date == date)
    }

    @Test func saveWritesText() throws {
        let file = try write("a", "a.md", in: try tempFolder())
        try DocumentFile(url: file).save("b")
        #expect(try String(contentsOf: file, encoding: .utf8) == "b")
    }

    @Test func saveKeepsCRLFAndBOM() throws {
        let text = "\u{FEFF}a\r\nb\r\n"
        let file = try write(text, "a.md", in: try tempFolder())
        let document = try DocumentFile(url: file)
        #expect(document.text.unicodeScalars.first?.value == 0xFEFF)
        try document.save(document.text + "c")
        #expect(try Data(contentsOf: file) == Data((text + "c").utf8))
    }

    @Test func nonUTF8IsReadOnly() throws {
        let folder = try tempFolder()
        let file = folder.appendingPathComponent("a.md")
        try Data([0x63, 0x61, 0x66, 0xE9]).write(to: file)
        let document = try DocumentFile(url: file)
        #expect(document.isReadOnly)
        #expect(document.text == "café")
    }

    @Test func readOnlySaveThrows() throws {
        let folder = try tempFolder()
        let file = folder.appendingPathComponent("a.md")
        let bytes = Data([0x63, 0xE9])
        try bytes.write(to: file)
        let document = try DocumentFile(url: file)
        #expect(throws: DocumentFile.SaveError.readOnly) { try document.save("x") }
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test func checkDiskUnchanged() throws {
        let document = try DocumentFile(url: try write("a", "a.md", in: try tempFolder()))
        #expect(document.checkDisk() == .unchanged)
    }

    @Test func checkDiskSeesOwnSaveAsUnchanged() throws {
        let document = try DocumentFile(url: try write("a", "a.md", in: try tempFolder()))
        try document.save("b")
        #expect(document.checkDisk() == .unchanged)
    }

    @Test func checkDiskSeesExternalChange() throws {
        let file = try write("a", "a.md", in: try tempFolder())
        let document = try DocumentFile(url: file)
        try Data("z".utf8).write(to: file)
        #expect(document.checkDisk() == .changed("z"))
    }

    @Test func checkDiskSeesMissingFile() throws {
        let file = try write("a", "a.md", in: try tempFolder())
        let document = try DocumentFile(url: file)
        try FileManager.default.removeItem(at: file)
        #expect(document.checkDisk() == .missing)
    }

    @Test func acceptDiskMakesItCurrent() throws {
        let file = try write("a", "a.md", in: try tempFolder())
        let document = try DocumentFile(url: file)
        try Data("z".utf8).write(to: file)
        document.acceptDisk()
        #expect(document.text == "z")
        #expect(document.checkDisk() == .unchanged)
    }

    @Test func saveConflictCopyWritesBesideFile() throws {
        let file = try write("a", "Name.md", in: try tempFolder())
        let document = try DocumentFile(url: file)
        try Data("theirs".utf8).write(to: file)
        let copy = try document.saveConflictCopy()
        #expect(copy.lastPathComponent == "Name (conflict).md")
        #expect(try String(contentsOf: copy, encoding: .utf8) == "theirs")
    }

    @Test func conflictCopyKeepsTheOtherBytes() throws {
        let file = try write("a", "Name.md", in: try tempFolder())
        let document = try DocumentFile(url: file)
        let bytes = Data([0x63, 0xE9, 0x20])
        try bytes.write(to: file)
        #expect(try Data(contentsOf: try document.saveConflictCopy()) == bytes)
    }

    @Test func saveThroughSymlinkKeepsTheLink() throws {
        let folder = try tempFolder()
        let real = try write("a", "real.md", in: folder)
        let link = folder.appendingPathComponent("link.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        try DocumentFile(url: link).save("edited")
        #expect(try String(contentsOf: real, encoding: .utf8) == "edited")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == real.path)
    }

    @Test func saveRecreatesMissingFile() throws {
        let file = try write("a", "a.md", in: try tempFolder())
        let document = try DocumentFile(url: file)
        try FileManager.default.removeItem(at: file)
        try document.save("kept")
        #expect(try String(contentsOf: file, encoding: .utf8) == "kept")
    }

    @Test func movedDocumentSavesToNewURL() throws {
        let folder = try tempFolder()
        let file = try write("a", "a.md", in: folder)
        let document = try DocumentFile(url: file)
        let target = folder.appendingPathComponent("b.md")
        try FileManager.default.moveItem(at: file, to: target)
        document.url = target
        try document.save("c")
        #expect(try String(contentsOf: target, encoding: .utf8) == "c")
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}
