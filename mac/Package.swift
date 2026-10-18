// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "sclip",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "SclipCore"),
        .target(name: "SclipViewModels", dependencies: ["SclipCore"]),
        .target(name: "SclipPlatform", dependencies: ["SclipCore"]),
        .target(name: "SclipUI", dependencies: ["SclipViewModels"]),
        .executableTarget(
            name: "sclip",
            dependencies: ["SclipCore", "SclipViewModels", "SclipPlatform", "SclipUI"]
        ),
        .testTarget(name: "SclipCoreTests", dependencies: ["SclipCore"]),
        .testTarget(name: "SclipViewModelsTests", dependencies: ["SclipViewModels"]),
        .testTarget(name: "SclipPlatformTests", dependencies: ["SclipPlatform"]),
    ],
    swiftLanguageModes: [.v6]
)
