import Foundation

public enum FileNaming {
    private static let maxLength = 60
    private static let maxBytes = 200

    /// A file name from the first line of text that has words in it.
    public static func name(fromFirstLineOf text: String) -> String {
        let syntax = CharacterSet(charactersIn: "#>-*_`~=+ \t")
        for line in text.split(whereSeparator: \.isNewline) {
            var name = line.trimmingCharacters(in: syntax)
            name = name.components(separatedBy: CharacterSet(charactersIn: "/\\:")).joined(separator: "-")
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            if !name.isEmpty {
                var short = String(name.prefix(maxLength))
                // File names are limited to 255 bytes; a short title of emoji can pass that.
                while short.utf8.count > maxBytes { short.removeLast() }
                return short.trimmingCharacters(in: .whitespaces)
            }
        }
        return "Untitled"
    }

    public static func uniqueURL(for name: String, in folder: URL) -> URL {
        firstFree(in: folder) { number in number == 1 ? "\(name).md" : "\(name) \(number).md" }
    }

    public static func conflictURL(for url: URL) -> URL {
        let name = url.deletingPathExtension().lastPathComponent
        return firstFree(in: url.deletingLastPathComponent()) { number in
            number == 1 ? "\(name) (conflict).md" : "\(name) (conflict \(number)).md"
        }
    }

    private static func firstFree(in folder: URL, name: (Int) -> String) -> URL {
        var number = 1
        while true {
            let url = folder.appendingPathComponent(name(number))
            if !FileManager.default.fileExists(atPath: url.path) { return url }
            number += 1
        }
    }
}
