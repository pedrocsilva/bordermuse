import CoreGraphics
import Foundation
import ImageIO

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for (name, width, height, bits, type) in [
    ("source.jpg", 6000, 4000, 8, "public.jpeg"),
    ("source.png", 4000, 3000, 8, "public.png"),
    ("source.tiff", 6000, 4000, 16, "public.tiff"),
] {
    let url = folder.appendingPathComponent(name)
    if FileManager.default.fileExists(atPath: url.path) { continue }
    try autoreleasepool {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: bits, bytesPerRow: 0,
            space: CGColorSpace(name: bits == 16 ? CGColorSpace.displayP3 : CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | (bits == 16 ? CGBitmapInfo.byteOrder16Little.rawValue : 0))!
        for y in stride(from: 0, to: height, by: 64) {
            context.setFillColor(CGColor(red: CGFloat(y % 255) / 255, green: 0.4, blue: CGFloat((y * 3) % 255) / 255, alpha: 1))
            context.fill(CGRect(x: 0, y: y, width: width, height: min(64, height - y)))
        }
        let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
