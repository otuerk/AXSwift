import Foundation
import Cocoa

/// Thread-safe queue manager for all AX API operations
@available(macOS 10.15, *)
class AXQueue {
    static let shared = AXQueue()
    
    private let axQueue: DispatchQueue
    
    private init() {
        axQueue = DispatchQueue(label: "at.otu.axswift.axqueue", qos: .userInitiated)
    }
    
    /// Execute AX operation asynchronously on background queue using async/await
    /// All AX operations must go through this to ensure thread safety
    @available(macOS 10.15, *)
    func execute<T>(_ operation: @escaping () throws -> T?) async throws -> T? {
        return try await withCheckedThrowingContinuation { continuation in
            axQueue.async {
                do {
                    let value = try operation()
                    continuation.resume(returning: value)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Execute AX operation asynchronously with custom callback queue using async/await
    @available(macOS 10.15, *)
    func execute<T>(_ operation: @escaping () throws -> T,
                   callbackQueue: DispatchQueue) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            axQueue.async {
                do {
                    let value = try operation()
                    callbackQueue.async {
                        continuation.resume(returning: value)
                    }
                } catch {
                    callbackQueue.async {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    /// Execute multiple AX operations in sequence on the background queue using async/await
    @available(macOS 10.15, *)
    func executeBatch<T>(_ operations: [() throws -> T]) async throws -> [T] {
        return try await withCheckedThrowingContinuation { continuation in
            axQueue.async {
                do {
                    var results: [T] = []
                    for operation in operations {
                        let result = try operation()
                        results.append(result)
                    }
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
