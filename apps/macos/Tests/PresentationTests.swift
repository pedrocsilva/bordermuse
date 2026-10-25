import AppKit
import CoreGraphics
import ImageIO
import SwiftUI
import XCTest
import BorderMuseImaging
import BorderMuseGeometry
@testable import BorderMuse

@MainActor
final class PresentationTests: XCTestCase {
    private func session(width: Int = 1000, height: Int = 800) async throws -> PhotoSession {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("bordermuse-layout-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Example.png")
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.8, green: 0.4, blue: 0.15, alpha: 1))
        context.fillEllipse(in: CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let session = PhotoSession(store: PresetStore(url: directory.appendingPathComponent("presets.json")))
        session.photos = [try await session.loader.load(url)]
        session.selectedID = session.photos[0].id
        session.preview = PreviewImage(image: context.makeImage()!)
        return session
    }
    func testInvalidDraftBlocksExportAndPresetCanResetIt() async throws {
        let session = try await session()
        XCTAssertTrue(session.canExport)
        XCTAssertNil(NumericSetting.thickness.parse("abc"))
        XCTAssertNil(NumericSetting.thickness.parse("51"))
        XCTAssertNil(NumericSetting.thickness.parse(""))
        XCTAssertEqual(NumericSetting.thickness.parse(" 20 "), 20)
        session.setInputValidity(.thickness, valid: false)
        XCTAssertFalse(session.canExport); XCTAssertNotNil(session.validationMessage)
        session.savePreset(name: "Invalid draft")
        XCTAssertTrue(session.presets.isEmpty)
        session.setInputValidity(.thickness, valid: true)
        session.savePreset(name: "Valid")
        let id = try XCTUnwrap(session.presets.first?.id)
        session.setInputValidity(.quality, valid: false)
        session.usePreset(id)
        XCTAssertTrue(session.canExport); XCTAssertNil(session.validationMessage)
    }
    func testArrowSelectionClampsAndDeleteKeepsAValidSelection() async throws {
        let session = try await session()
        let second = try await session.loader.load(session.photos[0].url)
        session.photos.append(second)
        session.selectNeighbor(1); XCTAssertEqual(session.selectedID, second.id)
        session.selectNeighbor(1); XCTAssertEqual(session.selectedID, second.id)
        session.selectNeighbor(-1); XCTAssertEqual(session.selectedID, session.photos[0].id)
        session.remove(session.photos[0]); XCTAssertEqual(session.selectedID, second.id)
        session.remove(second); XCTAssertNil(session.selectedID)
    }
    func testExportSummaryTracksBatchScopeAndResizeLimit() async throws {
        let model = try await session()
        XCTAssertEqual(model.settingsScope, "1 photo")
        XCTAssertEqual(model.exportSizeSummary, "Original resolution")
        model.settings.reduceSize = true
        model.settings.longEdge = 3000
        XCTAssertEqual(model.exportSizeSummary, "Up to 3,000 px")
        // A limit above the source must not claim that the content was enlarged.
        let layout = try XCTUnwrap(model.layout)
        XCTAssertEqual(layout.width - layout.left - layout.right, 1000)
        model.setInputValidity(.longEdge, valid: false)
        XCTAssertEqual(model.exportSizeSummary, "Review size")
        model.setInputValidity(.longEdge, valid: true)
        let second = try await model.loader.load(model.photos[0].url)
        model.photos.append(second)
        XCTAssertEqual(model.settingsScope, "All 2 photos")
        model.clear()
        XCTAssertEqual(model.settingsScope, "Add photos to begin")
    }
    func testWorkspaceSnapshotsAtMinimumSizeAndBothAppearances() async throws {
        try requireNativeRendering()
        var repository = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { repository.deleteLastPathComponent() }
        let output = repository.appendingPathComponent("build/qa/design")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, w, h, dark, width, height, options) in [
            ("light-landscape", 1000, 800, false, 1120, 760, false),
            ("dark-portrait", 801, 1201, true, 1120, 760, false),
            ("light-square-minimum", 900, 900, false, 900, 620, false),
            ("dark-minimum-options", 801, 1201, true, 900, 620, true),
            ("light-mobile-reference", 801, 1201, false, 900, 620, true),
            ("light-empty", 1000, 800, false, 900, 620, false),
            ("dark-exporting", 1000, 800, true, 900, 620, false),
            ("light-long-name-batch", 1000, 800, false, 900, 620, false),
            ("light-inactive", 1000, 800, false, 900, 620, false),
            ("dark-inactive", 1000, 800, true, 900, 620, false),
        ] {
            let model = try await session(width: w, height: h)
            model.settings.ratio = "1:1"; model.settings.reduceSize = options
            if name == "light-mobile-reference" { model.usePreset(Preset.mobileReferenceID) }
            if name == "light-empty" { model.clear() }
            if name == "dark-exporting" || name == "light-long-name-batch" {
                let original = model.photos[0]
                for index in 2...3 {
                    let url = original.url.deletingLastPathComponent().appendingPathComponent("Example \(index).png")
                    try FileManager.default.copyItem(at: original.url, to: url)
                    model.photos.append(try await model.loader.load(url))
                }
            }
            if name == "dark-exporting" { model.isExporting = true; model.total = 3; model.completed = 2 }
            if name == "light-long-name-batch" {
                let original = model.photos[0]
                let longURL = original.url.deletingLastPathComponent().appendingPathComponent("A very long photograph name from a memorable journey in the mountains — final edited version.png")
                try FileManager.default.copyItem(at: original.url, to: longURL)
                let renamed = Photo(id: original.id, url: longURL, info: original.info, canonicalURL: longURL)
                model.photos[0] = renamed
            }
            let root = WorkspaceView(session: model)
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.colorScheme, dark ? .dark : .light)
                .environment(\.controlActiveState, name.hasSuffix("-inactive") ? .inactive : .active)
                .frame(width: CGFloat(width), height: CGFloat(height))
            let hosting = NSHostingView(rootView: root)
            let frame = NSRect(x: 0, y: 0, width: width, height: height)
            let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.contentView = hosting
            hosting.frame = frame; hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: output.appendingPathComponent(name + ".png"))
            XCTAssertGreaterThan(png.count, 5000, "Snapshot must contain rendered UI")
            if name == "light-mobile-reference" {
                XCTAssertEqual(model.selectedPreset, Preset.mobileReferenceID)
                XCTAssertTrue(model.settings.isMobileReference)
            }
            window.close()
            model.clear()
        }
    }
    private func nonwhiteBounds(_ image: CGImage, region: CGRect? = nil) throws -> CGRect {
        let roi = region ?? CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let cropped = try XCTUnwrap(image.cropping(to: roi))
        let context = try XCTUnwrap(CGContext(data: nil, width: cropped.width, height: cropped.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        var left = cropped.width, top = cropped.height, right = -1, bottom = -1
        for y in 0..<cropped.height { for x in 0..<cropped.width {
            let i = y * context.bytesPerRow + x * 4
            if bytes[i] < 245 || bytes[i + 1] < 245 || bytes[i + 2] < 245 {
                left = min(left, x); right = max(right, x); top = min(top, y); bottom = max(bottom, y)
            }
        } }
        XCTAssertGreaterThanOrEqual(right, left)
        let origin = CGPoint(x: CGFloat(left) + roi.minX, y: CGFloat(top) + roi.minY)
        let size = CGSize(width: CGFloat(right - left + 1), height: CGFloat(bottom - top + 1))
        return CGRect(origin: origin, size: size)
    }
    func testRenderedPreviewUsesFullResolutionGeometryRatherThanThumbnailGeometry() async throws {
        try requireNativeRendering()
        let model = try await session(width: 101, height: 67)
        model.settings.ratio = "5:4"; model.settings.thickness = 7
        let photo = try XCTUnwrap(model.photos.first)
        let thumbnail = try ImageProcessor.preview(photo.url, maximumPixelSize: 15)
        XCTAssertEqual(thumbnail.width, 15)
        let layout = try XCTUnwrap(model.layout)
        XCTAssertEqual(layout.width, 107); XCTAssertEqual(layout.height, 85)
        let view = CanvasPreview(name: "Example.png", preview: PreviewImage(image: thumbnail), failure: nil, layout: layout)
            .frame(width: 800, height: 600)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let rendered = try XCTUnwrap(renderer.cgImage)
        // Independent screen coordinates for a 107×85 canvas fitted into 800×600
        // with 36 pt padding. Screen rasterization may cover one fractional pixel.
        let screen = try nonwhiteBounds(rendered, region: CGRect(x: 69, y: 38, width: 662, height: 524))
        XCTAssertEqual(screen.minX, 86, accuracy: 1); XCTAssertEqual(screen.minY, 92, accuracy: 1)
        XCTAssertEqual(screen.maxX, 714, accuracy: 1); XCTAssertEqual(screen.maxY, 508, accuracy: 1)
        let output = photo.url.deletingLastPathComponent().appendingPathComponent("preview-export.png")
        try ImageProcessor.export(input: photo.url, output: output, options: model.settings.options)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        let exported = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(try nonwhiteBounds(exported), CGRect(x: 3, y: 9, width: 101, height: 67))
    }
    private func requireNativeRendering() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["BORDER_MUSE_SKIP_RENDER_TESTS"] == "1",
                      "Native render tests need a usable Metal device; unavailable on the Intel hosted runner.")
    }
}
