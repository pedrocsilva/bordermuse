import XCTest
import BorderMuseGeometry
import BorderMuseImaging

final class ResizingTests: XCTestCase {
    func testResizingIsIndependentAndNeverEnlarges() throws {
        let source = try PixelSize(width: 6000, height: 4000)
        XCTAssertEqual(try source.reduced(longEdge: 1200), try PixelSize(width: 1200, height: 800))
        XCTAssertEqual(try source.reduced(longEdge: 8000), source)
        XCTAssertEqual(try source.reduced(longEdge: nil), source)
        XCTAssertThrowsError(try source.reduced(longEdge: 0))
    }
}
