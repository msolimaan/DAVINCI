import Foundation

public enum RemovalMode: String, CaseIterable, Identifiable, Sendable {
    case moveToTrash
    case deletePermanently

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .moveToTrash: return "Move to Trash"
        case .deletePermanently: return "Delete Immediately"
        }
    }

    public var explanation: String {
        switch self {
        case .moveToTrash: return "Safest. You can put things back until you empty the Trash."
        case .deletePermanently: return "Frees space right away. Removed files cannot be restored."
        }
    }
}

/// Something the user chose to remove, plus the folder it has to stay inside.
public struct RemovalTarget: Hashable, Sendable {
    public let url: URL
    public let allowedRoot: URL
    public let size: Int64
    /// Set for things that cannot go to the Trash, like items already in it.
    public let forcePermanent: Bool

    public init(url: URL, allowedRoot: URL, size: Int64, forcePermanent: Bool = false) {
        self.url = url
        self.allowedRoot = allowedRoot
        self.size = size
        self.forcePermanent = forcePermanent
    }
}

public struct RemovalReport: Sendable {
    public struct Failure: Identifiable, Sendable {
        public let id: UUID
        public let target: RemovalTarget
        public let reason: String
        /// True when the failure is a permission problem that administrator rights would solve.
        public let needsAdministrator: Bool

        public init(target: RemovalTarget, reason: String, needsAdministrator: Bool) {
            self.id = UUID()
            self.target = target
            self.reason = reason
            self.needsAdministrator = needsAdministrator
        }
    }

    public var removed: [URL] = []
    public var failures: [Failure] = []
    public var freedBytes: Int64 = 0

    public init() {}

    public mutating func merge(_ other: RemovalReport) {
        removed += other.removed
        failures += other.failures
        freedBytes += other.freedBytes
    }
}

/// Removes files after re-checking each one with `SafetyGuard`.
public struct Remover: Sendable {
    public let safety: SafetyGuard

    public init(safety: SafetyGuard = SafetyGuard()) {
        self.safety = safety
    }

    public func remove(_ targets: [RemovalTarget], mode: RemovalMode) -> RemovalReport {
        var report = RemovalReport()
        let fileManager = FileManager.default

        for target in targets {
            if case .denied(let reason) = safety.check(target.url, allowedRoot: target.allowedRoot) {
                report.failures.append(.init(target: target, reason: reason, needsAdministrator: false))
                continue
            }
            // Already gone (for example a parent folder was removed first): nothing to do.
            guard Self.itemExists(at: target.url) else { continue }

            do {
                if mode == .deletePermanently || target.forcePermanent {
                    try fileManager.removeItem(at: target.url)
                } else {
                    try Self.moveToTrash(target.url)
                }
                report.removed.append(target.url)
                report.freedBytes += target.size
            } catch {
                report.failures.append(
                    .init(
                        target: target,
                        reason: error.localizedDescription,
                        needsAdministrator: Self.isPermissionError(error)
                    )
                )
            }
        }
        return report
    }

    /// Shell command that deletes the targets as root. Only targets that pass `SafetyGuard` are included.
    public func privilegedRemovalCommand(for targets: [RemovalTarget]) -> String? {
        let allowed = targets.filter { safety.check($0.url, allowedRoot: $0.allowedRoot).isAllowed }
        guard !allowed.isEmpty else { return nil }
        let paths = allowed.map { CommandRunner.shellQuote($0.url.path) }.joined(separator: " ")
        return "/bin/rm -rf -- \(paths)"
    }

    static func itemExists(at url: URL) -> Bool {
        // `fileExists` follows symlinks, so a dangling link would look missing.
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    static func moveToTrash(_ url: URL) throws {
        #if os(macOS)
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        #else
        try FileManager.default.removeItem(at: url)
        #endif
    }

    static func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            if nsError.code == NSFileWriteNoPermissionError || nsError.code == NSFileReadNoPermissionError {
                return true
            }
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain,
           [Int(EACCES), Int(EPERM)].contains(underlying.code) {
            return true
        }
        return false
    }
}
