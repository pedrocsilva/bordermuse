import XCTest
import BorderMuseGeometry
@testable import BorderMuseImaging

final class ImageTests: XCTestCase {
    func testUnreadableImageFailsBeforeWriting() throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try ImageProcessor.export(input: output.appendingPathExtension("missing"), output: output, options: ImageOptions()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }
}
