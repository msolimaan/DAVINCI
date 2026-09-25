import Foundation

/// A group of junk files the cleaner knows how to find.
public enum ScanCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case userCaches
    case userLogs
    case systemLogs
    case xcodeJunk
    case developerCaches
    case browserCaches
    case mailAttachments
    case trash

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .userCaches: return "User Cache Files"
        case .userLogs: return "User Log Files"
        case .systemLogs: return "System Log Files"
        case .xcodeJunk: return "Xcode Junk"
        case .developerCaches: return "Developer Tool Caches"
        case .browserCaches: return "Browser Caches"
        case .mailAttachments: return "Mail Downloads"
        case .trash: return "Trash Bins"
        }
    }

    public var subtitle: String {
        switch self {
        case .userCaches: return "Temporary files apps keep to load faster. They are rebuilt automatically."
        case .userLogs: return "Diagnostic logs and crash reports written by your apps."
        case .systemLogs: return "Logs written by system services that you are allowed to remove."
        case .xcodeJunk: return "DerivedData, old device support files, simulator caches and archives."
        case .developerCaches: return "Package caches from Homebrew, npm, Yarn, pnpm, pip, CocoaPods, Gradle and Cargo."
        case .browserCaches: return "Cached web content from Safari, Chrome, Firefox, Edge, Brave and Arc."
        case .mailAttachments: return "Attachments Mail saved when you opened or previewed them."
        case .trash: return "Files already in your Trash that still take up space."
        }
    }

    /// SF Symbol used to represent the category in the UI.
    public var symbolName: String {
        switch self {
        case .userCaches: return "internaldrive"
        case .userLogs: return "doc.text.magnifyingglass"
        case .systemLogs: return "gearshape.2"
        case .xcodeJunk: return "hammer"
        case .developerCaches: return "shippingbox"
        case .browserCaches: return "globe"
        case .mailAttachments: return "paperclip"
        case .trash: return "trash"
        }
    }

    /// Items already in the Trash cannot be moved to the Trash, so they are always deleted.
    public var alwaysDeletesPermanently: Bool { self == .trash }
}
