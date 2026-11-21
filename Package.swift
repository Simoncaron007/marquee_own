// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Marquee",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Marquee",
            path: "Sources/Marquee"
        )
    ]
)
