import AppKit
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import SwiftUI
import XCTest
@testable import BorderMuse

/// Opt-in, reproducible measurement of the real session, preview decoder and
/// serial exporter. This measures component latency/RSS, not display frame rate.
@MainActor
final class PerformanceBenchmarks: XCTestCase {
    private func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
    private func rss() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : -1
    }
    private func peakRSS() -> Double {
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_maxrss) / 1_048_576 // Darwin reports bytes.
    }
    private func idle(_ session: PhotoSession) async throws {
        let deadline = ContinuousClock.now + .seconds(120)
        while session.isImporting || session.isExporting {
            guard ContinuousClock.now < deadline else { XCTFail("Benchmark timed out"); throw CancellationError() }
            try await Task.sleep(for: .milliseconds(2))
        }
    }
    func testRealBatchResourceUsage() async throws {
        guard ProcessInfo.processInfo.environment["BORDERMUSE_BENCHMARK"] == "1" else {
            throw XCTSkip("Opt-in resource benchmark: run scripts/macos/benchmark.sh")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bordermuse-bench-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixtures = try XCTUnwrap(ProcessInfo.processInfo.environment["BORDERMUSE_BENCHMARK_FIXTURES"], "Use scripts/macos/benchmark.sh")
        let directory = URL(fileURLWithPath: fixtures)
        let jpeg = directory.appendingPathComponent("source.jpg")
        let png = directory.appendingPathComponent("source.png")
        let tiff = directory.appendingPathComponent("source.tiff")
        var urls: [URL] = []
        for index in 0..<400 {
            let url = root.appendingPathComponent("photo-\(index).jpg")
            try FileManager.default.linkItem(at: jpeg, to: url); urls.append(url)
        }
        urls += [png, tiff]
        let model = PhotoSession(store: PresetStore(url: root.appendingPathComponent("presets.json")))
        let before = rss()
        var gaps: [Double] = []
        let heartbeat = Task { @MainActor in
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(10))
                guard !Task.isCancelled else { break }
                let now = ContinuousClock.now
                gaps.append(seconds(last.duration(to: now))); last = now
            }
        }
        defer { heartbeat.cancel() }
        var start = ContinuousClock.now
        model.importPhotos(urls); try await idle(model)
        let importSeconds = seconds(start.duration(to: .now))
        XCTAssertEqual(model.photos.count, 402)
        let importedRSS = rss()
        let peakAfterImport = peakRSS()
        var thumbnailSamples: [[String: Double]] = []
        start = .now
        for (index, photo) in model.photos.enumerated() {
            _ = try await model.loader.thumbnail(photo.url)
            if [49, 199, 399, 401].contains(index) { thumbnailSamples.append(["count": Double(index + 1), "rssMiB": rss()]) }
        }
        let thumbnailSeconds = seconds(start.duration(to: .now))
        let peakAfterThumbnails = peakRSS()
        let view = NSHostingView(rootView: WorkspaceView(session: model).frame(width: 1120, height: 760))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        defer { window.close() }
        var previews: [Double] = []
        for index in Array(stride(from: 1, to: 400, by: 20)) + [400, 401] {
            start = .now
            model.selectedID = model.photos[index].id
            let deadline = start + .seconds(15)
            while model.preview == nil && model.previewError == nil && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(2))
            }
            XCTAssertNotNil(model.preview)
            view.layoutSubtreeIfNeeded()
            previews.append(seconds(start.duration(to: .now)))
        }
        let selectedRSS = rss()
        let peakAfterSelections = peakRSS()
        // Rapid changes should cancel obsolete previews and leave the final one ready.
        start = .now
        for index in 0..<100 { model.selectedID = model.photos[index].id }
        let deadline = start + .seconds(15)
        while model.preview == nil && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(2)) }
        let rapidSeconds = seconds(start.duration(to: .now))
        XCTAssertNotNil(model.preview)
        model.settings.ratio = "5:4"
        let batch = Array(model.photos.prefix(4)) + [model.photos[400], model.photos[401], model.photos[401]]
        start = .now; model.export(batch, to: root); try await idle(model)
        let exportSeconds = seconds(start.duration(to: .now))
        XCTAssertEqual(model.result?.outputs.count, 7); XCTAssertTrue(model.issues.isEmpty)
        heartbeat.cancel(); await heartbeat.value
        var repository = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { repository.deleteLastPathComponent() }
        let reportURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["BORDERMUSE_BENCHMARK_REPORT"] ?? repository.appendingPathComponent("build/qa/performance.json").path)
        let report: [String: Any] = [
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "memoryGiB": Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824,
            "processorCount": ProcessInfo.processInfo.activeProcessorCount,
            "workload": "402 inputs; 400 hardlinks to one synthetic 24MP JPEG; 12MP PNG; 24MP 16-bit P3 TIFF; 7 exports; offscreen workspace",
            "importSeconds": importSeconds, "thumbnailSeconds": thumbnailSeconds,
            "previewSeconds": previews, "rapid100SelectionsSeconds": rapidSeconds,
            "exportSeconds": exportSeconds, "mainActorHeartbeatMaxSeconds": gaps.max() ?? 0,
            "peakAfterImportMiB": peakAfterImport, "peakAfterThumbnailsMiB": peakAfterThumbnails, "peakAfterSelectionsMiB": peakAfterSelections,
            "rssBeforeMiB": before, "rssAfterImportMiB": importedRSS, "thumbnailSamples": thumbnailSamples,
            "rssAfterSelectionsMiB": selectedRSS, "rssAfterExportMiB": rss(), "processPeakRSSMiB": peakRSS(),
        ]
        try FileManager.default.createDirectory(at: reportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: reportURL)
        print("BENCHMARK_REPORT: \(reportURL.path)")
        model.clear()
    }
}
