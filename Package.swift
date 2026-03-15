// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "doc-crop",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/ainame/Swift-WebP.git", from: "0.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "doc-crop",
            dependencies: [
                .product(name: "WebP", package: "Swift-WebP"),
            ],
            path: "Sources/doc-crop"
        ),
    ]
)
