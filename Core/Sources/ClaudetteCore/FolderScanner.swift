import Foundation

public struct ListedFile: Equatable, Sendable {
    public var url: URL
    public var displayName: String
    public var modified: Date
}

public enum FolderScanner {
    private static let skippedFolders: Set<String> = ["node_modules"]

    /// Every `.md` file in a folder and its subfolders, newest first.
    public static func scan(_ folder: URL) throws -> [ListedFile] {
        let manager = FileManager.default
        var isFolder: ObjCBool = false
        guard manager.fileExists(atPath: folder.path, isDirectory: &isFolder), isFolder.boolValue else {
            throw CocoaError(.fileNoSuchFile)
        }
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        guard let walker = manager.enumerator(at: folder, includingPropertiesForKeys: keys,
                                              options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var files: [ListedFile] = []
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if skippedFolders.contains(url.lastPathComponent) { walker.skipDescendants() }
                continue
            }
            guard url.pathExtension.lowercased() == "md" else { continue }
            files.append(ListedFile(url: plainURL(of: url, in: folder), displayName: url.deletingPathExtension().lastPathComponent,
                                    modified: values?.contentModificationDate ?? .distantPast))
        }
        return files.sorted {
            $0.modified != $1.modified ? $0.modified > $1.modified : $0.displayName < $1.displayName
        }
    }

    /// The enumerator can resolve symlinks in a folder's path, so rebuild the URL from the
    /// folder as connected. Then it equals any other URL made for the same file.
    private static func plainURL(of url: URL, in folder: URL) -> URL {
        let base = folder.resolvingSymlinksInPath().path + "/"
        let path = url.resolvingSymlinksInPath().path
        guard path.hasPrefix(base) else { return URL(fileURLWithPath: url.path) }
        let parent = folder.path.hasSuffix("/") ? folder.path : folder.path + "/"
        return URL(fileURLWithPath: parent + path.dropFirst(base.count))
    }
}
