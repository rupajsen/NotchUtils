// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "NotchUtils",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "NotchUtils",
            path: "Sources",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
