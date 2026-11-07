import Foundation

public enum DiskChange: Equatable, Sendable {
    case unchanged
    case changed(String)
    case missing
}

/// One Markdown file. It only writes when the text really differs from what's on disk.
public final class DocumentFile {
    public enum SaveError: Error, Equatable {
        case readOnly
    }

    public var url: URL
    public private(set) var text: String
    public private(set) var isReadOnly: Bool
    private var diskData: Data

    public init(url: URL) throws {
        self.url = url
        let data = try Data(contentsOf: url)
        diskData = data
        (text, isReadOnly) = Self.decode(data)
    }

    private static func decode(_ data: Data) -> (String, Bool) {
        // `String(data:encoding:)` only validates here: it would drop a BOM from the text.
        if String(data: data, encoding: .utf8) != nil { return (String(decoding: data, as: UTF8.self), false) }
        return (String(data: data, encoding: .isoLatin1) ?? "", true)
    }

    public func save(_ newText: String) throws {
        guard !isReadOnly else { throw SaveError.readOnly }
        let data = Data(newText.utf8)
        let isOnDisk = FileManager.default.fileExists(atPath: url.path)
        if data == diskData, isOnDisk { return }
        // Write to a link's target: an atomic write would replace the link with a file.
        try data.write(to: url.resolvingSymlinksInPath(), options: .atomic)
        diskData = data
        text = newText
    }

    public func checkDisk() -> DiskChange {
        guard let data = try? Data(contentsOf: url) else { return .missing }
        return data == diskData ? .unchanged : .changed(Self.decode(data).0)
    }

    /// Takes on what's on disk now as the current text.
    public func acceptDisk() {
        guard let data = try? Data(contentsOf: url) else { return }
        diskData = data
        (text, isReadOnly) = Self.decode(data)
    }

    @discardableResult
    public func saveConflictCopy() throws -> URL {
        let copy = FileNaming.conflictURL(for: url)
        // The other version's exact bytes: it may not be text this app can read.
        try Data(contentsOf: url).write(to: copy, options: .atomic)
        return copy
    }
}
