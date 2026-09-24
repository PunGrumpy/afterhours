// swift-tools-version:6.2
import PackageDescription

let appSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let core: Target.Dependency = .product(name: "AfterhoursCore", package: "core")

let package = Package(
    name: "Afterhours",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../packages/core")],
    targets: [
        .executableTarget(
            name: "Afterhours",
            dependencies: [core],
            swiftSettings: appSettings,
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("Carbon")]
        ),
        .executableTarget(name: "afterhours-hook", dependencies: [core], swiftSettings: appSettings),
    ]
)
