import Foundation
import SystemExtensions
import NetworkExtension
import os.log

/// Manages activation and deactivation of the MoatFilter system extension.
@MainActor
class SystemExtensionManager: NSObject, ObservableObject {
    static let filterBundleID = "dev.halfday.moat.filter"

    enum Status: String {
        case unknown = "Unknown"
        case pending = "Pending Approval…"
        case activated = "Activated"
        case deactivating = "Deactivating…"
        case error = "Error"
    }

    @Published var status: Status = .unknown
    @Published var errorMessage: String?
    @Published var filterEnabled: Bool = false

    private let logger = Logger(subsystem: "dev.halfday.moat", category: "sysext")

    /// Request activation of the system extension.
    func activate() {
        status = .pending
        errorMessage = nil
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: Self.filterBundleID,
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    /// Request deactivation of the system extension.
    func deactivate() {
        status = .deactivating
        errorMessage = nil
        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: Self.filterBundleID,
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    /// Enable the content filter via NEFilterManager.
    func enableFilter() {
        NEFilterManager.shared().loadFromPreferences { [weak self] error in
            if let error {
                Task { @MainActor in
                    self?.errorMessage = "Load prefs failed: \(error.localizedDescription)"
                }
                return
            }

            let config = NEFilterProviderConfiguration()
            config.filterBrowsers = true
            config.filterSockets = true

            NEFilterManager.shared().providerConfiguration = config
            NEFilterManager.shared().isEnabled = true

            NEFilterManager.shared().saveToPreferences { [weak self] error in
                Task { @MainActor in
                    if let error {
                        self?.errorMessage = "Save prefs failed: \(error.localizedDescription)"
                    } else {
                        self?.filterEnabled = true
                    }
                }
            }
        }
    }

    /// Disable the content filter.
    func disableFilter() {
        NEFilterManager.shared().loadFromPreferences { [weak self] error in
            if let error {
                Task { @MainActor in
                    self?.errorMessage = "Load prefs failed: \(error.localizedDescription)"
                }
                return
            }
            NEFilterManager.shared().isEnabled = false
            NEFilterManager.shared().saveToPreferences { [weak self] error in
                Task { @MainActor in
                    if let error {
                        self?.errorMessage = "Save prefs failed: \(error.localizedDescription)"
                    } else {
                        self?.filterEnabled = false
                    }
                }
            }
        }
    }
}

// MARK: - OSSystemExtensionRequestDelegate

extension SystemExtensionManager: OSSystemExtensionRequestDelegate {
    nonisolated func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        Task { @MainActor in
            status = .pending
            logger.info("System extension needs user approval")
        }
    }

    nonisolated func request(
        _ request: OSSystemExtensionRequest,
        didFinishWithResult result: OSSystemExtensionRequest.Result
    ) {
        Task { @MainActor in
            switch result {
            case .completed:
                status = .activated
                logger.info("System extension activated")
            case .willCompleteAfterReboot:
                status = .pending
                logger.info("System extension will activate after reboot")
            @unknown default:
                status = .unknown
            }
        }
    }

    nonisolated func request(
        _ request: OSSystemExtensionRequest,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            status = .error
            errorMessage = error.localizedDescription
            logger.error("System extension error: \(error.localizedDescription)")
        }
    }
}
