import AppKit

/// Loads pictures for image lines, from the Mac or the web, and keeps recent ones for reuse.
@MainActor
final class ImageLoader {
    enum State {
        case loading
        case loaded(NSImage)
        case failed
    }

    static let shared = ImageLoader(session: .shared)
    static let didLoad = Notification.Name("ImageLoaderDidLoad")
    /// Larger files and downloads aren't shown.
    static let maxBytes = 40 * 1024 * 1024

    private final class Entry {
        let image: NSImage
        let version: Date?
        init(image: NSImage, version: Date?) {
            self.image = image
            self.version = version
        }
    }

    private let session: URLSession
    private let retryAfter: TimeInterval
    /// Decoded pictures, dropped by the system when memory is short or the limit is reached.
    private let images = NSCache<NSURL, Entry>()
    private var pending: Set<URL> = []
    /// Web pictures that failed, and when. They're tried again after `retryAfter`.
    private var webFailures: [URL: Date] = [:]
    /// Files that couldn't be read, by the change date they had then.
    private var fileFailures: [URL: Date] = [:]
    /// Called after a web picture arrives or fails and editors have updated.
    var onLoad: (() -> Void)?

    init(session: URLSession, retryAfter: TimeInterval = 30) {
        self.session = session
        self.retryAfter = retryAfter
        images.totalCostLimit = 256 * 1024 * 1024
    }

    /// True while any web picture is on its way.
    var isLoading: Bool { !pending.isEmpty }

    /// Where an image's source points: a web address, or a file path relative to the document.
    static func url(for source: String, relativeTo folder: URL?) -> URL? {
        let trimmed = source.trimmingCharacters(in: .whitespaces)
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), ["http", "https", "file"].contains(scheme) {
            return url
        }
        let path = (trimmed.removingPercentEncoding ?? trimmed) as NSString
        if path.hasPrefix("/") || path.hasPrefix("~") { return URL(fileURLWithPath: path.expandingTildeInPath) }
        return folder?.appendingPathComponent(path as String)
    }

    /// The picture if it's ready. Files load right away, and again when they change.
    /// Web pictures start loading only when `startLoading` is true, so typing an address
    /// doesn't fetch every partial one.
    func state(for url: URL, startLoading: Bool = true) -> State {
        url.isFileURL ? fileState(for: url) : webState(for: url, startLoading: startLoading)
    }

    private func fileState(for url: URL) -> State {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return .failed }
        let version = attributes[.modificationDate] as? Date
        if let entry = images.object(forKey: url as NSURL), entry.version == version { return .loaded(entry.image) }
        if let failed = fileFailures[url], failed == version { return .failed }
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size <= Self.maxBytes, let image = NSImage(contentsOf: url) else {
            fileFailures[url] = version
            return .failed
        }
        fileFailures[url] = nil
        images.setObject(Entry(image: image, version: version), forKey: url as NSURL, cost: Self.cost(of: image))
        return .loaded(image)
    }

    private func webState(for url: URL, startLoading: Bool) -> State {
        if let entry = images.object(forKey: url as NSURL) { return .loaded(entry.image) }
        if pending.contains(url) { return .loading }
        if let failed = webFailures[url], Date().timeIntervalSince(failed) < retryAfter { return .failed }
        guard startLoading else { return .loading }
        pending.insert(url)
        session.dataTask(with: url) { data, response, _ in
            let isOK = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            let fits = (data?.count ?? 0) <= Self.maxBytes
            let image = isOK && fits ? data.flatMap(NSImage.init(data:)) : nil
            Task { @MainActor in
                self.pending.remove(url)
                if let image {
                    self.webFailures[url] = nil
                    self.images.setObject(Entry(image: image, version: nil), forKey: url as NSURL, cost: Self.cost(of: image))
                } else {
                    self.webFailures[url] = Date()
                }
                NotificationCenter.default.post(name: Self.didLoad, object: self)
                self.onLoad?()
            }
        }.resume()
        return .loading
    }

    /// Roughly the memory a decoded picture takes.
    private static func cost(of image: NSImage) -> Int {
        let pixels = image.representations.map { $0.pixelsWide * $0.pixelsHigh }.max() ?? 0
        return max(pixels, Int(image.size.width * image.size.height)) * 4
    }
}
