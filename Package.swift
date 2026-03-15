// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "doc-crop",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "doc-crop",
            path: "Sources/doc-crop"
        ),
    ]
)
