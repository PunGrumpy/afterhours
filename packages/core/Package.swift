// swift-tools-version:6.2
import PackageDescription

let shippedSettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "AfterhoursCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AfterhoursCore", targets: ["AfterhoursCore"])],
    // A library: stays nonisolated so callers decide where it runs. The two upcoming features match
    // what build-app.sh passes, so the tests check the semantics that ship.
    targets: [
        .target(name: "AfterhoursCore", swiftSettings: shippedSettings),
        .testTarget(name: "AfterhoursCoreTests", dependencies: ["AfterhoursCore"], swiftSettings: shippedSettings),
    ]
)
