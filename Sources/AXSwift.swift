import Cocoa

/// Checks if the current process is a trusted accessibility client asynchronously.
///
/// - parameter prompt: Whether to show the user a prompt if the process is untrusted. This
///                    happens asynchronously and does not affect the return value.
/// - parameter completion: Called with the result on the main queue
public func checkIsProcessTrusted(prompt: Bool = false, completion: @escaping (Bool) -> Void) {
    AXQueue.shared.execute({
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [promptKey: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }, completion: { result in
        switch result {
        case .success(let trusted):
            completion(trusted)
        case .failure(_):
            completion(false)
        }
    })
}
