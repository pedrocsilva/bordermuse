import Foundation
import XCTest
@testable import BorderMuseImaging

final class PhotoParityTests: XCTestCase {
    func testPublicPhotoReferenceExports() throws {
        guard let path = ProcessInfo.processInfo.environment["BORDERMUSE_PHOTO_CORPUS"] else {
            throw XCTSkip("Opt-in public photo QA: run the Public photo parity workflow.")
        }
        let root = URL(fileURLWithPath: path)
        for filename in ["river.jpg", "Landscape_6.jpg", "Portrait_8.jpg"] {
            let input = root.appendingPathComponent("input/" + filename)
            let original = try Data(contentsOf: input)
            let version = try ImageFileVersion.read(input)
            for edge in [0, 2048] {
                let directory = root.appendingPathComponent("macos/" + (edge == 0 ? "original" : "2048"))
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let output = directory.appendingPathComponent(filename)
                try ImageProcessor.export(input: input, output: output,
                    options: ImageOptions(thickness: 10, longEdge: edge == 0 ? nil : edge), expectedVersion: version)
                XCTAssertEqual(try ImageProcessor.inspect(output).orientation, 1)
                print("Reference: \(filename), long edge \(edge == 0 ? "original" : "2048")")
            }
            XCTAssertEqual(try Data(contentsOf: input), original)
        }
    }
}
