// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BorderMuseImaging",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "BorderMuseImaging", targets: ["BorderMuseImaging"]),
        .executable(name: "bordermuse-verify", targets: ["BorderMuseVerification"]),
    ],
    dependencies: [.package(path: "../..")],
    targets: [
        .target(name: "BorderMuseImaging", dependencies: [
            .product(name: "BorderMuseGeometry", package: "bordermuse"),
        ]),
        .executableTarget(name: "BorderMuseVerification", dependencies: [
            "BorderMuseImaging",
            .product(name: "BorderMuseGeometry", package: "bordermuse"),
        ], path: "Verification"),
        .testTarget(name: "BorderMuseImagingTests", dependencies: [
            "BorderMuseImaging",
            .product(name: "BorderMuseGeometry", package: "bordermuse"),
        ]),
    ]
)
