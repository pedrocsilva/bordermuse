import Foundation
import XCTest
@testable import BorderMuseGeometry

final class ConformanceTests: XCTestCase {
    struct Corpus: Decodable { let spec_id: String; let cases: [Case] }
    struct Case: Decodable {
        struct Input: Decodable { let width: Int; let height: Int; let thickness: Int; let ratio: [Int] }
        let source_file: String
        let input: Input
        let expected: CanvasLayout
    }

    func testEveryMeasuredExport() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "conformance-v1", withExtension: "json"))
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
        XCTAssertEqual(corpus.spec_id, CanvasLayout.contractID)
        XCTAssertEqual(corpus.cases.count, 20)
        for test in corpus.cases {
            let size = try PixelSize(width: test.input.width, height: test.input.height)
            let ratio = try AspectRatio(width: test.input.ratio[0], height: test.input.ratio[1])
            let result = try CanvasLayout.calculate(content: size, thickness: test.input.thickness, ratio: ratio)
            XCTAssertEqual(result, test.expected, test.source_file)
        }
    }

    func testExactIntegerBoundaryAndOriginal() throws {
        let size = try PixelSize(width: 100, height: 100)
        let result = try CanvasLayout.calculate(content: size, thickness: 14, ratio: nil)
        XCTAssertEqual(result.width, 114)
        XCTAssertEqual(result.left, 7)
        let odd = try PixelSize(width: 1201, height: 799)
        let original = try CanvasLayout.calculate(content: odd, thickness: 7, ratio: nil)
        let explicit = try CanvasLayout.calculate(content: odd, thickness: 7, ratio: AspectRatio(width: 1201, height: 799))
        XCTAssertEqual(original, explicit)
    }

    func testInvalidInputsAndOverflow() throws {
        XCTAssertThrowsError(try PixelSize(width: 0, height: 10))
        XCTAssertThrowsError(try AspectRatio.parse("1:2:3"))
        XCTAssertThrowsError(try AspectRatio.parse("0:1"))
        let size = try PixelSize(width: 100, height: 100)
        XCTAssertThrowsError(try CanvasLayout.calculate(content: size, thickness: 51, ratio: nil))
        let huge = try PixelSize(width: Int.max, height: 100)
        XCTAssertThrowsError(try CanvasLayout.calculate(content: huge, thickness: 50, ratio: AspectRatio(width: 1, height: 1)))
    }

}
