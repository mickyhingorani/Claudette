import AppKit
import XCTest
@testable import Claudette

/// Serves a fixed picture for any web address, so web images can be tested offline.
final class StubImageProtocol: URLProtocol {
    nonisolated(unsafe) static var data = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/png"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class ImageTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudetteImageTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    nonisolated static func png(width: Int, height: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: width, height: height)
        return rep.representation(using: .png, properties: [:])!
    }

    private func picture(_ name: String, width: Int, height: Int) throws {
        try Self.png(width: width, height: height).write(to: folder.appendingPathComponent(name))
    }

    private func makeEditor(_ text: String, loader: ImageLoader? = nil) -> EditorTextView {
        let (_, editor) = EditorTextView.makeInScrollView()
        editor.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        if let loader { editor.imageLoader = loader }
        editor.documentFolder = folder
        editor.load(text: text)
        editor.layoutManager!.ensureLayout(for: editor.textContainer!)
        editor.positionOverlays()
        return editor
    }

    private func top(of location: Int, in editor: EditorTextView) -> CGFloat {
        let layout = editor.hidingLayoutManager
        layout.ensureLayout(for: editor.textContainer!)
        return layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: location), effectiveRange: nil).minY + editor.textContainerOrigin.y
    }

    func testLocalImageShowsAtItsOwnSize() throws {
        try picture("pic.png", width: 120, height: 60)
        let editor = makeEditor("a\n\n![x](pic.png)\n\nb")
        let overlay = try XCTUnwrap(editor.imageOverlays.first)
        XCTAssertEqual(overlay.frame.size, NSSize(width: 120, height: 60))
        XCTAssertFalse(overlay.isPlaceholder)
    }

    func testTextBelowAnImageStartsBelowIt() throws {
        try picture("pic.png", width: 120, height: 60)
        let text = "a\n\n![x](pic.png)\n\nb"
        let editor = makeEditor(text)
        let overlay = try XCTUnwrap(editor.imageOverlays.first)
        XCTAssertGreaterThanOrEqual(top(of: (text as NSString).length - 1, in: editor), overlay.frame.maxY)
        XCTAssertGreaterThanOrEqual(overlay.frame.minY, top(of: 0, in: editor) + 10)
    }

    func testWideImageShrinksToTheTextColumn() throws {
        try picture("wide.png", width: 3000, height: 1500)
        let editor = makeEditor("![x](wide.png)\n")
        let overlay = try XCTUnwrap(editor.imageOverlays.first)
        XCTAssertLessThan(overlay.frame.width, 800)
        XCTAssertEqual(overlay.frame.height, overlay.frame.width / 2, accuracy: 1)
    }

    func testImageSourceIsHiddenAwayFromTheCaret() throws {
        try picture("pic.png", width: 120, height: 60)
        let editor = makeEditor("a\n\n![x](pic.png)\n")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertTrue(editor.hidingLayoutManager.isHidden(at: 3))
    }

    func testCaretOnTheImageShowsItsSourceAboveThePicture() throws {
        try picture("pic.png", width: 120, height: 60)
        let editor = makeEditor("a\n\n![x](pic.png)\n")
        editor.setSelectedRange(NSRange(location: 8, length: 0))
        editor.positionOverlays()
        XCTAssertFalse(editor.hidingLayoutManager.isHidden(at: 3))
        let overlay = try XCTUnwrap(editor.imageOverlays.first)
        let font = editor.textStorage!.attribute(.font, at: 3, effectiveRange: nil) as! NSFont
        XCTAssertGreaterThanOrEqual(overlay.frame.minY, top(of: 3, in: editor) + font.ascender - font.descender)
    }

    func testWrappedSourceReservesThePictureOnce() throws {
        try picture("pic.png", width: 120, height: 60)
        let alt = String(repeating: "a long description ", count: 12)
        let text = "![\(alt)](pic.png)\n\nafter"
        let editor = makeEditor(text)
        editor.setSelectedRange(NSRange(location: 5, length: 0))
        editor.positionOverlays()
        let layout = editor.hidingLayoutManager
        let image = try XCTUnwrap(editor.imageOverlays.first)
        let source = NSRange(location: 0, length: (text as NSString).range(of: "\n").location)
        var lines: [NSRect] = []
        layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(forCharacterRange: source, actualCharacterRange: nil)) { _, used, _, _, _ in
            lines.append(used)
        }
        XCTAssertGreaterThan(lines.count, 1, "the source should wrap")
        let lastTextBottom = try XCTUnwrap(lines.last).maxY + editor.textContainerOrigin.y
        XCTAssertGreaterThanOrEqual(image.frame.minY, lastTextBottom - 1)
        let after = top(of: (text as NSString).length - 1, in: editor)
        XCTAssertLessThan(after - image.frame.maxY, 40, "no extra picture-sized gap below")
    }

    func testRemovedImageLeavesNoStaleOffset() throws {
        try picture("pic.png", width: 120, height: 60)
        let editor = makeEditor("a\n\n![x](pic.png)\n")
        editor.setSelectedRange(NSRange(location: 8, length: 0))
        editor.hidingLayoutManager.ensureLayout(for: editor.textContainer!)
        XCTAssertGreaterThan(editor.hidingLayoutManager.blockOffset(at: 3), 0)
        editor.applyEdit(NSRange(location: 1, length: 15), "")
        editor.hidingLayoutManager.ensureLayout(for: editor.textContainer!)
        XCTAssertEqual(editor.hidingLayoutManager.blockOffset(at: 3), 0)
    }

    func testClickingAnImageShowsItsSource() throws {
        try picture("pic.png", width: 120, height: 60)
        let editor = makeEditor("a\n\n![x](pic.png)\n")
        try XCTUnwrap(editor.imageOverlays.first).onClick?()
        XCTAssertEqual(editor.selectedRange().location, 16)
        XCTAssertFalse(editor.hidingLayoutManager.isHidden(at: 3))
    }

    func testMissingImageShowsAPlaceholder() throws {
        let editor = makeEditor("![x](nowhere.png)\n")
        let overlay = try XCTUnwrap(editor.imageOverlays.first)
        XCTAssertTrue(overlay.isPlaceholder)
        XCTAssertEqual(overlay.label, "nowhere.png")
        XCTAssertGreaterThan(overlay.frame.height, 20)
    }

    func testImageInASentenceIsNotDrawn() throws {
        try picture("pic.png", width: 120, height: 60)
        let editor = makeEditor("see ![x](pic.png) here\n")
        XCTAssertTrue(editor.imageOverlays.isEmpty)
    }

    func testMarkdownViewShowsNoPictures() throws {
        try picture("pic.png", width: 120, height: 60)
        let editor = makeEditor("![x](pic.png)\n")
        editor.viewMode = .markdown
        XCTAssertTrue(editor.imageOverlays.isEmpty)
        XCTAssertFalse(editor.hidingLayoutManager.isHidden(at: 0))
    }

    func testWebImageLoadsAndTakesItsSize() throws {
        StubImageProtocol.data = Self.png(width: 90, height: 30)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubImageProtocol.self]
        let loader = ImageLoader(session: URLSession(configuration: configuration))
        let editor = makeEditor("![x](https://example.test/a.png)\n", loader: loader)
        let loaded = expectation(description: "image loaded")
        loader.onLoad = { loaded.fulfill() }
        wait(for: [loaded], timeout: 5)
        editor.positionOverlays()
        let overlay = try XCTUnwrap(editor.imageOverlays.first)
        XCTAssertFalse(overlay.isPlaceholder)
        XCTAssertEqual(overlay.frame.size, NSSize(width: 90, height: 30))
    }

    func testLoadingNeverChangesTheText() throws {
        try picture("pic.png", width: 120, height: 60)
        let text = "a\n\n![x](pic.png)\n"
        XCTAssertEqual(makeEditor(text).string, text)
    }
}

@MainActor
final class ImageResizeTests: XCTestCase {
    func testNarrowingTheWindowShrinksAWideImage() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudetteResize-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try ImageTests.png(width: 3000, height: 1500).write(to: folder.appendingPathComponent("wide.png"))
        let (_, editor) = EditorTextView.makeInScrollView()
        editor.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        editor.documentFolder = folder
        editor.load(text: "![x](wide.png)\n")
        editor.positionOverlays()
        let wide = try XCTUnwrap(editor.imageOverlays.first).frame.width
        editor.setFrameSize(NSSize(width: 400, height: 600))
        editor.positionOverlays()
        XCTAssertLessThan(try XCTUnwrap(editor.imageOverlays.first).frame.width, wide)
    }
}

/// Counts requests, and fails until told to succeed.
final class CountingImageProtocol: URLProtocol {
    nonisolated(unsafe) static var requests: [URL] = []
    nonisolated(unsafe) static var succeeds = true
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request.url!)
        let status = Self.succeeds ? 200 : 404
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if Self.succeeds { client?.urlProtocol(self, didLoad: ImageTests.png(width: 40, height: 20)) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class ImageLoaderTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudetteLoader-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        CountingImageProtocol.requests = []
        CountingImageProtocol.succeeds = true
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func countingLoader(retryAfter: TimeInterval = 30) -> ImageLoader {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CountingImageProtocol.self]
        return ImageLoader(session: URLSession(configuration: configuration), retryAfter: retryAfter)
    }

    private func makeEditor(_ text: String, loader: ImageLoader? = nil) -> EditorTextView {
        let (_, editor) = EditorTextView.makeInScrollView()
        editor.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        editor.imageLoader = loader ?? ImageLoader(session: .shared)
        editor.documentFolder = folder
        editor.load(text: text)
        editor.positionOverlays()
        return editor
    }

    private func wait(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    func testMissingPictureAppearsOnceTheFileExists() throws {
        let editor = makeEditor("![x](later.png)\n")
        XCTAssertTrue(try XCTUnwrap(editor.imageOverlays.first).isPlaceholder)
        try ImageTests.png(width: 50, height: 25).write(to: folder.appendingPathComponent("later.png"))
        editor.restyle()
        XCTAssertFalse(try XCTUnwrap(editor.imageOverlays.first).isPlaceholder)
    }

    func testChangedPictureIsReloaded() throws {
        let file = folder.appendingPathComponent("pic.png")
        try ImageTests.png(width: 50, height: 25).write(to: file)
        let editor = makeEditor("![x](pic.png)\n")
        try ImageTests.png(width: 80, height: 40).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: file.path)
        editor.restyle()
        editor.positionOverlays()
        XCTAssertEqual(try XCTUnwrap(editor.imageOverlays.first).frame.size, NSSize(width: 80, height: 40))
    }

    func testTypingAWebAddressFetchesOnlyWhereYouStop() {
        let loader = countingLoader()
        let editor = makeEditor("![x](https://e.test/a)\n", loader: loader)
        wait(0.2)
        XCTAssertEqual(CountingImageProtocol.requests.count, 1)
        for character in "bcd" {
            let end = (editor.string as NSString).range(of: ")").location
            editor.insertText(String(character), replacementRange: NSRange(location: end, length: 0))
        }
        wait(0.2)
        XCTAssertEqual(CountingImageProtocol.requests.count, 1, "nothing fetched while typing")
        wait(0.8)
        XCTAssertEqual(CountingImageProtocol.requests.map(\.absoluteString), ["https://e.test/a", "https://e.test/abcd"])
    }

    func testFailedWebPictureIsTriedAgainLater() {
        CountingImageProtocol.succeeds = false
        let loader = countingLoader(retryAfter: 0.3)
        let url = URL(string: "https://e.test/flaky.png")!
        _ = loader.state(for: url)
        wait(0.2)
        guard case .failed = loader.state(for: url) else { return XCTFail("should have failed") }
        CountingImageProtocol.succeeds = true
        wait(0.3)
        _ = loader.state(for: url)
        wait(0.2)
        guard case .loaded = loader.state(for: url) else { return XCTFail("should load on retry") }
    }

    func testOversizedFileIsNotLoaded() throws {
        let file = folder.appendingPathComponent("huge.png")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(ImageLoader.maxBytes + 1))
        try handle.close()
        guard case .failed = ImageLoader(session: .shared).state(for: file) else { return XCTFail("should refuse") }
    }
}

final class AppSettingsTests: XCTestCase {
    /// Plain http pictures are blocked by default; Claudette only fetches pictures, so it allows them.
    func testPlainHttpPicturesAreAllowed() {
        let security = Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity") as? [String: Any]
        XCTAssertEqual(security?["NSAllowsArbitraryLoads"] as? Bool, true)
    }
}
