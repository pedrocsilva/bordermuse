// swift-tools-version: 5.9
import PackageDescription

// This repository's public Swift package contains only portable geometry.
let package = Package(
    name: "BorderMuseGeometry",
    products: [
        .library(name: "BorderMuseGeometry", targets: ["BorderMuseGeometry"]),
    ],
    targets: [
        .target(name: "BorderMuseGeometry", path: "packages/geometry-swift/Sources"),
        .testTarget(
            name: "BorderMuseGeometryTests",
            dependencies: ["BorderMuseGeometry"],
            path: "geometry",
            exclude: ["README.md", "reference.py", "test_reference.py"],
            sources: ["swift"],
            resources: [.copy("conformance-v1.json")]
        ),
    ]
)
