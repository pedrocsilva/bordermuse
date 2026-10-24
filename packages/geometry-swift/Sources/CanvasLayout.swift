import Foundation

public enum GeometryError: Error, LocalizedError {
    case invalidSize, invalidThickness, invalidRatio, overflow

    public var errorDescription: String? {
        switch self {
        case .invalidSize: return "Image dimensions must be positive integers."
        case .invalidThickness: return "Thickness must be an integer from 0 to 50."
        case .invalidRatio: return "Aspect ratio must be Original or two positive integers, such as 4:5."
        case .overflow: return "The requested image dimensions are too large."
        }
    }
}

public struct PixelSize: Hashable, Codable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) throws {
        guard width > 0, height > 0 else { throw GeometryError.invalidSize }
        self.width = width
        self.height = height
    }
}

public struct AspectRatio: Hashable, Codable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) throws {
        guard width > 0, height > 0 else { throw GeometryError.invalidRatio }
        var a = width, b = height
        while b != 0 { (a, b) = (b, a % b) }
        self.width = width / a
        self.height = height / a
    }

    public static func parse(_ value: String) throws -> AspectRatio? {
        if value == "original" { return nil }
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) else {
            throw GeometryError.invalidRatio
        }
        return try AspectRatio(width: w, height: h)
    }
}

/// Exact bordermuse-geometry-v1. All arithmetic is integer and checked.
public struct CanvasLayout: Equatable, Codable, Sendable {
    public static let contractID = "bordermuse-geometry-v1"
    public let width: Int
    public let height: Int
    public let left: Int
    public let right: Int
    public let top: Int
    public let bottom: Int

    public static func calculate(content: PixelSize, thickness: Int, ratio: AspectRatio?) throws -> CanvasLayout {
        guard content.width > 0, content.height > 0 else { throw GeometryError.invalidSize }
        guard (0...50).contains(thickness) else { throw GeometryError.invalidThickness }
        let ratio = try ratio ?? AspectRatio(width: content.width, height: content.height)
        guard ratio.width > 0, ratio.height > 0 else { throw GeometryError.invalidRatio }
        let w = content.width, h = content.height, rw = ratio.width, rh = ratio.height
        let mx: Int, my: Int
        if try multiply(w, rh) >= multiply(h, rw) {
            mx = try multiply(w, thickness) / 200
            let desired = try multiply(multiply(w, 100 + thickness), rh)
            let occupied = try multiply(multiply(100, h), rw)
            my = try subtract(desired, occupied) / multiply(200, rw)
        } else {
            let desired = try multiply(multiply(h, 100 + thickness), rw)
            let occupied = try multiply(multiply(100, w), rh)
            mx = try subtract(desired, occupied) / multiply(200, rh)
            my = try multiply(h, thickness) / 200
        }
        return try CanvasLayout(width: add(w, multiply(2, mx)), height: add(h, multiply(2, my)),
                                left: mx, right: mx, top: my, bottom: my)
    }

    private static func multiply(_ a: Int, _ b: Int) throws -> Int {
        let (value, overflow) = a.multipliedReportingOverflow(by: b)
        guard !overflow else { throw GeometryError.overflow }
        return value
    }
    private static func add(_ a: Int, _ b: Int) throws -> Int {
        let (value, overflow) = a.addingReportingOverflow(b)
        guard !overflow else { throw GeometryError.overflow }
        return value
    }
    private static func subtract(_ a: Int, _ b: Int) throws -> Int {
        let (value, overflow) = a.subtractingReportingOverflow(b)
        guard !overflow, value >= 0 else { throw GeometryError.overflow }
        return value
    }
}
