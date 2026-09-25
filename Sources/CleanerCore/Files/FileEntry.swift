import Foundation

public enum FileKind: String, CaseIterable, Identifiable, Sendable {
    case video, audio, image, archive, diskImage, document, application, code, other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .video: return "Movies"
        case .audio: return "Music & Audio"
        case .image: return "Pictures"
        case .archive: return "Archives"
        case .diskImage: return "Disk Images"
        case .document: return "Documents"
        case .application: return "Apps & Installers"
        case .code: return "Code & Data"
        case .other: return "Other"
        }
    }

    public var symbolName: String {
        switch self {
        case .video: return "film"
        case .audio: return "music.note"
        case .image: return "photo"
        case .archive: return "archivebox"
        case .diskImage: return "opticaldiscdrive"
        case .document: return "doc.richtext"
        case .application: return "app.badge"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .other: return "doc"
        }
    }

    public static func from(pathExtension ext: String) -> FileKind {
        switch ext.lowercased() {
        case "mov", "mp4", "m4v", "mkv", "avi", "wmv", "webm", "mpg", "mpeg", "braw", "r3d", "mxf", "prores":
            return .video
        case "mp3", "wav", "aiff", "aif", "flac", "m4a", "aac", "ogg", "caf", "logicx":
            return .audio
        case "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "raw", "cr2", "cr3", "nef", "arw", "dng", "psd", "gif", "webp", "exr":
            return .image
        case "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst":
            return .archive
        case "dmg", "iso", "img", "sparseimage", "sparsebundle", "vmdk", "qcow2", "vdi":
            return .diskImage
        case "pdf", "doc", "docx", "pages", "key", "keynote", "ppt", "pptx", "xls", "xlsx", "numbers", "txt", "rtf", "epub":
            return .document
        case "app", "pkg", "mpkg", "ipa", "xip", "apk":
            return .application
        case "json", "csv", "sqlite", "db", "log", "xml", "parquet", "npy", "safetensors", "gguf", "bin", "ckpt", "pt":
            return .code
        default:
            return .other
        }
    }
}

public struct FileEntry: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let size: Int64
    public let modified: Date?
    public let lastOpened: Date?

    public init(url: URL, size: Int64, modified: Date?, lastOpened: Date?) {
        self.url = url
        self.size = size
        self.modified = modified
        self.lastOpened = lastOpened
    }

    public var name: String { url.lastPathComponent }
    public var kind: FileKind { FileKind.from(pathExtension: url.pathExtension) }

    /// The most recent time the file was used or changed.
    public var lastActivity: Date? {
        switch (modified, lastOpened) {
        case let (m?, o?): return max(m, o)
        case let (m?, nil): return m
        case let (nil, o?): return o
        default: return nil
        }
    }

    public var removalTarget: RemovalTarget {
        RemovalTarget(url: url, allowedRoot: url.deletingLastPathComponent(), size: size)
    }
}
