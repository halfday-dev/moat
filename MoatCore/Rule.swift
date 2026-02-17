import Foundation

/// The default policy for a user when no specific rule matches.
public enum DefaultPolicy: String, Codable, Sendable {
    case allow
    case deny
}

/// A per-user rule set: a default policy plus domain-level overrides.
public struct UserRule: Sendable, Equatable, Hashable {
    /// The user's UNIX UID.
    public let uid: uid_t

    /// What to do when no allowlist/blocklist entry matches.
    public let defaultPolicy: DefaultPolicy

    /// Domains explicitly allowed (overrides a default-deny).
    /// Supports wildcard prefixes like `*.example.com`.
    public let allowlist: Set<String>

    /// Domains explicitly blocked (overrides a default-allow).
    /// Supports wildcard prefixes like `*.example.com`.
    public let blocklist: Set<String>

    public init(
        uid: uid_t,
        defaultPolicy: DefaultPolicy = .allow,
        allowlist: Set<String> = [],
        blocklist: Set<String> = []
    ) {
        self.uid = uid
        self.defaultPolicy = defaultPolicy
        self.allowlist = allowlist
        self.blocklist = blocklist
    }
}
