import SwiftUI
import AppKit

// Grabi design system tokens (design/Phase 1 and Phase 2).
// Hardcoding values in views is FORBIDDEN: everything goes through here.

// MARK: - Color

private func dynamicColor(light: String, dark: String, alpha: CGFloat = 1) -> Color {
    func nsColor(_ hex: String) -> NSColor {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        return NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha)
    }
    return Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? nsColor(dark) : nsColor(light)
    })
}

/// Semantic colors (Phase 1 §03 + Phase 2 §01 "Red interaction" +
/// Phase 4 prototype variables). Light/dark pair on every token.
public enum GrabiColor {
    // Surfaces and text
    public static let bg = dynamicColor(light: "FAF7F1", dark: "1B1916")
    public static let surface = dynamicColor(light: "FFFFFF", dark: "242019")
    public static let text = dynamicColor(light: "26221C", dark: "F2EDE4")
    public static let textSecondary = dynamicColor(light: "5C5548", dark: "B3AA9B")
    public static let border = dynamicColor(light: "EAE3D6", dark: "3A342C")
    /// Strong border (secondary buttons, record-button pill).
    public static let borderStrong = dynamicColor(light: "D8CDB8", dark: "4A4438")
    public static let divider = dynamicColor(light: "F3EEE3", dark: "26221C")

    // The red rule: `rec` only as SHAPE (dot, badge, mascot);
    // `error` only as text with an icon. They never mix.
    public static let rec = dynamicColor(light: "E5483F", dark: "FF6B5E")
    public static let brandStrong = dynamicColor(light: "C93A32", dark: "FF6B5E")
    public static let brandHover = dynamicColor(light: "B33028", dark: "FF7B6F") // dark: lighten +6%
    public static let brandActive = dynamicColor(light: "9E2A23", dark: "FF8B80")
    public static let onBrand = dynamicColor(light: "FFFFFF", dark: "1B1916")
    public static let focus = dynamicColor(light: "C93A32", dark: "FF6B5E")

    // Semantic
    public static let success = dynamicColor(light: "2E7D4C", dark: "6FCE96")
    public static let exitoBg = dynamicColor(light: "EDF5EE", dark: "243527")
    public static let advertencia = dynamicColor(light: "8A5E00", dark: "E4B45C")
    public static let advertenciaBg = dynamicColor(light: "FDF6E8", dark: "332A1B")
    public static let error = dynamicColor(light: "B3372B", dark: "F1867B")
    public static let errorHover = dynamicColor(light: "9E2F25", dark: "F1867B")
    public static let errorActive = dynamicColor(light: "8A2820", dark: "F1867B")

    // Tints (12% of the base color, Phase 2)
    public static let tintRec = dynamicColor(light: "E5483F", dark: "FF6B5E", alpha: 0.12)
    public static let tintExito = dynamicColor(light: "2E7D4C", dark: "6FCE96", alpha: 0.12)
    public static let tintAdvertencia = dynamicColor(light: "8A5E00", dark: "E4B45C", alpha: 0.12)

    // Controls (Phase 4 prototype variables)
    public static let track = dynamicColor(light: "EFE8DA", dark: "1B1916") // segmented background
    public static let segmentThumb = dynamicColor(light: "FFFFFF", dark: "3A342C")
    public static let switchOff = dynamicColor(light: "C4B89F", dark: "3A342C")
    public static let switchOffHover = dynamicColor(light: "AD9F82", dark: "4A4438")
    public static let knobOn = dynamicColor(light: "FFFFFF", dark: "1B1916")
    public static let chip = dynamicColor(light: "F3EEE3", dark: "1B1916") // ⌘⇧2 shortcut background
    public static let ghostHover = dynamicColor(light: "F3EEE3", dark: "2E2A23")
    public static let ghostActive = dynamicColor(light: "EAE3D6", dark: "3A342C")

    // Mascot
    public static let mascotFace = dynamicColor(light: "FFF6F0", dark: "26221C")

    // Fixed dark surfaces (floating pill, tooltips, REC badge:
    // dark in both modes, per Phase 2/3)
    public static let inkFixed = Color(nsColor: NSColor(srgbRed: 0x26/255.0, green: 0x22/255.0, blue: 0x1C/255.0, alpha: 1))
    public static let inkFixedSoft = Color(nsColor: NSColor(srgbRed: 0x3A/255.0, green: 0x34/255.0, blue: 0x2C/255.0, alpha: 1))
    public static let inkFixedBorder = Color(nsColor: NSColor(srgbRed: 0x4A/255.0, green: 0x44/255.0, blue: 0x38/255.0, alpha: 1))
    public static let ivoryFixed = Color(nsColor: NSColor(srgbRed: 0xF2/255.0, green: 0xED/255.0, blue: 0xE4/255.0, alpha: 1))
    public static let ivoryFixedDim = Color(nsColor: NSColor(srgbRed: 0xB3/255.0, green: 0xAA/255.0, blue: 0x9B/255.0, alpha: 1))
    public static let recOnInk = Color(nsColor: NSColor(srgbRed: 1.0, green: 0x6B/255.0, blue: 0x5E/255.0, alpha: 1)) // #FF6B5E
    public static let ambarOnInk = Color(nsColor: NSColor(srgbRed: 0xE4/255.0, green: 0xB4/255.0, blue: 0x5C/255.0, alpha: 1)) // #E4B45C

    public static let shadow = dynamicColor(light: "26221C", dark: "000000", alpha: 0.2)
}

// MARK: - Spacing (4 px scale, Phase 2 §01)

public enum GrabiSpace {
    public static let s1: CGFloat = 4
    public static let s2: CGFloat = 8
    public static let s3: CGFloat = 12
    public static let s4: CGFloat = 16
    public static let s6: CGFloat = 24
    public static let s8: CGFloat = 32
    public static let s12: CGFloat = 48
    public static let s16: CGFloat = 64
}

// MARK: - Radii

public enum GrabiRadius {
    public static let xs: CGFloat = 6
    public static let sm: CGFloat = 10
    public static let md: CGFloat = 14
    public static let lg: CGFloat = 20
    public static let full: CGFloat = 999
}

// MARK: - Elevation

public struct GrabiElevation {
    public let radius: CGFloat
    public let y: CGFloat
    public let opacity: CGFloat

    /// resting: 0 1px 3px
    public static let e1 = GrabiElevation(radius: 3, y: 1, opacity: 0.10)
    /// popover: 0 6px 18px
    public static let e2 = GrabiElevation(radius: 18, y: 6, opacity: 0.12)
    /// modal: 0 16px 40px
    public static let e3 = GrabiElevation(radius: 40, y: 16, opacity: 0.20)
}

public extension View {
    /// Elevation shadow using the system shadow color.
    func grabiShadow(_ elevation: GrabiElevation) -> some View {
        shadow(color: GrabiColor.shadow.opacity(elevation.opacity / 0.2),
               radius: elevation.radius / 2, x: 0, y: elevation.y)
    }
}

// MARK: - Motion

public enum GrabiDuration {
    public static let fast: Double = 0.120   // hover, press
    public static let base: Double = 0.200   // toggles, segmented, tooltips
    public static let slow: Double = 0.320   // panels, modals, toasts
    public static let pulse: Double = 1.600  // REC pulse
}

public enum GrabiAnimation {
    /// easing.standard · cubic-bezier(0.2, 0, 0, 1)
    public static func standard(_ duration: Double = GrabiDuration.base) -> Animation {
        .timingCurve(0.2, 0, 0, 1, duration: duration)
    }
    /// easing.exit · cubic-bezier(0.3, 0, 1, 1)
    public static func exit(_ duration: Double = GrabiDuration.base) -> Animation {
        .timingCurve(0.3, 0, 1, 1, duration: duration)
    }
}

// MARK: - Typography (system SF Pro with the manual's scale, Phase 1 §04)

public enum GrabiFont {
    public static let title1 = Font.system(size: 32, weight: .bold)
    public static let title2 = Font.system(size: 24, weight: .semibold)
    public static let title3 = Font.system(size: 20, weight: .semibold)
    public static let bodyLg = Font.system(size: 16)
    public static let body = Font.system(size: 14)
    public static let bodySemibold = Font.system(size: 14, weight: .semibold)
    public static let caption = Font.system(size: 13)
    public static let micro = Font.system(size: 12, weight: .medium)
    /// Timers: tabular figures are mandatory.
    public static func timer(_ size: CGFloat = 17) -> Font {
        Font.system(size: size, weight: .semibold).monospacedDigit()
    }
}
