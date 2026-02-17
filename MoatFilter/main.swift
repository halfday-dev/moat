import Foundation
import NetworkExtension

// Entry point for the MoatFilter system extension.
// NEProvider subclasses are loaded automatically by the NetworkExtension framework
// when the extension is activated. This file exists as the main entry point.
autoreleasepool {
    NEProvider.startSystemExtensionMode()
}
dispatchMain()
