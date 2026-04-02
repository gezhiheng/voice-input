// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "VoiceInput",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "VoiceInput",
            targets: ["VoiceInputApp"]
        )
    ],
    targets: [
        .executableTarget(
            name: "VoiceInputApp",
            path: "Sources/VoiceInputApp"
        ),
        .testTarget(
            name: "VoiceInputAppTests",
            dependencies: ["VoiceInputApp"],
            path: "Tests/VoiceInputAppTests"
        )
    ],
    swiftLanguageModes: [.v5]
)