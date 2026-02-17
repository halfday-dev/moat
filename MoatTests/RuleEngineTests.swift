import XCTest
@testable import MoatCore

final class RuleEngineTests: XCTestCase {

    // MARK: - No Rules

    func testUserWithNoRules_allows() {
        let engine = RuleEngine(rules: [])
        XCTAssertEqual(engine.evaluate(uid: 501, hostname: "example.com"), .allow)
    }

    // MARK: - Default Deny + Allowlist

    func testDefaultDeny_allowlistedDomain_allows() {
        let rule = UserRule(uid: 501, defaultPolicy: .deny, allowlist: ["example.com"])
        let engine = RuleEngine(rules: [rule])
        XCTAssertEqual(engine.evaluate(uid: 501, hostname: "example.com"), .allow)
    }

    func testDefaultDeny_nonAllowlistedDomain_denies() {
        let rule = UserRule(uid: 501, defaultPolicy: .deny, allowlist: ["example.com"])
        let engine = RuleEngine(rules: [rule])
        XCTAssertEqual(engine.evaluate(uid: 501, hostname: "evil.com"), .deny)
    }

    // MARK: - Wildcard Matching

    func testWildcard_matchesSubdomain() {
        let rule = UserRule(uid: 501, defaultPolicy: .deny, allowlist: ["*.github.com"])
        let engine = RuleEngine(rules: [rule])
        XCTAssertEqual(engine.evaluate(uid: 501, hostname: "api.github.com"), .allow)
    }

    func testWildcard_doesNotMatchBaseDomain() {
        let rule = UserRule(uid: 501, defaultPolicy: .deny, allowlist: ["*.github.com"])
        let engine = RuleEngine(rules: [rule])
        XCTAssertEqual(engine.evaluate(uid: 501, hostname: "github.com"), .deny)
    }

    func testWildcard_matchesDeepSubdomain() {
        let rule = UserRule(uid: 501, defaultPolicy: .deny, allowlist: ["*.openai.com"])
        let engine = RuleEngine(rules: [rule])
        XCTAssertEqual(engine.evaluate(uid: 501, hostname: "api.v2.openai.com"), .allow)
    }

    // MARK: - Default Allow + Blocklist

    func testDefaultAllow_blocklistedDomain_denies() {
        let rule = UserRule(uid: 501, defaultPolicy: .allow, blocklist: ["bad.com"])
        let engine = RuleEngine(rules: [rule])
        XCTAssertEqual(engine.evaluate(uid: 501, hostname: "bad.com"), .deny)
    }

    func testDefaultAllow_nonBlocklistedDomain_allows() {
        let rule = UserRule(uid: 501, defaultPolicy: .allow, blocklist: ["bad.com"])
        let engine = RuleEngine(rules: [rule])
        XCTAssertEqual(engine.evaluate(uid: 501, hostname: "good.com"), .allow)
    }

    func testDefaultAllow_wildcardBlocklist_denies() {
        let rule = UserRule(uid: 501, defaultPolicy: .allow, blocklist: ["*.tiktok.com"])
        let engine = RuleEngine(rules: [rule])
        XCTAssertEqual(engine.evaluate(uid: 501, hostname: "www.tiktok.com"), .deny)
    }

    // MARK: - Empty Hostname

    func testEmptyHostname_defaultDeny_denies() {
        let rule = UserRule(uid: 501, defaultPolicy: .deny, allowlist: ["example.com"])
        let engine = RuleEngine(rules: [rule])
        XCTAssertEqual(engine.evaluate(uid: 501, hostname: ""), .deny)
    }

    func testEmptyHostname_defaultAllow_allows() {
        let rule = UserRule(uid: 501, defaultPolicy: .allow, blocklist: ["bad.com"])
        let engine = RuleEngine(rules: [rule])
        XCTAssertEqual(engine.evaluate(uid: 501, hostname: ""), .allow)
    }

    func testNilHostname_defaultDeny_denies() {
        let rule = UserRule(uid: 501, defaultPolicy: .deny, allowlist: ["example.com"])
        let engine = RuleEngine(rules: [rule])
        XCTAssertEqual(engine.evaluate(uid: 501, hostname: nil), .deny)
    }

    // MARK: - Case Insensitivity

    func testCaseInsensitive_matching() {
        let rule = UserRule(uid: 501, defaultPolicy: .deny, allowlist: ["Example.COM"])
        let engine = RuleEngine(rules: [rule])
        XCTAssertEqual(engine.evaluate(uid: 501, hostname: "example.com"), .allow)
    }

    // MARK: - Multiple Users

    func testMultipleUsers_isolatedRules() {
        let rules = [
            UserRule(uid: 501, defaultPolicy: .deny, allowlist: ["work.com"]),
            UserRule(uid: 502, defaultPolicy: .allow, blocklist: ["games.com"]),
        ]
        let engine = RuleEngine(rules: rules)

        XCTAssertEqual(engine.evaluate(uid: 501, hostname: "work.com"), .allow)
        XCTAssertEqual(engine.evaluate(uid: 501, hostname: "games.com"), .deny)
        XCTAssertEqual(engine.evaluate(uid: 502, hostname: "work.com"), .allow)
        XCTAssertEqual(engine.evaluate(uid: 502, hostname: "games.com"), .deny)
        XCTAssertEqual(engine.evaluate(uid: 503, hostname: "anything.com"), .allow)
    }
}

// MARK: - FlowLogEntry Tests

final class FlowLogEntryTests: XCTestCase {

    func testJSONRoundTrip() throws {
        let entry = FlowLogEntry(
            uid: 501,
            processName: "curl",
            remoteHost: "example.com",
            verdict: .allow
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(entry)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FlowLogEntry.self, from: data)

        XCTAssertEqual(entry, decoded)
    }

    func testJSONRoundTrip_deny() throws {
        let entry = FlowLogEntry(
            uid: 502,
            processName: nil,
            remoteHost: nil,
            verdict: .deny
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(FlowLogEntry.self, from: data)

        XCTAssertEqual(entry, decoded)
        XCTAssertEqual(decoded.verdict, .deny)
        XCTAssertNil(decoded.processName)
        XCTAssertNil(decoded.remoteHost)
    }

    func testJSONRoundTrip_verdictIsString() throws {
        let entry = FlowLogEntry(uid: 501, verdict: .allow)
        let data = try JSONEncoder().encode(entry)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        // Verdict should serialize as a raw string
        XCTAssertEqual(json["verdict"] as? String, "allow")
    }
}
