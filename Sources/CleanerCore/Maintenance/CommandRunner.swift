import Foundation

public struct CommandResult: Sendable {
    public let exitCode: Int32
    public let output: String

    public init(exitCode: Int32, output: String) {
        self.exitCode = exitCode
        self.output = output
    }

    public var succeeded: Bool { exitCode == 0 }

    /// True when the user dismissed the macOS administrator password prompt.
    public var wasCancelledByUser: Bool { output.contains("-128") || output.contains("User canceled") }
}

/// Runs shell commands, optionally with administrator rights through the standard macOS password prompt.
public enum CommandRunner {
    /// Runs `command` with `/bin/sh -c`. When `asAdministrator` is set, macOS shows its own
    /// authentication dialog (via `osascript ... with administrator privileges`); the app never sees the password.
    public static func run(_ command: String, asAdministrator: Bool = false) async -> CommandResult {
        let executable: String
        let arguments: [String]
        if asAdministrator {
            executable = "/usr/bin/osascript"
            arguments = ["-e", "do shell script \"\(appleScriptEscaped(command))\" with administrator privileges"]
        } else {
            executable = "/bin/sh"
            arguments = ["-c", command]
        }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runSynchronously(executable: executable, arguments: arguments))
            }
        }
    }

    static func runSynchronously(executable: String, arguments: [String]) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return CommandResult(exitCode: -1, output: error.localizedDescription)
        }
        // Drain the pipe before waiting so a chatty command can't fill the buffer and block.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return CommandResult(exitCode: process.terminationStatus, output: output)
    }

    /// Wraps a string in single quotes for `/bin/sh`.
    public static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Escapes a string for use inside an AppleScript double-quoted literal.
    public static func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
