// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MacClipboard",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MacClipboard",
            path: "Sources/MacClipboard",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        // Requires Xcode (XCTest isn't included in the Command Line Tools). Runs in CI.
        .testTarget(
            name: "MacClipboardTests",
            dependencies: ["MacClipboard"],
            path: "Tests/MacClipboardTests"
        ),
    ]
)
