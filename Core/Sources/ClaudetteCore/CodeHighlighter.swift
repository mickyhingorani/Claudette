import Foundation
import JavaScriptCore

public enum CodeTokenKind: Equatable, Sendable {
    case keyword, string, number, comment, function, tag, attribute, type
}

public struct CodeToken: Equatable, Sendable {
    public var range: NSRange
    public var kind: CodeTokenKind
}

/// Finds the parts of code worth coloring, using the bundled highlight.js.
/// It reports what each part is, not its color, so themes own the colors.
@MainActor
public final class CodeHighlighter {
    public static let shared = CodeHighlighter()

    private static let maxLength = 100_000
    private static let maxGuessLength = 5_000
    private static let maxCacheEntries = 200

    private struct CacheKey: Hashable {
        let code: String
        let language: String?
    }

    private var context: JSContext?
    private var engine: JSValue?
    private var cache: [CacheKey: [CodeToken]] = [:]

    private init() {}

    /// Tokens in the order to apply them: an inner token follows the one it sits inside.
    public func tokens(in code: String, language: String?) -> [CodeToken] {
        let length = (code as NSString).length
        guard length > 0, length <= Self.maxLength else { return [] }
        let key = CacheKey(code: code, language: language?.lowercased())
        if let cached = cache[key] { return cached }
        let result = highlightedHTML(code, language: key.language).map { Self.parse($0, expectedLength: length) } ?? []
        if cache.count >= Self.maxCacheEntries { cache.removeAll() }
        cache[key] = result
        return result
    }

    /// Names where highlight.js's own reads badly as a label: its HTML grammar is "HTML, XML".
    private static let nameOverrides = ["html": "HTML", "xhtml": "HTML", "htm": "HTML", "xml": "XML", "svg": "SVG", "plaintext": "Text", "text": "Text", "txt": "Text"]

    /// The language's proper name for a code block's label, like "JavaScript" for `js`.
    /// A language highlight.js doesn't know keeps the name as written; a blank one has none.
    public func displayName(for language: String) -> String? {
        let key = language.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { return nil }
        if let name = Self.nameOverrides[key] { return name }
        guard let engine = loadEngine(),
              let definition = engine.invokeMethod("getLanguage", withArguments: [key]), definition.isObject,
              let name = definition.objectForKeyedSubscript("name"), name.isString else {
            return language.trimmingCharacters(in: .whitespaces)
        }
        return name.toString()
    }

    /// How many guesses have run, so callers can check they aren't guessing on every keystroke.
    public private(set) var guessCount = 0

    /// highlight.js's guess at the language of unlabeled code, or `plaintext`. Guessing tries
    /// every language, so it's slow: callers should guess once per block and reuse the answer.
    public func guessLanguage(in code: String) -> String {
        let sample = (code as NSString).length > Self.maxGuessLength ? (code as NSString).substring(to: Self.maxGuessLength) : code
        guard !sample.isEmpty, let engine = loadEngine() else { return "plaintext" }
        guessCount += 1
        let result = engine.invokeMethod("highlightAuto", withArguments: [sample])
        guard let language = result?.objectForKeyedSubscript("language"), language.isString else { return "plaintext" }
        return language.toString()
    }

    private func loadEngine() -> JSValue? {
        if let engine { return engine }
        guard let url = Bundle.module.url(forResource: "highlight.min", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8),
              let context = JSContext() else { return nil }
        context.evaluateScript(source)
        let loaded = context.objectForKeyedSubscript("hljs")
        guard let loaded, loaded.isObject else { return nil }
        self.context = context
        engine = loaded
        return loaded
    }

    private func highlightedHTML(_ code: String, language: String?) -> String? {
        guard let engine = loadEngine() else { return nil }
        let result: JSValue?
        if let language, engine.invokeMethod("getLanguage", withArguments: [language])?.isObject == true {
            result = engine.invokeMethod("highlight", withArguments: [code, ["language": language, "ignoreIllegals": true]])
        } else if (code as NSString).length <= Self.maxGuessLength {
            result = engine.invokeMethod("highlightAuto", withArguments: [code])
        } else {
            result = nil
        }
        guard let value = result?.objectForKeyedSubscript("value"), value.isString else { return nil }
        return value.toString()
    }

    private static func kind(forClasses classes: String) -> CodeTokenKind? {
        let names = classes.split(separator: " ")
        if names.contains("class_") { return .type }
        if names.contains("function_") { return .function }
        guard let first = names.first else { return nil }
        switch first {
        case "hljs-keyword", "hljs-literal", "hljs-selector-pseudo": return .keyword
        case "hljs-string", "hljs-regexp", "hljs-symbol": return .string
        case "hljs-number": return .number
        case "hljs-comment", "hljs-quote", "hljs-doctag", "hljs-meta": return .comment
        case "hljs-title", "hljs-section": return .function
        case "hljs-tag", "hljs-name", "hljs-selector-tag": return .tag
        case "hljs-attr", "hljs-attribute", "hljs-selector-class", "hljs-selector-id", "hljs-property": return .attribute
        case "hljs-type", "hljs-built_in": return .type
        default: return nil
        }
    }

    /// Reads highlight.js's spans into ranges of the original code.
    private static func parse(_ html: String, expectedLength: Int) -> [CodeToken] {
        let entities: [(String, Int)] = [("&amp;", 5), ("&lt;", 4), ("&gt;", 4), ("&quot;", 6), ("&#x27;", 6)]
        let openTag = "<span class=\""
        let closeTag = "</span>"
        var tokens: [CodeToken?] = []
        var stack: [Int?] = []
        var offset = 0
        var index = html.startIndex
        while index < html.endIndex {
            let rest = html[index...]
            if rest.hasPrefix(openTag) {
                let classStart = html.index(index, offsetBy: openTag.count)
                guard let classEnd = html[classStart...].firstIndex(of: "\"") else { return [] }
                if let kind = kind(forClasses: String(html[classStart..<classEnd])) {
                    stack.append(tokens.count)
                    tokens.append(CodeToken(range: NSRange(location: offset, length: 0), kind: kind))
                } else {
                    stack.append(nil)
                }
                index = html.index(classEnd, offsetBy: 2)
            } else if rest.hasPrefix(closeTag) {
                guard let open = stack.popLast() else { return [] }
                if let open, var token = tokens[open] {
                    token.range.length = offset - token.range.location
                    tokens[open] = token
                }
                index = html.index(index, offsetBy: closeTag.count)
            } else if html[index] == "&", let entity = entities.first(where: { rest.hasPrefix($0.0) }) {
                offset += 1
                index = html.index(index, offsetBy: entity.1)
            } else {
                offset += html[index].utf16.count
                index = html.index(after: index)
            }
        }
        // If the text doesn't add up, the ranges can't be trusted.
        guard offset == expectedLength else { return [] }
        return tokens.compactMap { $0 }.filter { $0.range.length > 0 }
    }
}
