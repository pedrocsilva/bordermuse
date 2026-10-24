import Foundation
import BorderMuseImaging
import BorderMuseGeometry

struct PhotoIssue: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let message: String
    let canRetry: Bool
}
struct ExportResult: Sendable {
    var outputs: [URL] = []
    var issues: [PhotoIssue] = []
    var canceled = false
}

actor ExportWorker {
    func run(photos: [Photo], folder: URL, options: ImageOptions,
             progress: @MainActor @Sendable (Int) async -> Void) async -> ExportResult {
        let folderAccess = folder.startAccessingSecurityScopedResource()
        defer { if folderAccess { folder.stopAccessingSecurityScopedResource() } }
        var result = ExportResult()
        for (index, photo) in photos.enumerated() {
            if Task.isCancelled { result.canceled = true; break }
            await progress(index + 1)
            let access = photo.url.startAccessingSecurityScopedResource()
            defer { if access { photo.url.stopAccessingSecurityScopedResource() } }
            do {
                let output = try autoreleasepool { () throws -> URL in
                    var number = 1
                    while true {
                        try Task.checkCancellation()
                        let suffix = number == 1 ? "-border" : "-border-\(number)"
                        let output = folder.appendingPathComponent(photo.url.deletingPathExtension().lastPathComponent + suffix)
                            .appendingPathExtension(photo.url.pathExtension)
                        if FileManager.default.fileExists(atPath: output.path) { number += 1; continue }
                        do { try ImageProcessor.export(input: photo.url, output: output, options: options, expectedVersion: photo.info.version); return output }
                        catch ImageError.destinationExists { number += 1 }
                    }
                }
                result.outputs.append(output)
            } catch is CancellationError { result.canceled = true; break }
            catch {
                result.issues.append(PhotoIssue(url: photo.url, message: Self.message(error), canRetry: true))
            }
        }
        return result
    }
    nonisolated static func message(_ error: Error, importing: Bool = false) -> String {
        if let error = error as? ImageError { return error.localizedDescription }
        if let error = error as? BorderMuseGeometry.GeometryError { return error.localizedDescription }
        return Strings.text(importing ? "genericImportError" : "genericExportError")
    }
}
