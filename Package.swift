// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DeskDragon",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "DeskDragon", path: "Sources/DeskDragon")
    ],
    swiftLanguageVersions: [.v5]
)
