import Foundation
import Testing
@testable import ClaudetteCore

private func r(_ location: Int, _ length: Int) -> NSRange { NSRange(location: location, length: length) }

@Suite struct ImageScanTests {
    @Test func imageOnItsOwnLineIsABlockImage() {
        let map = MarkdownScanner.scan("a\n\n![Chart](img/chart.png)\n")
        #expect(map.images == [ImageInfo(range: r(3, 23), source: "img/chart.png", alt: "Chart", isBlock: true)])
    }

    @Test func blockImageSourceIsHiddenUntilTheCaretIsOnIt() {
        let map = MarkdownScanner.scan("![x](a.png)")
        #expect(map.hidden.contains(HiddenRange(range: r(0, 11), owner: r(0, 11), kind: .inline)))
    }

    @Test func imageInsideASentenceIsInline() {
        let map = MarkdownScanner.scan("see ![x](a.png) here")
        #expect(map.images.first?.isBlock == false)
        #expect(map.hidden.isEmpty)
    }

    @Test func webImageKeepsItsAddress() {
        #expect(MarkdownScanner.scan("![](https://example.com/a.png)").images.first?.source == "https://example.com/a.png")
    }

    @Test func imageWithSpacesAroundIsStillABlock() {
        #expect(MarkdownScanner.scan("  ![x](a.png)  \n").images.first?.isBlock == true)
    }
}

@Suite struct CalloutScanTests {
    @Test func noteCalloutIsFound() {
        let map = MarkdownScanner.scan("> [!NOTE]\n> Read this.\n")
        #expect(map.callouts == [Callout(range: r(0, 22), kind: .note, marker: r(2, 7), title: nil)])
    }

    @Test func everyKindIsRecognizedInAnyCase() {
        let kinds = ["NOTE", "tip", "Important", "WARNING", "caution"].map {
            MarkdownScanner.scan("> [!\($0)]\n> x\n").callouts.first?.kind
        }
        #expect(kinds == [.note, .tip, .important, .warning, .caution])
    }

    @Test func markerIsHiddenWithTheQuotePrefix() {
        let hidden = MarkdownScanner.scan("> [!TIP]\n> x\n").hidden.map(\.range)
        #expect(hidden.contains(r(0, 2)))
        #expect(hidden.contains(r(2, 6)))
    }

    @Test func textAfterTheMarkerIsACustomTitle() {
        let callout = MarkdownScanner.scan("> [!WARNING] Mind the gap\n> x\n").callouts.first
        #expect(callout?.title == r(13, 12))
        #expect(callout?.marker == r(2, 11))
    }

    @Test func ordinaryQuoteIsNoCallout() {
        #expect(MarkdownScanner.scan("> just a quote\n").callouts.isEmpty)
    }

    @Test func unknownKindIsNoCallout() {
        #expect(MarkdownScanner.scan("> [!FOO]\n> x\n").callouts.isEmpty)
    }
}

@Suite struct StyleMapMergeTests {
    private func r(_ location: Int, _ length: Int) -> NSRange { NSRange(location: location, length: length) }

    @Test func imageDirectlyAboveATableIsKept() {
        let map = MarkdownScanner.scan("![pic](a.png)\n| a | b |\n|---|---|\n")
        #expect(map.images.count == 1)
        #expect(map.images.first?.isBlock == true)
    }

    @Test func mergeKeepsEveryKindOfResult() {
        var full = StyleMap()
        full.spans = [StyledSpan(range: r(0, 1), kind: .strong)]
        full.hidden = [HiddenRange(range: r(0, 1), owner: r(0, 1), kind: .inline)]
        full.substitutions = [Substitution(range: r(0, 1), glyph: "•", owner: r(0, 1))]
        full.taskBoxes = [TaskBox(range: r(0, 3), isChecked: true, owner: r(0, 3))]
        full.codeBlocks = [CodeBlockInfo(range: r(0, 5), contentRange: r(1, 2), language: "js", isClosed: true)]
        full.paragraphBreaks = [r(4, 1)]
        full.images = [ImageInfo(range: r(0, 5), source: "a.png", alt: "", isBlock: true)]
        full.callouts = [Callout(range: r(0, 9), kind: .tip, marker: r(2, 6), title: nil)]
        var merged = StyleMap()
        merged.merge(full)
        #expect(merged == full)
    }
}
