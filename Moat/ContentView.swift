import SwiftUI
import MoatCore

/// Main UI for the Moat host app.
/// Shows extension status, activation controls, and a live flow log.
struct ContentView: View {
    @StateObject private var manager = SystemExtensionManager()
    @StateObject private var logReader = FlowLogReader()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("Moat — Network Flow Monitor")
                .font(.title)
                .fontWeight(.bold)

            // Status
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)
                Text("Extension: \(manager.status.rawValue)")
                    .font(.headline)
            }

            if let error = manager.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            // Controls
            HStack(spacing: 12) {
                Button("Activate Extension") {
                    manager.activate()
                }
                .disabled(manager.status == .activated || manager.status == .pending)

                Button("Deactivate Extension") {
                    manager.deactivate()
                }
                .disabled(manager.status != .activated)

                Divider().frame(height: 20)

                Button(manager.filterEnabled ? "Disable Filter" : "Enable Filter") {
                    if manager.filterEnabled {
                        manager.disableFilter()
                    } else {
                        manager.enableFilter()
                    }
                }
                .disabled(manager.status != .activated)
            }

            Divider()

            // Log view
            Text("Flow Log")
                .font(.headline)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(logReader.lines.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .id(idx)
                        }
                    }
                    .padding(4)
                }
                .onChange(of: logReader.lines.count) { _, newCount in
                    if newCount > 0 {
                        proxy.scrollTo(newCount - 1, anchor: .bottom)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.textBackgroundColor))
            .cornerRadius(6)
        }
        .padding()
        .frame(minWidth: 700, minHeight: 500)
    }

    private var statusColor: Color {
        switch manager.status {
        case .activated: return .green
        case .pending, .deactivating: return .yellow
        case .error: return .red
        case .unknown: return .gray
        }
    }
}

/// Reads the shared JSONL flow log file and tails it incrementally.
@MainActor
class FlowLogReader: ObservableObject {
    @Published var lines: [String] = []
    private var timer: Timer?
    /// Track file offset to only read new bytes on each poll.
    private var fileOffset: UInt64 = 0

    init() {
        loadNewLines()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.loadNewLines()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }

    private func loadNewLines() {
        let url = FlowLogConfig.logFileURL()

        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { handle.closeFile() }

        handle.seek(toFileOffset: fileOffset)
        let newData = handle.readDataToEndOfFile()

        guard !newData.isEmpty,
              let text = String(data: newData, encoding: .utf8) else { return }

        fileOffset += UInt64(newData.count)

        let newLines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        lines.append(contentsOf: newLines)

        // Keep only last 500 lines
        if lines.count > 500 {
            lines = Array(lines.suffix(500))
        }
    }
}
