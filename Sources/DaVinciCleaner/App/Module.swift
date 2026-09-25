import SwiftUI

/// The sections of the app, shown in the sidebar.
enum Module: String, CaseIterable, Identifiable, Hashable {
    case smartScan
    case systemJunk
    case uninstaller
    case spaceLens
    case largeFiles
    case duplicates
    case maintenance
    case loginItems
    case monitor

    enum Group: String, CaseIterable, Identifiable {
        case care, cleanup, applications, files, speed, health

        var id: String { rawValue }

        var title: String {
            switch self {
            case .care: return "Smart Care"
            case .cleanup: return "Cleanup"
            case .applications: return "Applications"
            case .files: return "Files"
            case .speed: return "Speed"
            case .health: return "Health"
            }
        }

        var modules: [Module] { Module.allCases.filter { $0.group == self } }
    }

    var id: String { rawValue }

    var group: Group {
        switch self {
        case .smartScan: return .care
        case .systemJunk: return .cleanup
        case .uninstaller: return .applications
        case .spaceLens, .largeFiles, .duplicates: return .files
        case .maintenance, .loginItems: return .speed
        case .monitor: return .health
        }
    }

    var title: String {
        switch self {
        case .smartScan: return "Smart Scan"
        case .systemJunk: return "System Junk"
        case .uninstaller: return "Uninstaller"
        case .spaceLens: return "Space Lens"
        case .largeFiles: return "Large & Old Files"
        case .duplicates: return "Duplicates"
        case .maintenance: return "Maintenance"
        case .loginItems: return "Login Items"
        case .monitor: return "System Monitor"
        }
    }

    var tagline: String {
        switch self {
        case .smartScan: return "One scan to clean junk, speed things up and spot clutter."
        case .systemJunk: return "Clear caches, logs, developer leftovers and browser data to free up space."
        case .uninstaller: return "Remove apps completely, including the files they hide in your Library."
        case .spaceLens: return "See what's taking up space, folder by folder, as an interactive map."
        case .largeFiles: return "Find big files you forgot about and decide what to keep."
        case .duplicates: return "Find identical copies of files and keep just one."
        case .maintenance: return "Run the scripts that fix common slowdowns and glitches."
        case .loginItems: return "Control what starts automatically with your Mac."
        case .monitor: return "Live CPU, memory and disk health, plus the apps using the most."
        }
    }

    var symbol: String {
        switch self {
        case .smartScan: return "sparkles"
        case .systemJunk: return "trash.circle"
        case .uninstaller: return "square.grid.3x3.square"
        case .spaceLens: return "circle.hexagongrid"
        case .largeFiles: return "doc.on.doc"
        case .duplicates: return "square.on.square"
        case .maintenance: return "bolt.horizontal.circle"
        case .loginItems: return "power.circle"
        case .monitor: return "waveform.path.ecg"
        }
    }

    var palette: ModulePalette {
        switch self {
        case .smartScan:
            return ModulePalette(top: Color(hex: 0x2A0B6B), bottom: Color(hex: 0xA3169A), glow: Color(hex: 0xF472D0))
        case .systemJunk:
            return ModulePalette(top: Color(hex: 0x053B3A), bottom: Color(hex: 0x14966F), glow: Color(hex: 0x5EEAD4))
        case .uninstaller:
            return ModulePalette(top: Color(hex: 0x0A1F5C), bottom: Color(hex: 0x2563EB), glow: Color(hex: 0x7DD3FC))
        case .spaceLens:
            return ModulePalette(top: Color(hex: 0x1B1650), bottom: Color(hex: 0x0E7490), glow: Color(hex: 0x67E8F9))
        case .largeFiles:
            return ModulePalette(top: Color(hex: 0x5A1A0B), bottom: Color(hex: 0xE0621A), glow: Color(hex: 0xFDBA74))
        case .duplicates:
            return ModulePalette(top: Color(hex: 0x4A0628), bottom: Color(hex: 0xD02670), glow: Color(hex: 0xF9A8D4))
        case .maintenance:
            return ModulePalette(top: Color(hex: 0x5B0F2E), bottom: Color(hex: 0xEE5A36), glow: Color(hex: 0xFFC48A))
        case .loginItems:
            return ModulePalette(top: Color(hex: 0x2E0A57), bottom: Color(hex: 0xB026C9), glow: Color(hex: 0xE9A8FF))
        case .monitor:
            return ModulePalette(top: Color(hex: 0x0D1330), bottom: Color(hex: 0x3F3CC4), glow: Color(hex: 0xA5B4FC))
        }
    }
}
