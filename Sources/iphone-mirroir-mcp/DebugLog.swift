// ABOUTME: Shared debug logger that writes to stderr and /tmp/iphone-mirroir-mcp-debug.log.
// ABOUTME: Gated by a global flag set at startup via --debug CLI argument.

import Foundation

/// Shared debug logger used across the MCP server.
/// Writes tagged lines to both stderr and the debug log file when enabled.
enum DebugLog {
    /// Whether debug logging is active. Set once at startup from --debug flag,
    /// before any concurrent access occurs.
    nonisolated(unsafe) static var enabled = false

    /// Path to the debug log file.
    static let logPath = "/tmp/iphone-mirroir-mcp-debug.log"

    /// Truncate the debug log file. Called once at startup.
    static func reset() {
        guard enabled else { return }
        FileManager.default.createFile(atPath: logPath, contents: nil)
    }

    /// Write a tagged debug line to stderr and the log file.
    static func log(_ tag: String, _ message: String) {
        guard enabled else { return }
        let line = "[\(tag)] \(message)\n"
        fputs(line, stderr)
        if let fh = FileHandle(forWritingAtPath: logPath) {
            fh.seekToEndOfFile()
            fh.write(Data(line.utf8))
            fh.closeFile()
        } else {
            FileManager.default.createFile(atPath: logPath,
                                           contents: Data(line.utf8))
        }
    }
}
