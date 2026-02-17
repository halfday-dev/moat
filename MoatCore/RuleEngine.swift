import Foundation

/// Evaluates network flows against per-user rules.
///
/// Thread-safe: all state is immutable after init.
public struct RuleEngine: Sendable {
    private let rulesByUID: [uid_t: UserRule]

    /// Create a rule engine with the given user rules.
    public init(rules: [UserRule]) {
        var map: [uid_t: UserRule] = [:]
        for rule in rules {
            map[rule.uid] = rule
        }
        self.rulesByUID = map
    }

    /// Evaluate whether a flow from `uid` to `hostname` should be allowed.
    public func evaluate(uid: uid_t, hostname: String?) -> Verdict {
        guard let rule = rulesByUID[uid] else {
            return .allow
        }

        let host = hostname ?? ""

        switch rule.defaultPolicy {
        case .deny:
            if !host.isEmpty && matchesDomainSet(host, rule.allowlist) {
                return .allow
            }
            return .deny

        case .allow:
            if !host.isEmpty && matchesDomainSet(host, rule.blocklist) {
                return .deny
            }
            return .allow
        }
    }

    /// Check if `hostname` matches any entry in `domains`.
    /// Supports exact matches and wildcard prefixes (`*.example.com`).
    private func matchesDomainSet(_ hostname: String, _ domains: Set<String>) -> Bool {
        let lower = hostname.lowercased()
        for pattern in domains {
            let p = pattern.lowercased()
            if p.hasPrefix("*.") {
                let suffix = String(p.dropFirst(1)) // → .example.com
                if lower.hasSuffix(suffix) && lower != String(suffix.dropFirst()) {
                    return true
                }
            } else {
                if lower == p {
                    return true
                }
            }
        }
        return false
    }
}
