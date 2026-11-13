// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VTranslator",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "VTranslator",
            path: "Sources/VTranslator"
        )
    ]
)
