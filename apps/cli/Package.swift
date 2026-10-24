// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "bordermuse-cli",
    platforms: [.macOS(.v12)],
    dependencies: [
        .package(path: "../../packages/imaging-apple"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(name: "bordermuse", dependencies: [
            .product(name: "BorderMuseImaging", package: "imaging-apple"),
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),
    ]
)
