import Foundation
import Testing
@testable import ClaudetteCore

@MainActor
@Suite struct CodeHighlighterTests {
    private func kinds(_ code: String, _ language: String?) -> [String: CodeTokenKind] {
        let ns = code as NSString
        var result: [String: CodeTokenKind] = [:]
        for token in CodeHighlighter.shared.tokens(in: code, language: language) {
            result[ns.substring(with: token.range)] = token.kind
        }
        return result
    }

    @Test func javascript() {
        let found = kinds("const a = 'x'; // note\nsum(1);", "javascript")
        #expect(found["const"] == .keyword)
        #expect(found["'x'"] == .string)
        #expect(found["// note"] == .comment)
        #expect(found["1"] == .number)
        #expect(found["sum"] == .function)
    }

    @Test func html() {
        let found = kinds("<a href=\"p.html\">x</a>", "html")
        #expect(found["a"] == .tag)
        #expect(found["href"] == .attribute)
        #expect(found["\"p.html\""] == .string)
    }

    @Test func css() {
        let found = kinds(".box { color: red; width: 10px; }", "css")
        #expect(found[".box"] == .attribute)
        #expect(found["color"] == .attribute)
        #expect(found["10px"] == .number)
    }

    @Test func languageAliasWorks() {
        #expect(kinds("const a = 1;", "js")["const"] == .keyword)
    }

    @Test func labelCaseDoesNotMatter() {
        #expect(kinds("const a = 1;", "JavaScript")["const"] == .keyword)
    }

    @Test func otherLanguages() {
        #expect(kinds("def f():\n    return 1", "python")["def"] == .keyword)
        #expect(kinds("let a = 1", "swift")["let"] == .keyword)
        #expect(kinds("SELECT 1", "sql")["SELECT"] == .keyword)
    }

    @Test func unknownLabelStillDoesNotCrash() {
        _ = CodeHighlighter.shared.tokens(in: "hello", language: "notalanguage")
    }

    @Test func noLabelGuessesLanguage() {
        #expect(kinds("<!DOCTYPE html>\n<html>\n<body class=\"a\"><p>hi</p></body>\n</html>", nil)["body"] == .tag)
    }

    @Test func emptyCodeHasNoTokens() {
        #expect(CodeHighlighter.shared.tokens(in: "", language: "js").isEmpty)
    }

    @Test func rangesExactAfterEmojiAndEntities() {
        let code = "const a = '😀 & <b>'; const b = 2;"
        let found = kinds(code, "js")
        #expect(found["'😀 & <b>'"] == .string)
        #expect(found["2"] == .number)
    }

    @Test func tokensStayInsideTheCode() {
        let code = "<div>&amp; \"q\" 'r'</div>\r\n// 😀"
        let length = (code as NSString).length
        #expect(CodeHighlighter.shared.tokens(in: code, language: "html").allSatisfy { NSMaxRange($0.range) <= length })
    }

    @Test func innerTokensComeAfterOuterOnes() {
        let tokens = CodeHighlighter.shared.tokens(in: "<a>", language: "html")
        #expect(tokens.first?.range.length == 3)
        #expect(tokens.last?.range.length == 1)
    }

    @Test func hugeCodeIsSkipped() {
        #expect(CodeHighlighter.shared.tokens(in: String(repeating: "a ", count: 100_000), language: "js").isEmpty)
    }
}

@MainActor
@Suite struct LanguageGuessTests {
    @Test func guessesTheLanguageOfUnlabeledCode() {
        let guess = CodeHighlighter.shared.guessLanguage(in: "<!DOCTYPE html>\n<html>\n  <body>\n    <p class=\"note\">Hi</p>\n  </body>\n</html>\n")
        #expect(guess != "plaintext", "guessed \(guess)")
    }

    @Test func guessingNothingSaysPlainText() {
        #expect(CodeHighlighter.shared.guessLanguage(in: "") == "plaintext")
    }
}
