// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudetteCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "ClaudetteCore", targets: ["ClaudetteCore"])],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.5.0"),
    ],
    targets: [
        .target(name: "ClaudetteCore", dependencies: [.product(name: "Markdown", package: "swift-markdown")]),
        .testTarget(name: "ClaudetteCoreTests", dependencies: ["ClaudetteCore"]),
    ]
)
