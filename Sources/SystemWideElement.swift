import Foundation
import Cocoa

/// A singleton for the system-wide element.
public var systemWideElement = SystemWideElement()

/// A `UIElement` for the system-wide accessibility element, which can be used to retrieve global,
/// application-inspecific parameters like the currently focused element.
open class SystemWideElement: UIElement {
    fileprivate convenience init() {
        self.init(AXUIElementCreateSystemWide())
    }

    /// Returns the element at the specified top-down coordinates asynchronously, or nil if there is none.
    /// - parameter completion: Called with the result on the main queue
    open override func elementAtPosition(_ x: Float, _ y: Float, completion: @escaping (Result<UIElement?, Error>) -> Void) {
        super.elementAtPosition(x, y, completion: completion)
    }
}
