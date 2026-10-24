import CoreGraphics
import Foundation
import ImageIO
import BorderMuseGeometry

public enum ImageError: Error, LocalizedError {
    case unreadable, sourceChanged, unsupported, invalidOptions, allocation, writeFailed, destinationExists, sameFile
    public var errorDescription: String? {
        switch self {
        case .unreadable: return "This image could not be read."
        case .sourceChanged: return "This photo changed after it was added. Add it again or retry to use the updated file."
        case .unsupported: return "Choose a single JPEG, PNG, or TIFF image with 8-bit or 16-bit color."
        case .invalidOptions: return "Choose a positive image size and JPEG quality between 1 and 100."
        case .allocation: return "This canvas needs too much memory. Choose a smaller content size."
        case .writeFailed: return "The image could not be saved. Check the destination folder."
        case .destinationExists: return "A file with this name already exists. Choose a different name."
        case .sameFile: return "Choose an output file different from the original."
        }
    }
}

public struct ImageOptions: Equatable, Sendable {
    public var thickness: Int
    public var ratio: AspectRatio?
    public var longEdge: Int?
    public var jpegQuality: Double
    public var preserveMetadata: Bool
    public init(thickness: Int = 10, ratio: AspectRatio? = nil, longEdge: Int? = nil,
                jpegQuality: Double = 0.95, preserveMetadata: Bool = true) {
        self.thickness = thickness; self.ratio = ratio; self.longEdge = longEdge
        self.jpegQuality = jpegQuality; self.preserveMetadata = preserveMetadata
    }
}

/// A fresh filesystem identity check, independent of URL resource-value caches.
/// This detects ordinary edits/replacements; it is not a content checksum.
public struct ImageFileVersion: Hashable, Sendable {
    let size: UInt64
    let modified: Date
    let inode: UInt64
    let device: UInt64

    public static func read(_ url: URL) throws -> Self {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              let modified = attributes[.modificationDate] as? Date,
              let inode = attributes[.systemFileNumber] as? NSNumber,
              let device = attributes[.systemNumber] as? NSNumber else { throw ImageError.unreadable }
        return Self(size: size.uint64Value, modified: modified, inode: inode.uint64Value, device: device.uint64Value)
    }
    public func validate(_ url: URL) throws {
        guard try Self.read(url) == self else { throw ImageError.sourceChanged }
    }
}

public struct ImageInfo: Sendable {
    public let size: PixelSize
    public let bitsPerComponent: Int
    public let orientation: Int
    public let typeIdentifier: String
    public let version: ImageFileVersion
}

public enum ImageProcessor {
    private static let formats: Set<String> = ["public.jpeg", "public.png", "public.tiff"]
    private static let maximumWorkingBytes = 1_073_741_824

    public static func inspect(_ url: URL) throws -> ImageInfo {
        let version = try ImageFileVersion.read(url)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let uti = CGImageSourceGetType(source) else { throw ImageError.unreadable }
        guard formats.contains(uti as String), CGImageSourceGetCount(source) == 1 else { throw ImageError.unsupported }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let w = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let h = properties[kCGImagePropertyPixelHeight as String] as? Int else { throw ImageError.unreadable }
        let orientation = properties[kCGImagePropertyOrientation as String] as? Int ?? 1
        guard (1...8).contains(orientation) else { throw ImageError.unsupported }
        let size = try PixelSize(width: orientation >= 5 ? h : w, height: orientation >= 5 ? w : h)
        let bits = properties[kCGImagePropertyDepth as String] as? Int ?? 8
        guard bits == 8 || bits == 16,
              properties[kCGImagePropertyIsFloat as String] as? Bool != true else { throw ImageError.unsupported }
        // HDR gain maps need an explicit color pipeline; do not silently discard them.
        guard CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeHDRGainMap) == nil else { throw ImageError.unsupported }
        if #available(macOS 15, *) {
            guard CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeISOGainMap) == nil else { throw ImageError.unsupported }
        }
        try version.validate(url)
        return ImageInfo(size: size, bitsPerComponent: bits, orientation: orientation, typeIdentifier: uti as String, version: version)
    }

    public static func preview(_ url: URL, maximumPixelSize: Int = 1400, expectedVersion: ImageFileVersion? = nil) throws -> CGImage {
        let info = try inspect(url)
        if let expectedVersion, expectedVersion != info.version { throw ImageError.sourceChanged }
        guard maximumPixelSize > 0,
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else { throw ImageError.unreadable }
        try info.version.validate(url)
        return image
    }

    public static func layout(for info: ImageInfo, options: ImageOptions) throws -> CanvasLayout {
        try CanvasLayout.calculate(content: info.size.reduced(longEdge: options.longEdge),
                                   thickness: options.thickness, ratio: options.ratio)
    }

    public static func export(input: URL, output: URL, options: ImageOptions, expectedVersion: ImageFileVersion? = nil) throws {
        guard input.standardizedFileURL != output.standardizedFileURL else { throw ImageError.sameFile }
        guard !FileManager.default.fileExists(atPath: output.path) else { throw ImageError.destinationExists }
        guard options.jpegQuality.isFinite, (0.01...1).contains(options.jpegQuality),
              options.longEdge == nil || options.longEdge! > 0 else { throw ImageError.invalidOptions }
        let info = try inspect(input)
        if let expectedVersion, expectedVersion != info.version { throw ImageError.sourceChanged }
        let content = try info.size.reduced(longEdge: options.longEdge)
        let layout = try layout(for: info, options: options)
        let bytesPerPixel = info.bitsPerComponent == 16 ? 8 : 4
        let (pixels, pixelOverflow) = layout.width.multipliedReportingOverflow(by: layout.height)
        let (bytes, byteOverflow) = pixels.multipliedReportingOverflow(by: bytesPerPixel)
        let (sourcePixels, sourceOverflow) = info.size.width.multipliedReportingOverflow(by: info.size.height)
        let (sourceBytes, sourceByteOverflow) = sourcePixels.multipliedReportingOverflow(by: bytesPerPixel)
        let (workingBytes, workingOverflow) = bytes.addingReportingOverflow(sourceBytes)
        guard !pixelOverflow, !byteOverflow, !sourceOverflow, !sourceByteOverflow, !workingOverflow,
              workingBytes <= maximumWorkingBytes else { throw ImageError.allocation }
        try Task.checkCancellation()
        let temp = output.deletingLastPathComponent().appendingPathComponent(".bordermuse-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temp) }

        // Keep unchanged originals byte-identical when no processing is requested.
        if options.thickness == 0, options.ratio == nil, content == info.size, options.preserveMetadata {
            try FileManager.default.copyItem(at: input, to: temp)
        } else {
            let prepared = try prepare(input: input, info: info, content: content, layout: layout, options: options)
            let rendered = prepared.image
            guard let destination = CGImageDestinationCreateWithURL(temp as CFURL, info.typeIdentifier as CFString, 1, nil) else { throw ImageError.writeFailed }
            var properties = prepared.properties
            properties[kCGImagePropertyOrientation as String] = 1
            properties[kCGImagePropertyPixelWidth as String] = layout.width
            properties[kCGImagePropertyPixelHeight as String] = layout.height
            var exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
            exif[kCGImagePropertyExifPixelXDimension as String] = layout.width
            exif[kCGImagePropertyExifPixelYDimension as String] = layout.height
            properties[kCGImagePropertyExifDictionary as String] = exif
            if var tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
                tiff[kCGImagePropertyTIFFOrientation as String] = 1
                properties[kCGImagePropertyTIFFDictionary as String] = tiff
            }
            properties[kCGImageDestinationLossyCompressionQuality as String] = options.jpegQuality
            if let metadata = prepared.metadata {
                // CopyProperties alone drops unrecognized XMP namespaces. Keep the
                // complete embedded packet, normalizing tags affected by rendering.
                let normalized: [(CFString, CFString, NSNumber)] = [
                    (kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFOrientation, NSNumber(value: 1)),
                    (kCGImagePropertyExifDictionary, kCGImagePropertyExifPixelXDimension, NSNumber(value: layout.width)),
                    (kCGImagePropertyExifDictionary, kCGImagePropertyExifPixelYDimension, NSNumber(value: layout.height)),
                ]
                for (dictionary, property, value) in normalized {
                    guard CGImageMetadataSetValueMatchingImageProperty(metadata, dictionary, property, value) else { throw ImageError.writeFailed }
                }
                for (path, value) in [("tiff:ImageWidth", layout.width), ("tiff:ImageLength", layout.height)] {
                    guard CGImageMetadataSetValueWithPath(metadata, nil, path as CFString, NSNumber(value: value)) else { throw ImageError.writeFailed }
                }
                // Embedded thumbnails describe the old unframed image.
                CGImageMetadataRemoveTagWithPath(metadata, nil, "xmp:Thumbnails" as CFString)
                CGImageDestinationAddImageAndMetadata(destination, rendered, metadata, properties as CFDictionary)
            } else {
                CGImageDestinationAddImage(destination, rendered, properties as CFDictionary)
            }
            guard CGImageDestinationFinalize(destination) else { throw ImageError.writeFailed }
        }
        try Task.checkCancellation()
        try info.version.validate(input)
        // Move is atomic on this volume and refuses to overwrite a racing writer.
        do { try FileManager.default.moveItem(at: temp, to: output) }
        catch {
            if FileManager.default.fileExists(atPath: output.path) { throw ImageError.destinationExists }
            throw ImageError.writeFailed
        }
    }

    private struct PreparedImage {
        let image: CGImage
        let properties: [String: Any]
        let metadata: CGMutableImageMetadata?
    }

    /// Release the decoder and source pixels before the encoder allocates buffers.
    private static func prepare(input: URL, info: ImageInfo, content: PixelSize,
                                layout: CanvasLayout, options: ImageOptions) throws -> PreparedImage {
        try autoreleasepool {
            try Task.checkCancellation()
            guard let source = CGImageSourceCreateWithURL(input as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw ImageError.unreadable }
            let bits = image.bitsPerComponent
            guard bits == 8 || bits == 16 else { throw ImageError.unsupported }
            let colorSpace = image.colorSpace?.model == .rgb ? image.colorSpace! : CGColorSpace(name: CGColorSpace.sRGB)!
            let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue | (bits == 16 ? CGBitmapInfo.byteOrder16Little.rawValue : 0)
            guard let context = CGContext(data: nil, width: layout.width, height: layout.height,
                                          bitsPerComponent: bits, bytesPerRow: 0,
                                          space: colorSpace, bitmapInfo: bitmapInfo) else { throw ImageError.allocation }
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: layout.width, height: layout.height))
            context.interpolationQuality = .high
            context.translateBy(x: CGFloat(layout.left), y: CGFloat(layout.bottom))
            context.scaleBy(x: CGFloat(content.width) / CGFloat(info.size.width), y: CGFloat(content.height) / CGFloat(info.size.height))
            context.concatenate(orientationTransform(info.orientation, width: image.width, height: image.height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            try Task.checkCancellation()
            guard let rendered = context.makeImage() else { throw ImageError.allocation }
            let properties = options.preserveMetadata ? (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]) : [:]
            let metadata: CGMutableImageMetadata?
            if options.preserveMetadata, let original = CGImageSourceCopyMetadataAtIndex(source, 0, nil) {
                metadata = CGImageMetadataCreateMutableCopy(original)
            } else { metadata = nil }
            return PreparedImage(image: rendered, properties: properties, metadata: metadata)
        }
    }

    private static func orientationTransform(_ orientation: Int, width: Int, height: Int) -> CGAffineTransform {
        let w = CGFloat(width), h = CGFloat(height)
        switch orientation {
        case 2: return CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0)
        case 3: return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h)
        case 4: return CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h)
        case 5: return CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: h, ty: w)
        case 6: return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w)
        case 7: return CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        case 8: return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0)
        default: return .identity
        }
    }
}

/// Render an image using explicit file paths and border geometry options.
public func processImage(inputURL: URL, outputURL: URL, borderPercent: Int, aspectRatio: String) throws {
    try ImageProcessor.export(input: inputURL, output: outputURL,
                              options: ImageOptions(thickness: borderPercent, ratio: AspectRatio.parse(aspectRatio)))
}
