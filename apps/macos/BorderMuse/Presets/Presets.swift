import Foundation
import BorderMuseGeometry
import BorderMuseImaging

enum NumericSetting: String, CaseIterable, Hashable {
    case thickness, longEdge, quality
    var range: ClosedRange<Int> {
        switch self {
        case .thickness: return 0...50
        case .longEdge: return 1...100_000
        case .quality: return 1...100
        }
    }
    var errorMessage: String { Strings.text(rawValue + "Error") }
    func parse(_ draft: String) -> Int? {
        guard let value = Int(draft.trimmingCharacters(in: .whitespacesAndNewlines)), range.contains(value) else { return nil }
        return value
    }
}

struct BorderSettings: Codable, Equatable, Sendable {
    var ratio = "original"
    var thickness = 10
    var reduceSize = false
    var longEdge = 3000
    var quality = 95
    var keepMetadata = true
    var isMobileReference: Bool { ratio == "5:4" && thickness == 10 && reduceSize && longEdge == 2048 }
    func applyingMobileReference() -> Self {
        var copy = self
        copy.ratio = "5:4"; copy.thickness = 10; copy.reduceSize = true; copy.longEdge = 2048
        return copy
    }
    var options: ImageOptions {
        get throws {
            guard (0...50).contains(thickness) else { throw GeometryError.invalidThickness }
            guard (1...100).contains(quality), !reduceSize || (1...100_000).contains(longEdge) else { throw ImageError.invalidOptions }
            return try ImageOptions(thickness: thickness, ratio: AspectRatio.parse(ratio),
                                    longEdge: reduceSize ? longEdge : nil,
                                    jpegQuality: Double(quality) / 100, preserveMetadata: keepMetadata)
        }
    }
}

struct Preset: Identifiable, Codable, Equatable {
    static let mobileReferenceID = UUID(uuidString: "F09C703A-989B-4B4F-9FE9-7BD46CF14001")!
    let id: UUID
    var name: String
    var settings: BorderSettings
}

struct PresetStore {
    private struct Document: Codable {
        var version = 1
        var geometryContract = CanvasLayout.contractID
        var presets: [Preset]
    }
    let url: URL
    init(url: URL? = nil) {
        #if DEBUG
        // Isolate UI-test presets without bypassing file panels or sandbox access.
        if url == nil, let token = ProcessInfo.processInfo.environment["BORDERMUSE_UI_TEST_SESSION"], UUID(uuidString: token) != nil {
            self.url = FileManager.default.temporaryDirectory.appendingPathComponent("BorderMuseUITests/\(token)/presets.json")
            return
        }
        #endif
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BorderMuse/presets-v1.json")
    }
    func load() -> [Preset] {
        guard let data = try? Data(contentsOf: url), let document = try? JSONDecoder().decode(Document.self, from: data),
              document.version == 1, document.geometryContract == CanvasLayout.contractID else { return [] }
        return document.presets.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (try? $0.settings.options) != nil }
    }
    func save(_ presets: [Preset]) throws {
        let data = try JSONEncoder().encode(Document(presets: presets))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
