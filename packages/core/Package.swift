// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "AfterhoursCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AfterhoursCore", targets: ["AfterhoursCore"])],
    // A library: stays nonisolated so callers decide where it runs.
    targets: [.target(name: "AfterhoursCore")]
)
