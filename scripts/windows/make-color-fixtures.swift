import CoreGraphics
import Foundation
import ImageIO

// Synthetic cross-platform codec evidence, generated on macOS and consumed by
// Windows CI. No photographs, camera identifiers or real location data.
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for (profile, space) in [("sRGB", CGColorSpace.sRGB), ("P3", CGColorSpace.displayP3)] {
    for (format, uti, bits) in [("jpg", "public.jpeg", 8), ("png", "public.png", 8), ("png", "public.png", 16), ("tiff", "public.tiff", 8), ("tiff", "public.tiff", 16)] {
        let context = CGContext(data: nil, width: 101, height: 67, bitsPerComponent: bits, bytesPerRow: 0,
            space: CGColorSpace(name: space)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | (bits == 16 ? CGBitmapInfo.byteOrder16Little.rawValue : 0))!
        if bits == 16 {
            let words = context.data!.assumingMemoryBound(to: UInt16.self)
            for y in 0..<67 { for x in 0..<101 {
                let i = y * context.bytesPerRow / 2 + x * 4
                words[i] = 10001; words[i+1] = 30002; words[i+2] = 50003; words[i+3] = 65535
            } }
        } else {
            context.setFillColor(CGColor(red: 0.15, green: 0.4, blue: 0.65, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 101, height: 67))
        }
        let metadata = CGImageMetadataCreateMutable()
        var error: Unmanaged<CFError>?
        precondition(CGImageMetadataRegisterNamespaceForPrefix(metadata, "https://example.invalid/bordermuse/qa/1.0/" as CFString, "bmqa" as CFString, &error))
        precondition(CGImageMetadataSetValueWithPath(metadata, nil, "bmqa:Marker" as CFString, "Synthetic BorderMuse metadata" as CFString))
        for (namespace, prefix) in [("http://ns.adobe.com/tiff/1.0/", "tiff"), ("http://ns.adobe.com/exif/1.0/", "exif")] {
            precondition(CGImageMetadataRegisterNamespaceForPrefix(metadata, namespace as CFString, prefix as CFString, &error))
        }
        for (path, value) in [("tiff:Orientation", 6), ("tiff:ImageWidth", 101), ("tiff:ImageLength", 67), ("exif:PixelXDimension", 101), ("exif:PixelYDimension", 67)] {
            precondition(CGImageMetadataSetValueWithPath(metadata, nil, path as CFString, NSNumber(value: value)))
        }
        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "QA Camera", kCGImagePropertyTIFFArtist: "QA Author"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2020:01:02 03:04:05", kCGImagePropertyExifLensModel: "QA Lens"],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 0.0, kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 0.0, kCGImagePropertyGPSLongitudeRef: "E"],
            kCGImageDestinationLossyCompressionQuality: 1.0,
        ]
        let path = folder.appendingPathComponent("\(profile)-\(bits).\(format)")
        let destination = CGImageDestinationCreateWithURL(path as CFURL, uti as CFString, 1, nil)!
        CGImageDestinationAddImageAndMetadata(destination, context.makeImage()!, metadata, properties as CFDictionary)
        precondition(CGImageDestinationFinalize(destination))
    }
}
