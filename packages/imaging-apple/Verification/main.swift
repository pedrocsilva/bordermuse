import CoreGraphics
import Foundation
import ImageIO
import BorderMuseGeometry
import BorderMuseImaging

struct VerificationFailure: Error, CustomStringConvertible { let description: String }
func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw VerificationFailure(description: message) }
}
struct Corpus: Decodable {
    struct Case: Decodable {
        struct Input: Decodable { let width: Int; let height: Int; let thickness: Int; let ratio: [Int] }
        let source_file: String; let input: Input; let expected: CanvasLayout
    }
    let spec_id: String; let cases: [Case]
}
let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: root.appendingPathComponent("geometry/conformance-v1.json")))
try require(corpus.spec_id == CanvasLayout.contractID && corpus.cases.count == 20, "Wrong conformance corpus")
for item in corpus.cases {
    let actual = try CanvasLayout.calculate(content: PixelSize(width: item.input.width, height: item.input.height), thickness: item.input.thickness,
                                          ratio: AspectRatio(width: item.input.ratio[0], height: item.input.ratio[1]))
    try require(actual == item.expected, "Conformance failed: \(item.source_file)")
}
try require(CanvasLayout.calculate(content: PixelSize(width: 100, height: 100), thickness: 14, ratio: nil).left == 7, "Exact boundary failed")
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("bordermuse-verify-\(UUID())")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }

func fixture(_ name: String, type: String = "public.tiff", orientation: Int = 1, bits: Int = 8) throws -> URL {
    let url = directory.appendingPathComponent(name)
    let space = CGColorSpace(name: CGColorSpace.displayP3)!
    let context = CGContext(data: nil, width: 60, height: 40, bitsPerComponent: bits, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | (bits == 16 ? CGBitmapInfo.byteOrder16Little.rawValue : 0))!
    let colors: [CGColor] = [CGColor(red: 1, green: 0, blue: 0, alpha: 1), CGColor(red: 0, green: 1, blue: 0, alpha: 1),
                             CGColor(red: 0, green: 0, blue: 1, alpha: 1), CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)]
    for index in 0..<4 {
        context.setFillColor(colors[index]); context.fill(CGRect(x: (index % 2) * 30, y: (index / 2) * 20, width: 30, height: 20))
    }
    let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImagePropertyOrientation: orientation,
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFArtist: "BorderMuse test"]] as CFDictionary)
    try require(CGImageDestinationFinalize(destination), "Could not create fixture")
    return url
}

// Compare oriented pixels with ImageIO's independent orientation implementation.
func pixels(_ image: CGImage) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    bytes.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return bytes
}
for orientation in 1...8 {
    let input = try fixture("orientation-\(orientation).tiff", orientation: orientation)
    let output = directory.appendingPathComponent("oriented-\(orientation).tiff")
    let expected = try ImageProcessor.preview(input, maximumPixelSize: 60)
    // Force decoding, bypassing the lossless no-op path.
    try ImageProcessor.export(input: input, output: output, options: ImageOptions(thickness: 0, preserveMetadata: false))
    let actual = try ImageProcessor.preview(output, maximumPixelSize: 60)
    try require(actual.width == expected.width && actual.height == expected.height, "Orientation dimensions \(orientation)")
    let a = pixels(actual), b = pixels(expected)
    let maximumDifference = zip(a.enumerated().filter { $0.offset % 4 != 3 }.map(\.element),
                                b.enumerated().filter { $0.offset % 4 != 3 }.map(\.element)).map { abs(Int($0)-Int($1)) }.max() ?? 0
    try require(maximumDifference <= 2, "Orientation pixels \(orientation), difference \(maximumDifference)")
}
for (type, suffix, bits) in [("public.jpeg", "jpg", 8), ("public.png", "png", 8), ("public.tiff", "tiff", 16)] {
    let input = try fixture("source.\(suffix)", type: type, bits: bits)
    let output = directory.appendingPathComponent("border.\(suffix)")
    try ImageProcessor.export(input: input, output: output, options: ImageOptions(thickness: 10, ratio: AspectRatio(width: 1, height: 1)))
    let info = try ImageProcessor.inspect(output)
    try require(info.size.width == 66 && info.size.height == 66 && info.bitsPerComponent == bits, "Dimensions/depth: \(suffix)")
    let source = CGImageSourceCreateWithURL(output as CFURL, nil)!
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
    let artist = (properties[kCGImagePropertyTIFFDictionary] as? NSDictionary)?[kCGImagePropertyTIFFArtist] as? String
    if type == "public.tiff" { try require(artist == "BorderMuse test", "TIFF metadata") }
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    try require(image.colorSpace?.name == CGColorSpace.displayP3, "Display P3 profile: \(suffix)")
    let bytes = pixels(image)
    let whiteTolerance: UInt8 = type == "public.jpeg" ? 245 : 254
    try require(bytes[0] >= whiteTolerance && bytes[1] >= whiteTolerance && bytes[2] >= whiteTolerance, "White canvas: \(suffix) \(Array(bytes.prefix(3)))")
    do {
        try ImageProcessor.export(input: input, output: output, options: ImageOptions())
        throw VerificationFailure(description: "Existing file overwritten")
    } catch ImageError.destinationExists { }
    let copy = directory.appendingPathComponent("copy.\(suffix)")
    try ImageProcessor.export(input: input, output: copy, options: ImageOptions(thickness: 0))
    try require(Data(contentsOf: input) == Data(contentsOf: copy), "No-op bytes changed")
    let reduced = directory.appendingPathComponent("reduced.\(suffix)")
    try ImageProcessor.export(input: input, output: reduced, options: ImageOptions(thickness: 10, longEdge: 30))
    try require(ImageProcessor.inspect(reduced).size == PixelSize(width: 32, height: 22), "Reduced content geometry")
}
print("PASS: 20 measured geometry cases; exact boundary; all 8 EXIF orientations; JPEG/PNG/TIFF; 16-bit TIFF; P3; metadata; resize; white fill; no-op; overwrite protection.")
