import Foundation

/// Verdict for a network flow.
public enum Verdict: String, Codable, Equatable, Sendable {
    case allow
    case deny
}

/// A single logged network flow event.
public struct FlowLogEntry: Codable, Sendable, Equatable {
    /// ISO-8601 timestamp.
    public let timestamp: String

    /// UNIX UID of the originating user.
    public let uid: uid_t

    /// Process name that initiated the flow (if available).
    public let processName: String?

    /// Remote hostname or IP.
    public let remoteHost: String?

    /// The verdict applied to this flow.
    public let verdict: Verdict

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        return fmt
    }()

    public init(
        timestamp: Date = Date(),
        uid: uid_t,
        processName: String? = nil,
        remoteHost: String? = nil,
        verdict: Verdict = .allow
    ) {
        self.timestamp = Self.iso8601Formatter.string(from: timestamp)
        self.uid = uid
        self.processName = processName
        self.remoteHost = remoteHost
        self.verdict = verdict
    }
}

/// Shared log file path for IPC between the filter extension and the host app.
/// Both targets must be in the same app group for this to work in production.
public enum FlowLogConfig {
    /// The shared log file name.
    public static let logFileName = "moat-flow-log.jsonl"

    /// Cached log directory URL (created once).
    private static let logDirectory: URL = {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory not found")
        }
        let dir = appSupport.appendingPathComponent("dev.halfday.moat", isDirectory: true)
        // Harden directory permissions: 0o700 (owner only, filter runs as root)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return dir
    }()

    /// Returns the URL for the shared log file in the user's Application Support directory.
    public static func logFileURL() -> URL {
        logDirectory.appendingPathComponent(logFileName)
    }
}
