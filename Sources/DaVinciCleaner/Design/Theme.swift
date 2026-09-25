import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// The colour story of one module. Every screen of a module is painted with its palette,
/// so you always know where you are (the same idea CleanMyMac uses).
struct ModulePalette: Equatable {
    let top: Color
    let bottom: Color
    let glow: Color

    var background: LinearGradient {
        LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var iconFill: LinearGradient {
        LinearGradient(colors: [glow, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var ring: AngularGradient {
        AngularGradient(colors: [.white.opacity(0.6), glow, .white], center: .center)
    }
}

enum Theme {
    static let cornerRadius: CGFloat = 18
    static let cardFill = Color.white.opacity(0.08)
    static let cardStroke = Color.white.opacity(0.14)
    static let rowHover = Color.white.opacity(0.07)
    static let rowSelected = Color.white.opacity(0.14)
    static let secondaryText = Color.white.opacity(0.68)
    static let tertiaryText = Color.white.opacity(0.45)

    /// Vivid colours for Space Lens tiles and charts.
    static let tilePalette: [Color] = [
        Color(hex: 0x38BDF8), Color(hex: 0x818CF8), Color(hex: 0xC084FC), Color(hex: 0xF472B6),
        Color(hex: 0xFB923C), Color(hex: 0xFACC15), Color(hex: 0x34D399), Color(hex: 0x2DD4BF),
    ]

    static let success = Color(hex: 0x4ADE80)
    static let warning = Color(hex: 0xFACC15)
    static let danger = Color(hex: 0xF87171)
}

extension Font {
    static let heroTitle = Font.system(size: 34, weight: .bold, design: .rounded)
    static let heroNumber = Font.system(size: 56, weight: .bold, design: .rounded)
    static let sectionTitle = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let cardTitle = Font.system(size: 15, weight: .semibold, design: .rounded)
}
