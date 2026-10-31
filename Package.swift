// swift-tools-version:6.2
import PackageDescription

let settings: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "NotchUtils",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "SMCKit", swiftSettings: settings),
        .executableTarget(name: "NotchUtils", dependencies: ["SMCKit"], swiftSettings: settings),
        .executableTarget(name: "NotchUtilsFanHelper", dependencies: ["SMCKit"], swiftSettings: settings),
        .executableTarget(name: "FanControllerChecks", dependencies: ["SMCKit"], swiftSettings: settings),
    ]
)
