// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Countdownula",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Countdownula",
            path: "Sources/Countdownula",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
