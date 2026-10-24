import CoreGraphics
import Foundation
import ImageIO
import XCTest
import BorderMuseImaging
@testable import BorderMuse

final class SessionTests: XCTestCase {
    @MainActor
    private func idle(_ session: PhotoSession, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while session.isImporting || session.isExporting {
            guard ContinuousClock.now < deadline else { XCTFail("Session did not become idle", file: file, line: line); return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    @MainActor
    func testSessionDeduplicatesImportsAndQueuesFinderOpeningDuringExport() async throws {
        let directory = try folder()
        let a = try fixture(directory)
        let b = directory.appendingPathComponent("second.png")
        try FileManager.default.copyItem(at: a, to: b)
        let session = PhotoSession(store: PresetStore(url: directory.appendingPathComponent("presets.json")))
        session.importPhotos([a, a, a])
        try await idle(session)
        XCTAssertEqual(session.photos.count, 1)
        XCTAssertNotNil(session.layout)
        session.settings.ratio = "1:1"
        session.export(session.photos, to: directory)
        session.importPhotos([b])
        try await idle(session)
        XCTAssertEqual(session.photos.count, 2)
        XCTAssertEqual(session.result?.outputs.count, 1)
        XCTAssertTrue(session.issues.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("photo-border.png").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("second-border.png").path))
        session.clear()
        XCTAssertTrue(session.photos.isEmpty); XCTAssertNil(session.preview); XCTAssertNil(session.selectedID)
    }
    @MainActor
    func testSessionCancellationAndMissingInputHaveUsableTerminalStates() async throws {
        let directory = try folder()
        let input = try fixture(directory)
        let session = PhotoSession(store: PresetStore(url: directory.appendingPathComponent("presets.json")))
        session.importPhotos([input]); try await idle(session)
        session.export(session.photos, to: directory); session.cancelExport()
        try await idle(session)
        XCTAssertEqual(session.result?.canceled, true)
        XCTAssertTrue(session.canExport)
        try FileManager.default.removeItem(at: input)
        session.export(session.photos, to: directory)
        try await idle(session)
        XCTAssertEqual(session.issues.count, 1)
        XCTAssertTrue(session.issues[0].canRetry)
        XCTAssertEqual(session.result?.outputs.count, 0)
        XCTAssertTrue(session.canExport)
    }
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func fixture(_ directory: URL, name: String = "photo.png", width: Int = 100, height: Int = 80,
                         bits: Int = 8, type: String = "public.png") throws -> URL {
        let url = directory.appendingPathComponent(name)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: bits, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | (bits == 16 ? CGBitmapInfo.byteOrder16Little.rawValue : 0))!
        context.setFillColor(CGColor(colorSpace: context.colorSpace!, components: [0.25, 0.5, 0.75, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
    func testVersionedPresetsAndInvalidSettings() throws {
        let store = PresetStore(url: try folder().appendingPathComponent("presets.json"))
        XCTAssertTrue(store.load().isEmpty)
        let preset = Preset(id: UUID(), name: "Square", settings: BorderSettings(ratio: "1:1"))
        try store.save([preset]); XCTAssertEqual(store.load(), [preset])
        var settings = BorderSettings(); settings.thickness = 51
        XCTAssertThrowsError(try settings.options)
        try Data("{\"version\":2}".utf8).write(to: store.url)
        XCTAssertTrue(store.load().isEmpty)
    }
    func testBatchNeverOverwritesAndKeepsSuccessesOnPartialFailure() async throws {
        let directory = try folder()
        let input = try fixture(directory)
        let photo = try await PhotoLoader().load(input)
        let options = try BorderSettings().options
        let worker = ExportWorker()
        let first = await worker.run(photos: [photo], folder: directory, options: options) { _ in }
        let saved = try XCTUnwrap(first.outputs.first)
        let data = try Data(contentsOf: saved)
        let second = await worker.run(photos: [photo, photo], folder: directory, options: options) { _ in }
        XCTAssertEqual(second.outputs.count, 2)
        XCTAssertEqual(Set(first.outputs + second.outputs).count, 3)
        XCTAssertEqual(try Data(contentsOf: saved), data)
        let missing = directory.appendingPathComponent("missing.png")
        try FileManager.default.copyItem(at: input, to: missing)
        let missingPhoto = try await PhotoLoader().load(missing)
        try FileManager.default.removeItem(at: missing)
        let partial = await worker.run(photos: [photo, missingPhoto], folder: directory, options: options) { _ in }
        XCTAssertEqual(partial.outputs.count, 1); XCTAssertEqual(partial.issues.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: partial.outputs[0].path))
        try FileManager.default.removeItem(at: input)
        let failure = await worker.run(photos: [photo], folder: directory, options: options) { _ in }
        XCTAssertEqual(failure.issues.count, 1); XCTAssertTrue(failure.outputs.isEmpty)
        XCTAssertEqual(try Data(contentsOf: saved), data)
    }
    func testCancellationLeavesNoTemporaryFiles() async throws {
        let directory = try folder()
        let photo = try await PhotoLoader().load(fixture(directory))
        let options = try BorderSettings().options
        let task = Task {
            // Cancellation is already set before the serial worker begins.
            withUnsafeCurrentTask { $0?.cancel() }
            return await ExportWorker().run(photos: [photo], folder: directory, options: options) { _ in }
        }
        let result = await task.value
        XCTAssertTrue(result.canceled); XCTAssertTrue(result.outputs.isEmpty)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasPrefix(".bordermuse-") })
    }
    func testMidBatchCancellationPreservesCompletedOutput() async throws {
        let directory = try folder()
        let photo = try await PhotoLoader().load(fixture(directory))
        let options = try BorderSettings().options
        let result = await Task {
            await ExportWorker().run(photos: [photo, photo], folder: directory, options: options) { index in
                if index == 2 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }.value
        XCTAssertTrue(result.canceled); XCTAssertEqual(result.outputs.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputs[0].path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasPrefix(".bordermuse-") })
    }

    @MainActor
    func testChangedSourceIsRejectedAndReimportRefreshesDimensionsAndThumbnail() async throws {
        let directory = try folder()
        let input = try fixture(directory)
        let session = PhotoSession(store: PresetStore(url: directory.appendingPathComponent("presets.json")))
        session.importPhotos([input]); try await idle(session)
        let original = try XCTUnwrap(session.selected)
        let thumbnail = try await session.loader.thumbnail(input)
        XCTAssertEqual(thumbnail.image.width, 100)
        let replacement = try fixture(directory, name: "replacement.png", width: 60, height: 120)
        try Data(contentsOf: replacement).write(to: input, options: .atomic)
        XCTAssertThrowsError(try ImageProcessor.preview(input, expectedVersion: original.info.version)) {
            guard case ImageError.sourceChanged = $0 else { return XCTFail("Unexpected error: \($0)") }
        }
        session.export(session.photos, to: directory); try await idle(session)
        XCTAssertEqual(session.result?.outputs.count, 0)
        XCTAssertEqual(session.issues.first?.message, ImageError.sourceChanged.localizedDescription)
        session.importPhotos([input]); try await idle(session)
        XCTAssertEqual(session.photos.count, 1)
        XCTAssertEqual(session.selectedID, original.id)
        XCTAssertEqual(session.selected?.info.size.width, 60)
        XCTAssertEqual(session.selected?.info.size.height, 120)
        let updated = try await session.loader.thumbnail(input)
        XCTAssertEqual(updated.image.width, 60); XCTAssertEqual(updated.image.height, 120)
        session.export(session.photos, to: directory); try await idle(session)
        XCTAssertEqual(session.result?.outputs.count, 1)
    }

    @MainActor
    func testRetryRefreshesRestoredInputBeforeExporting() async throws {
        let directory = try folder()
        let input = try fixture(directory)
        let session = PhotoSession(store: PresetStore(url: directory.appendingPathComponent("presets.json")))
        session.importPhotos([input]); try await idle(session)
        let id = session.selectedID
        try FileManager.default.removeItem(at: input)
        session.export(session.photos, to: directory); try await idle(session)
        XCTAssertEqual(session.result?.issues.count, 1)
        _ = try fixture(directory, width: 51, height: 91)
        session.export(session.photos, to: directory, refresh: true); try await idle(session)
        XCTAssertEqual(session.result?.outputs.count, 1)
        XCTAssertTrue(session.issues.isEmpty)
        XCTAssertEqual(session.selectedID, id)
        XCTAssertEqual(session.selected?.info.size.width, 51)
        let output = try XCTUnwrap(session.result?.outputs.first)
        let info = try ImageProcessor.inspect(output)
        XCTAssertEqual(info.size.width, 55); XCTAssertEqual(info.size.height, 99)
    }

    func testDeniedInputAndDestinationLeaveOriginalAndCompletedFilesIntact() async throws {
        let directory = try folder()
        let input = try fixture(directory)
        let original = try Data(contentsOf: input)
        let photo = try await PhotoLoader().load(input)
        let worker = ExportWorker()
        let options = try BorderSettings().options
        let destination = directory.appendingPathComponent("read-only", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: destination.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path) }
        let deniedWrite = await worker.run(photos: [photo], folder: destination, options: options) { _ in }
        XCTAssertTrue(deniedWrite.outputs.isEmpty); XCTAssertEqual(deniedWrite.issues.count, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), [])
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: input.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: input.path) }
        let deniedRead = await worker.run(photos: [photo], folder: directory, options: options) { _ in }
        XCTAssertTrue(deniedRead.outputs.isEmpty); XCTAssertEqual(deniedRead.issues.count, 1)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: input.path)
        XCTAssertEqual(try Data(contentsOf: input), original)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasPrefix(".bordermuse-") })
    }

    @MainActor
    func testQuitCancellationWaitsForActiveTemporaryWriteCleanup() async throws {
        let directory = try folder()
        let input = try autoreleasepool { try fixture(directory, name: "large.tiff", width: 2048, height: 1536, bits: 16, type: "public.tiff") }
        let session = PhotoSession(store: PresetStore(url: directory.appendingPathComponent("presets.json")))
        session.importPhotos([input]); try await idle(session)
        let photo = try XCTUnwrap(session.selected)
        session.export(Array(repeating: photo, count: 20), to: directory)
        let deadline = ContinuousClock.now + .seconds(10)
        var observedTemporaryWrite = false
        while session.isExporting && ContinuousClock.now < deadline {
            if try FileManager.default.contentsOfDirectory(atPath: directory.path).contains(where: { $0.hasPrefix(".bordermuse-") }) {
                observedTemporaryWrite = true; break
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertTrue(observedTemporaryWrite, "Cancel must interrupt an active write, not just a queued batch")
        await session.cancelExportAndWait()
        XCTAssertFalse(session.isExporting)
        XCTAssertEqual(session.result?.canceled, true)
        XCTAssertLessThan(session.result?.outputs.count ?? 20, 20)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasPrefix(".bordermuse-") })
        for output in session.result?.outputs ?? [] { XCTAssertNoThrow(try ImageProcessor.inspect(output)) }
        XCTAssertNoThrow(try ImageProcessor.inspect(input))
    }

}
