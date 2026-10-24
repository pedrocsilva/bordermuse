import SwiftUI

/// Border Muse's native workspace. Photo pixels and the export canvas never use
/// these chrome colors; the export canvas remains pure white in both appearances.
enum WorkspaceStyle {
    static let inspectorWidth: CGFloat = 280
    static let body = Font.system(size: 13)
    static let section = Font.system(size: 14, weight: .semibold)
    static let detail = Font.system(size: 12)
}

struct WorkspacePalette {
    let panel: Color
    let stage: Color
    let primary: Color
    let secondary: Color
    let divider: Color
    let accent: Color
    let onAccent: Color

    init(_ scheme: ColorScheme) {
        let dark = scheme == .dark
        panel = Self.color(dark ? 0x282828 : 0xF6F6F6)
        stage = Self.color(dark ? 0x212121 : 0xE7E7E7)
        primary = Self.color(dark ? 0xF1F1F1 : 0x252525)
        secondary = Self.color(dark ? 0xBDBDBD : 0x5E5E5E)
        divider = Self.color(dark ? 0x4B4B4B : 0xD6D6D6)
        accent = Self.color(dark ? 0xB5D4E6 : 0x356783)
        onAccent = Self.color(dark ? 0x183548 : 0xFFFFFF)
    }

    private static func color(_ rgb: UInt32) -> Color {
        Color(.sRGB, red: Double((rgb >> 16) & 255) / 255,
              green: Double((rgb >> 8) & 255) / 255,
              blue: Double(rgb & 255) / 255, opacity: 1)
    }
}
