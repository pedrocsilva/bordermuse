import XCTest
@testable import BorderMuse

final class LocalizationTests: XCTestCase {
    func testGeneratedPositionalFormatsLoadFromTheAppBundle() {
        XCTAssertEqual(Strings.format("contentSize", 12001, 8300), "Content: 12,001 × 8,300 px")
        XCTAssertEqual(Strings.format("position", 1, 2000), "Photo 1 of 2,000")
        XCTAssertEqual(Strings.format("previewSummary", "photo%20.png", "Output: 2,048 × 1,365 px"),
                       "Preview of photo%20.png. Output: 2,048 × 1,365 px")
    }
}
