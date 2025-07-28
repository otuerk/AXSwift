import Cocoa

/// Checks if the current process is a trusted accessibility client asynchronously.
///
/// - parameter prompt: Whether to show the user a prompt if the process is untrusted. This
///                    happens asynchronously and does not affect the return value.
/// - returns: Whether the process is trusted
@available(macOS 10.15, *)
public func checkIsProcessTrusted(prompt: Bool = false) async throws -> Bool {
    return try await AXQueue.shared.execute({
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [promptKey: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }) ?? false
}
