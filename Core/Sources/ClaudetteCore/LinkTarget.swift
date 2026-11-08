import Foundation

/// What following a link should do. Only web and email links leave the app, and only
/// Markdown files open inside it, so a link can't launch an app or run a script.
public enum LinkTarget: Equatable, Sendable {
    /// A web page or email address, opened in the default browser or mail app.
    case external(URL)
    /// A Markdown file, opened in Claudette.
    case document(URL)
    /// A link to a place in the same document: nothing to open.
    case none
    /// Anything else, such as another kind of file or an unknown scheme.
    case refused

    private static let externalSchemes: Set<String> = ["http", "https", "mailto"]
    private static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]

    public static func resolve(_ link: String, relativeTo folder: URL?) -> LinkTarget {
        let trimmed = link.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") { return .none }
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() {
            if externalSchemes.contains(scheme) { return .external(url) }
            if scheme == "file" { return isMarkdown(url) ? .document(URL(fileURLWithPath: url.path)) : .refused }
            return .refused
        }
        let withoutAnchor = String(trimmed.prefix { $0 != "#" && $0 != "?" })
        let path = withoutAnchor.removingPercentEncoding ?? withoutAnchor
        let url: URL?
        if path.hasPrefix("/") || path.hasPrefix("~") {
            url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        } else {
            url = folder?.appendingPathComponent(path)
        }
        guard let url, isMarkdown(url) else { return .refused }
        return .document(url.standardizedFileURL)
    }

    private static func isMarkdown(_ url: URL) -> Bool {
        markdownExtensions.contains(url.pathExtension.lowercased())
    }
}
