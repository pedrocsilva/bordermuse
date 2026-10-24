import CoreGraphics
import Foundation
import ImageIO

let folder = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/qa/fixtures")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for (name, width, height) in [("landscape.png", 1000, 800), ("portrait.png", 801, 1201), ("square.png", 900, 900)] {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(red: 0.15, green: 0.35, blue: 0.55, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(red: 0.3, green: 0.6, blue: 0.6, alpha: 1))
    context.fill(CGRect(x: 0, y: height / 2, width: width, height: height / 2))
    context.setFillColor(CGColor(red: 0.85, green: 0.4, blue: 0.15, alpha: 1))
    context.fillEllipse(in: CGRect(x: width / 6, y: height / 3, width: width / 2, height: height / 2))
    let destination = CGImageDestinationCreateWithURL(folder.appendingPathComponent(name) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Fixture could not be written") }
}
print(folder.path)
