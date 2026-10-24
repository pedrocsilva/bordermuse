import CoreGraphics
import Foundation
import BorderMuseImaging

struct Photo: Identifiable, Sendable {
    let id: UUID
    let url: URL
    let info: ImageInfo
    let canonicalURL: URL
}

actor PhotoLoader {
    private final class CachedImage: NSObject {
        let image: CGImage
        let version: ImageFileVersion
        init(_ image: CGImage, version: ImageFileVersion) { self.image = image; self.version = version }
    }
    private let thumbnails: NSCache<NSURL, CachedImage> = {
        let cache = NSCache<NSURL, CachedImage>()
        cache.totalCostLimit = 32 * 1024 * 1024
        cache.countLimit = 200
        return cache
    }()
    func load(_ url: URL, id: UUID = UUID()) throws -> Photo {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try autoreleasepool {
            try Task.checkCancellation()
            return try Photo(id: id, url: url, info: ImageProcessor.inspect(url), canonicalURL: url.resolvingSymlinksInPath().standardizedFileURL)
        }
    }
    func thumbnail(_ url: URL) throws -> PreviewImage {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try autoreleasepool {
            try Task.checkCancellation()
            let version = try ImageFileVersion.read(url)
            if let cached = thumbnails.object(forKey: url as NSURL), cached.version == version { return PreviewImage(image: cached.image) }
            let image = try ImageProcessor.preview(url, maximumPixelSize: 240, expectedVersion: version)
            thumbnails.setObject(CachedImage(image, version: version), forKey: url as NSURL, cost: image.bytesPerRow * image.height)
            return PreviewImage(image: image)
        }
    }
    func preview(_ url: URL, expectedVersion: ImageFileVersion? = nil) throws -> PreviewImage {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try autoreleasepool {
            try Task.checkCancellation()
            return try PreviewImage(image: ImageProcessor.preview(url, maximumPixelSize: 1600, expectedVersion: expectedVersion))
        }
    }
}
struct PreviewImage: @unchecked Sendable { let image: CGImage }
