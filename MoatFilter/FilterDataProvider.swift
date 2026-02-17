import NetworkExtension
import Darwin
import Foundation
import os.log
import MoatCore

/// NEFilterDataProvider subclass that logs all network flows with user identity.
/// Phase 0: observe only — all flows are allowed via RuleEngine (no rules configured).
class FilterDataProvider: NEFilterDataProvider {

    private let logger = Logger(subsystem: "dev.halfday.moat.filter", category: "flows")

    /// Rule engine for flow decisions. Phase 0: no rules = allow all.
    private let ruleEngine = RuleEngine(rules: [])

    /// Buffered log entries, flushed periodically or when threshold is reached.
    private var logBuffer: [FlowLogEntry] = []
    private let bufferQueue = DispatchQueue(label: "dev.halfday.moat.filter.logbuffer")
    private let flushThreshold = 100
    private var flushTimer: DispatchSourceTimer?

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        logger.info("MoatFilter: starting filter")

        // Start periodic flush timer (every 5 seconds)
        let timer = DispatchSource.makeTimerSource(queue: bufferQueue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            self?.flushBuffer()
        }
        timer.resume()
        self.flushTimer = timer

        // Use .filterData to catch ALL flows (not just browser)
        let filterSettings = NEFilterSettings(rules: [], defaultAction: .filterData)
        apply(filterSettings) { error in
            if let error {
                self.logger.error("MoatFilter: failed to apply settings: \(error.localizedDescription)")
            } else {
                self.logger.info("MoatFilter: filter settings applied")
            }
            completionHandler(error)
        }
    }

    override func stopFilter(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        logger.info("MoatFilter: stopping filter, reason: \(String(describing: reason))")
        flushTimer?.cancel()
        flushTimer = nil
        bufferQueue.sync { flushBuffer() }
        completionHandler()
    }

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        let uid = extractUID(from: flow)
        let hostname = extractHostname(from: flow)
        let processName = flow.sourceAppAuditToken.flatMap { extractProcessName(from: $0) }

        let verdict = ruleEngine.evaluate(uid: uid, hostname: hostname)

        logger.info("""
            MoatFilter flow: uid=\(uid) process=\(processName ?? "unknown", privacy: .public) \
            host=\(hostname ?? "unknown", privacy: .public) verdict=\(verdict.rawValue, privacy: .public)
            """)

        // Buffer log entry
        let entry = FlowLogEntry(
            uid: uid,
            processName: processName,
            remoteHost: hostname,
            verdict: verdict
        )
        bufferQueue.async { [weak self] in
            self?.appendToBuffer(entry)
        }

        switch verdict {
        case .allow: return .allow()
        case .deny: return .drop()
        }
    }

    // MARK: - Buffered Logging

    private func appendToBuffer(_ entry: FlowLogEntry) {
        logBuffer.append(entry)
        if logBuffer.count >= flushThreshold {
            flushBuffer()
        }
    }

    /// Flush buffered entries to disk. Must be called on bufferQueue.
    private func flushBuffer() {
        guard !logBuffer.isEmpty else { return }
        let entries = logBuffer
        logBuffer.removeAll(keepingCapacity: true)

        let encoder = JSONEncoder()
        let url = FlowLogConfig.logFileURL()

        var lines = ""
        for entry in entries {
            guard let data = try? encoder.encode(entry),
                  let line = String(data: data, encoding: .utf8) else { continue }
            lines += line + "\n"
        }

        guard !lines.isEmpty else { return }

        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(lines.utf8))
            handle.closeFile()
        } else {
            // Create file with restricted permissions (0o600)
            FileManager.default.createFile(atPath: url.path, contents: Data(lines.utf8), attributes: [.posixPermissions: 0o600])
        }
    }

    // MARK: - Private Helpers

    /// Extract the real UID from the flow's source app audit token.
    private func extractUID(from flow: NEFilterFlow) -> uid_t {
        guard let tokenData = flow.sourceAppAuditToken else {
            return UInt32.max
        }
        guard tokenData.count == MemoryLayout<audit_token_t>.size else {
            return UInt32.max
        }

        // Safe copy — no alignment assumption
        var token = audit_token_t()
        withUnsafeMutableBytes(of: &token) { dest in
            tokenData.copyBytes(to: dest)
        }

        return audit_token_to_ruid(token)
    }

    /// Try to get a process name from the audit token's PID.
    private func extractProcessName(from tokenData: Data) -> String? {
        guard tokenData.count == MemoryLayout<audit_token_t>.size else { return nil }

        var token = audit_token_t()
        withUnsafeMutableBytes(of: &token) { dest in
            tokenData.copyBytes(to: dest)
        }

        let pid = audit_token_to_pid(token)
        guard pid > 0 else { return nil }

        var name = [CChar](repeating: 0, count: 1024)
        let len = proc_name(pid, &name, UInt32(name.count))
        guard len > 0 else { return nil }
        return String(cString: name)
    }

    /// Extract the remote hostname from the flow.
    private func extractHostname(from flow: NEFilterFlow) -> String? {
        if let browserFlow = flow as? NEFilterBrowserFlow,
           let host = browserFlow.url?.host {
            return host
        }
        if let socketFlow = flow as? NEFilterSocketFlow,
           let endpoint = socketFlow.remoteEndpoint as? NWHostEndpoint {
            return endpoint.hostname
        }
        return flow.url?.host
    }
}
