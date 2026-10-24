import CoreGraphics
import Foundation
import ImageIO
import XCTest
import BorderMuseGeometry
@testable import BorderMuseImaging

final class ColorMetadataTests: XCTestCase {
    private let marker = "Synthetic BorderMuse metadata"
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bordermuse-color-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func fixture(_ directory: URL, type: String, bits: Int, space: CFString, orientation: Int = 1, noise: Bool = false) throws -> URL {
        let url = directory.appendingPathComponent(UUID().uuidString)
        let context = try XCTUnwrap(CGContext(data: nil, width: 101, height: 67, bitsPerComponent: bits, bytesPerRow: 0,
            space: CGColorSpace(name: space)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | (bits == 16 ? CGBitmapInfo.byteOrder16Little.rawValue : 0)))
        // These 16-bit values are deliberately not multiples of 257 (8-bit precision).
        if bits == 16 {
            let words = context.data!.assumingMemoryBound(to: UInt16.self)
            for y in 0..<67 { for x in 0..<101 {
                let index = y * context.bytesPerRow / 2 + x * 4
                words[index] = 10001; words[index + 1] = 30002; words[index + 2] = 50003; words[index + 3] = 65535
            } }
        } else if noise {
            let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
            var random: UInt32 = 0x12345678
            for y in 0..<67 { for x in 0..<101 { for c in 0..<3 {
                random = random &* 1664525 &+ 1013904223
                bytes[y * context.bytesPerRow + x * 4 + c] = UInt8((random >> 16) & 255)
            } } }
        } else {
            context.setFillColor(CGColor(red: 0.15, green: 0.4, blue: 0.65, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 101, height: 67))
        }
        let metadata = CGImageMetadataCreateMutable()
        var error: Unmanaged<CFError>?
        XCTAssertTrue(CGImageMetadataRegisterNamespaceForPrefix(metadata, "https://example.invalid/bordermuse/qa/1.0/" as CFString, "bmqa" as CFString, &error))
        XCTAssertTrue(CGImageMetadataSetValueWithPath(metadata, nil, "bmqa:Marker" as CFString, marker as CFString))
        XCTAssertTrue(CGImageMetadataSetValueMatchingImageProperty(metadata, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFOrientation, NSNumber(value: orientation)))
        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation,
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "QA Camera", kCGImagePropertyTIFFArtist: "QA Author"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2020:01:02 03:04:05", kCGImagePropertyExifLensModel: "QA Lens"],
            kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCCaptionAbstract: "QA Caption", kCGImagePropertyIPTCKeywords: ["Synthetic", "BorderMuse"]],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 0.0, kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 0.0, kCGImagePropertyGPSLongitudeRef: "E"],
            kCGImageDestinationLossyCompressionQuality: 1.0,
        ]
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil))
        CGImageDestinationAddImageAndMetadata(destination, context.makeImage()!, metadata, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
    private func image(_ url: URL) throws -> CGImage {
        try XCTUnwrap(CGImageSourceCreateImageAtIndex(XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil)), 0, nil))
    }
    private func properties(_ url: URL) throws -> [String: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
    }
    private func xmp(_ url: URL, path: String) throws -> String? {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        guard let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) else { return nil }
        return CGImageMetadataCopyStringValueWithPath(metadata, nil, path as CFString).map { $0 as String }
    }
    private func firstPixel16(_ image: CGImage) throws -> [UInt16] {
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 16, bytesPerRow: 0,
            space: image.colorSpace!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let words = context.data!.assumingMemoryBound(to: UInt16.self)
        return [words[0], words[1], words[2]]
    }
    func testFormatDepthAndProfileMatrixPreservesPixelsAndCustomXMP() throws {
        let directory = try folder()
        var count = 0
        for space in [CGColorSpace.sRGB, CGColorSpace.displayP3] {
            for (type, bits) in [("public.jpeg", 8), ("public.png", 8), ("public.png", 16), ("public.tiff", 8), ("public.tiff", 16)] {
                let input = try fixture(directory, type: type, bits: bits, space: space)
                XCTAssertEqual(try xmp(input, path: "bmqa:Marker"), marker, "Fixture must contain XMP: \(type)")
                let output = directory.appendingPathComponent("output-\(count)")
                try ImageProcessor.export(input: input, output: output, options: ImageOptions(thickness: 7, ratio: AspectRatio(width: 5, height: 4)))
                let rendered = try image(output)
                XCTAssertEqual(rendered.width, 107); XCTAssertEqual(rendered.height, 85)
                XCTAssertEqual(rendered.bitsPerComponent, bits, type)
                XCTAssertEqual(rendered.colorSpace?.name, space, type)
                XCTAssertEqual(try xmp(output, path: "bmqa:Marker"), marker, "Custom XMP lost: \(type)")
                let cropped = try XCTUnwrap(rendered.cropping(to: CGRect(x: 3, y: 9, width: 101, height: 67)))
                if bits == 16 {
                    let before = try firstPixel16(image(input)), after = try firstPixel16(cropped)
                    for (a, b) in zip(before, after) { XCTAssertLessThanOrEqual(abs(Int(a) - Int(b)), 2, "16-bit precision lost: \(type)") }
                    XCTAssertTrue(after.contains { $0 % 257 != 0 }, "Content was reduced to 8-bit precision")
                } else {
                    let before = try firstPixel16(image(input))
                    let center = try XCTUnwrap(cropped.cropping(to: CGRect(x: 50, y: 33, width: 1, height: 1)))
                    let after = try firstPixel16(center)
                    for (a, b) in zip(before, after) { XCTAssertLessThanOrEqual(abs(Int(a) - Int(b)), 514, "RGB color changed: \(type)") }
                }
                let stripped = directory.appendingPathComponent("stripped-\(count)")
                try ImageProcessor.export(input: input, output: stripped, options: ImageOptions(thickness: 7, preserveMetadata: false))
                XCTAssertNil(try xmp(stripped, path: "bmqa:Marker"))
                XCTAssertEqual(try image(stripped).colorSpace?.name, space, "ICC must survive metadata removal")
                count += 1
            }
        }
        XCTAssertEqual(count, 10)
    }
    func testCameraGPSIPTCRemovalAndNormalizedOrientationDimensions() throws {
        let directory = try folder()
        for type in ["public.jpeg", "public.tiff"] {
            let input = try fixture(directory, type: type, bits: 8, space: CGColorSpace.sRGB, orientation: 6)
            let original = try properties(input)
            XCTAssertNotNil((original[kCGImagePropertyGPSDictionary as String] as? [String: Any])?[kCGImagePropertyGPSLatitude as String], "Fixture GPS missing")
            for keep in [true, false] {
                let output = directory.appendingPathComponent(UUID().uuidString)
                try ImageProcessor.export(input: input, output: output, options: ImageOptions(thickness: 10, preserveMetadata: keep))
                let p = try properties(output)
                XCTAssertEqual(try ImageProcessor.inspect(output).orientation, 1)
                XCTAssertEqual(try image(output).width, 73); XCTAssertEqual(try image(output).height, 111)
                let exif = p[kCGImagePropertyExifDictionary as String] as? [String: Any]
                let tiff = p[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
                let iptc = p[kCGImagePropertyIPTCDictionary as String] as? [String: Any]
                let gps = p[kCGImagePropertyGPSDictionary as String] as? [String: Any]
                XCTAssertEqual(exif?[kCGImagePropertyExifPixelXDimension as String] as? Int, 73)
                XCTAssertEqual(exif?[kCGImagePropertyExifPixelYDimension as String] as? Int, 111)
                if keep {
                    XCTAssertEqual(tiff?[kCGImagePropertyTIFFMake as String] as? String, "QA Camera")
                    XCTAssertEqual(exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String, "2020:01:02 03:04:05")
                    XCTAssertEqual(iptc?[kCGImagePropertyIPTCCaptionAbstract as String] as? String, "QA Caption")
                    XCTAssertNotNil(gps?[kCGImagePropertyGPSLatitude as String])
                    XCTAssertEqual(try xmp(output, path: "tiff:Orientation"), "1")
                } else {
                    XCTAssertNil(tiff?[kCGImagePropertyTIFFMake as String])
                    XCTAssertNil(exif?[kCGImagePropertyExifDateTimeOriginal as String])
                    XCTAssertNil(iptc?[kCGImagePropertyIPTCCaptionAbstract as String])
                    XCTAssertNil(gps)
                }
            }
        }
    }
    func testJPEGQualityIsAppliedWhenPreservingXMP() throws {
        let directory = try folder()
        let input = try fixture(directory, type: "public.jpeg", bits: 8, space: CGColorSpace.sRGB, noise: true)
        let high = directory.appendingPathComponent("high.jpg"), low = directory.appendingPathComponent("low.jpg")
        try ImageProcessor.export(input: input, output: high, options: ImageOptions(jpegQuality: 1))
        try ImageProcessor.export(input: input, output: low, options: ImageOptions(jpegQuality: 0.1))
        XCTAssertGreaterThan(try Data(contentsOf: high).count, try Data(contentsOf: low).count * 2)
        XCTAssertEqual(try xmp(high, path: "bmqa:Marker"), marker)
        XCTAssertEqual(try xmp(low, path: "bmqa:Marker"), marker)
    }
    func testTransparentPNGAndTIFFCompositeOnWhiteAtEightAndSixteenBits() throws {
        let directory = try folder()
        for type in ["public.png", "public.tiff"] { for bits in [8, 16] {
            let context = try XCTUnwrap(CGContext(data: nil, width: 31, height: 21, bitsPerComponent: bits, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | (bits == 16 ? CGBitmapInfo.byteOrder16Little.rawValue : 0)))
            context.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [1, 0, 0, 1])!)
            context.fill(CGRect(x: 8, y: 5, width: 15, height: 11))
            let input = directory.appendingPathComponent(UUID().uuidString)
            let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(input as CFURL, type as CFString, 1, nil))
            CGImageDestinationAddImage(destination, context.makeImage()!, nil); XCTAssertTrue(CGImageDestinationFinalize(destination))
            let output = directory.appendingPathComponent(UUID().uuidString)
            try ImageProcessor.export(input: input, output: output, options: ImageOptions())
            let rendered = try image(output)
            XCTAssertEqual(rendered.bitsPerComponent, bits)
            XCTAssertTrue([CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(rendered.alphaInfo))
            let white = try firstPixel16(XCTUnwrap(rendered.cropping(to: CGRect(x: 1, y: 1, width: 1, height: 1))))
            XCTAssertTrue(white.allSatisfy { $0 >= 65534 })
            let red = try firstPixel16(XCTUnwrap(rendered.cropping(to: CGRect(x: 16, y: 11, width: 1, height: 1))))
            let original = try firstPixel16(XCTUnwrap(try image(input).cropping(to: CGRect(x: 15, y: 10, width: 1, height: 1))))
            for (a, b) in zip(original, red) { XCTAssertLessThanOrEqual(abs(Int(a) - Int(b)), 2, "Opaque content changed: \(type) \(bits)-bit") }
            XCTAssertGreaterThanOrEqual(red[0], 65534)
        } }
    }
    func testGrayAndCMYKBecomeProfiledRGB() throws {
        let directory = try folder()
        for space in [CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)!, CGColorSpaceCreateDeviceCMYK()] {
            let context = try XCTUnwrap(CGContext(data: nil, width: 30, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue))
            let components: [CGFloat] = space.model == .monochrome ? [0.4, 1] : [0.1, 0.2, 0.3, 0.1, 1]
            context.setFillColor(CGColor(colorSpace: space, components: components)!)
            context.fill(CGRect(x: 0, y: 0, width: 30, height: 20))
            let input = directory.appendingPathComponent(UUID().uuidString)
            let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(input as CFURL, "public.tiff" as CFString, 1, nil))
            CGImageDestinationAddImage(destination, context.makeImage()!, nil); XCTAssertTrue(CGImageDestinationFinalize(destination))
            let output = directory.appendingPathComponent(UUID().uuidString)
            try ImageProcessor.export(input: input, output: output, options: ImageOptions())
            let rendered = try image(output)
            XCTAssertEqual(rendered.colorSpace?.model, .rgb)
            XCTAssertEqual(rendered.colorSpace?.name, CGColorSpace.sRGB)
            let center = try firstPixel16(XCTUnwrap(rendered.cropping(to: CGRect(x: 15, y: 10, width: 1, height: 1))))
            XCTAssertTrue(center.allSatisfy { $0 > 100 && $0 < 65000 })
            if space.model == .monochrome { XCTAssertLessThanOrEqual(abs(Int(center[0]) - Int(center[2])), 2) }
        }
    }
}
