// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EditorGeometryExample",
    dependencies: [.package(path: "../..")],
    targets: [
        .executableTarget(name: "EditorGeometryExample", dependencies: [
            .product(name: "BorderMuseGeometry", package: "bordermuse"),
        ]),
    ]
)
