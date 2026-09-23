// swift-tools-version:6.2
import PackageDescription

let appSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "Afterhours",
    platforms: [.macOS(.v14)],
    targets: [
        // A library: stays nonisolated so callers decide where it runs.
        .target(name: "AfterhoursCore"),
        .executableTarget(
            name: "Afterhours",
            dependencies: ["AfterhoursCore"],
            swiftSettings: appSettings,
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("Carbon")]
        ),
        .executableTarget(name: "afterhours-hook", dependencies: ["AfterhoursCore"], swiftSettings: appSettings),
    ]
)
