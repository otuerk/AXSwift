import Foundation
import Cocoa

/// Thread-safe queue manager for all AX API operations
class AXQueue {
    static let shared = AXQueue()
    
    private let axQueue: DispatchQueue
    
    private init() {
        axQueue = DispatchQueue(label: "at.otu.axswift.axqueue", qos: .userInitiated)
    }
    
    /// Execute AX operation asynchronously on background queue
    /// All AX operations must go through this to ensure thread safety
    func execute<T>(_ operation: @escaping () throws -> T, 
                   completion: @escaping (Result<T, Error>) -> Void) {
        axQueue.async {
            do {
                let value = try operation()
                DispatchQueue.main.async {
                    completion(.success(value))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Execute AX operation asynchronously with custom callback queue
    func execute<T>(_ operation: @escaping () throws -> T,
                   callbackQueue: DispatchQueue,
                   completion: @escaping (Result<T, Error>) -> Void) {
        axQueue.async {
            do {
                let value = try operation()
                callbackQueue.async {
                    completion(.success(value))
                }
            } catch {
                callbackQueue.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Execute multiple AX operations in sequence on the background queue
    func executeBatch<T>(_ operations: [() throws -> T],
                        completion: @escaping (Result<[T], Error>) -> Void) {
        axQueue.async {
            do {
                var results: [T] = []
                for operation in operations {
                    let result = try operation()
                    results.append(result)
                }
                DispatchQueue.main.async {
                    completion(.success(results))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}
