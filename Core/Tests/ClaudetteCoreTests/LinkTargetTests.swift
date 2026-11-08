import Foundation
import Testing
@testable import ClaudetteCore

@Suite struct LinkTargetTests {
    let folder = URL(fileURLWithPath: "/Users/someone/Notes", isDirectory: true)

    @Test func webAndEmailLinksOpenOutside() {
        #expect(LinkTarget.resolve("https://example.com", relativeTo: folder) == .external(URL(string: "https://example.com")!))
        #expect(LinkTarget.resolve("http://example.com/a", relativeTo: folder) == .external(URL(string: "http://example.com/a")!))
        #expect(LinkTarget.resolve("mailto:a@b.com", relativeTo: folder) == .external(URL(string: "mailto:a@b.com")!))
    }

    @Test func markdownFileLinksOpenInClaudette() {
        #expect(LinkTarget.resolve("plan.md", relativeTo: folder) == .document(folder.appendingPathComponent("plan.md")))
        #expect(LinkTarget.resolve("sub/My%20Notes.md", relativeTo: folder) == .document(folder.appendingPathComponent("sub/My Notes.md")))
        #expect(LinkTarget.resolve("plan.md#section", relativeTo: folder) == .document(folder.appendingPathComponent("plan.md")))
        #expect(LinkTarget.resolve("file:///tmp/x.markdown", relativeTo: folder) == .document(URL(fileURLWithPath: "/tmp/x.markdown")))
    }

    @Test func otherFilesAndSchemesAreRefused() {
        #expect(LinkTarget.resolve("file:///Applications/Calculator.app", relativeTo: folder) == .refused)
        #expect(LinkTarget.resolve("run.command", relativeTo: folder) == .refused)
        #expect(LinkTarget.resolve("ssh://server", relativeTo: folder) == .refused)
        #expect(LinkTarget.resolve("javascript:alert(1)", relativeTo: folder) == .refused)
    }

    @Test func sameDocumentAnchorsDoNothing() {
        #expect(LinkTarget.resolve("#heading", relativeTo: folder) == .none)
    }

    @Test func relativeMarkdownLinkWithoutAFolderIsRefused() {
        #expect(LinkTarget.resolve("plan.md", relativeTo: nil) == .refused)
    }
}
