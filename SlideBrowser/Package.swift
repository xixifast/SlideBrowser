// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SlideBrowser",
    platforms: [.macOS(.v14)],
    targets: [
        // All behaviour lives here so it can be unit tested; the executable only bootstraps.
        .target(
            name: "SlideBrowserKit",
            path: "Sources/SlideBrowserKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "SlideBrowser",
            dependencies: ["SlideBrowserKit"],
            path: "Sources/SlideBrowser",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SlideBrowserKitTests",
            dependencies: ["SlideBrowserKit"],
            path: "Tests/SlideBrowserKitTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
