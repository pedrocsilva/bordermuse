// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "BorderMuseMac", defaultLocalization: "en-US", platforms: [.macOS(.v14)],
    products: [.executable(name: "BorderMuse", targets: ["BorderMuse"])],
    dependencies: [
        .package(path: "../.."),
        .package(path: "../../packages/imaging-apple"),
    ],
    targets: [.executableTarget(name: "BorderMuse", dependencies: [
        .product(name: "BorderMuseGeometry", package: "bordermuse"),
        .product(name: "BorderMuseImaging", package: "imaging-apple"),
    ], path: "BorderMuse", exclude: ["Resources/Info.plist", "Resources/BorderMuse.entitlements", "Resources/AppIcon.icns"],
       resources: [.process("Resources/en-US.lproj")]),
       .testTarget(name: "BorderMuseSessionTests", dependencies: ["BorderMuse"], path: "Tests")]
)
