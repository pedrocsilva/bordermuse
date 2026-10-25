import CoreGraphics
import Foundation
import ImageIO
import XCTest
import BorderMuseGeometry
import BorderMuseImaging

final class MobileGeometryTests: XCTestCase {
    private struct Corpus: Decodable { let cases: [Case] }
    private struct Case: Decodable {
        struct Input: Decodable { let width, height, thickness: Int; let ratio: [Int] }
        let source_file: String
        let input: Input
        let expected: CanvasLayout
    }
    private struct Pipeline: Decodable {
        struct Baseline: Decodable { let sourceWidth, sourceHeight, preparedWidth, preparedHeight: Int }
        let photoLongEdge: Int
        let baselines: [String: Baseline]
    }
    func testFullSizeThroughReductionAndRenderingMatchesAllMeasuredGeometry() throws {
        // Read the canonical files directly from the checkout; never copy/regenerate expectations.
        let geometry = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../geometry").standardizedFileURL
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: geometry.appendingPathComponent("conformance-v1.json")))
        let pipeline = try JSONDecoder().decode(Pipeline.self, from: Data(contentsOf: geometry.appendingPathComponent("mobile-export-v1.json")))
        XCTAssertEqual(corpus.cases.count, 20)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (key, baseline) in pipeline.baselines {
            let source = root.appendingPathComponent(key + ".png")
            try Self.blackImage(width: baseline.sourceWidth, height: baseline.sourceHeight, to: source)
            let original = try Data(contentsOf: source)
            for sample in corpus.cases where sample.source_file.hasPrefix(key + "_") {
                try autoreleasepool {
                    XCTAssertEqual(sample.input.width, baseline.preparedWidth)
                    XCTAssertEqual(sample.input.height, baseline.preparedHeight)
                    let info = try ImageProcessor.inspect(source)
                    XCTAssertEqual(try info.size.reduced(longEdge: pipeline.photoLongEdge), try PixelSize(width: baseline.preparedWidth, height: baseline.preparedHeight))
                    let options = try ImageOptions(thickness: sample.input.thickness,
                        ratio: AspectRatio.parse("\(sample.input.ratio[0]):\(sample.input.ratio[1])"), longEdge: pipeline.photoLongEdge, preserveMetadata: false)
                    XCTAssertEqual(try ImageProcessor.layout(for: info, options: options), sample.expected, sample.source_file)
                    let output = root.appendingPathComponent(sample.source_file + ".png")
                    try ImageProcessor.export(input: source, output: output, options: options)
                    XCTAssertEqual(try Self.measuredLayout(output), [sample.expected.width, sample.expected.height, sample.expected.left, sample.expected.right, sample.expected.top, sample.expected.bottom], sample.source_file)
                }
            }
            XCTAssertEqual(try Data(contentsOf: source), original)
        }
    }
    // These validate Border Muse policy only, not unmeasured Lightroom behavior.
    func testOriginalCustomAndSmallPhotosRemainIndependentPolicies() throws {
        let small = try PixelSize(width: 1001, height: 667)
        XCTAssertEqual(try small.reduced(longEdge: 2048), small)
        XCTAssertEqual(try small.reduced(longEdge: nil), small)
        XCTAssertEqual(try small.reduced(longEdge: 500), try PixelSize(width: 500, height: 333))
        let source = try PixelSize(width: 3923, height: 5886)
        XCTAssertEqual(try source.reduced(longEdge: nil), source)
        let prepared = try source.reduced(longEdge: 2048)
        let originalRatio = try CanvasLayout.calculate(content: prepared, thickness: 7, ratio: nil)
        XCTAssertEqual(originalRatio, try CanvasLayout.calculate(content: prepared, thickness: 7, ratio: AspectRatio(width: prepared.width, height: prepared.height)))
    }
    private static func blackImage(width: Int, height: Int, to url: URL) throws {
        let data = Data(repeating: 0, count: width * height)
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
    private static func measuredLayout(_ url: URL) throws -> [Int] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var left = w, right = -1, top = h, bottom = -1
        for y in 0..<h { for x in 0..<w where bytes[(y * w + x) * 4] < 128 {
            left = min(left, x); right = max(right, x); top = min(top, y); bottom = max(bottom, y)
        } }
        XCTAssertGreaterThanOrEqual(right, left)
        return [w, h, left, w - right - 1, top, h - bottom - 1]
    }
}
