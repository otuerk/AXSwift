import Cocoa
import Foundation

/// Holds and interacts with any accessibility element.
///
/// This class wraps every operation that operates on AXUIElements.
///
/// - seeAlso: [OS X Accessibility Model](https://developer.apple.com/library/mac/documentation/Accessibility/Conceptual/AccessibilityMacOSX/OSXAXmodel.html)
///
/// Note that every operation involves IPC and is tied to the event loop of the target process.
/// All operations are now asynchronous and executed on a dedicated background queue to prevent
/// blocking the main thread. Timeouts can be changed using `setMessagingTimeout` and `setGlobalMessagingTimeout`.
///
/// Every attribute- or action-related function has an enum version and a String version. This is
/// because certain processes might report attributes or actions not documented in the standard API.
/// These will be ignored by enum functions (and you can't specify them). Most users will want to
/// use the enum-based versions, but if you want to be exhaustive or use non-standard attributes and
/// actions, you can use the String versions.
///
/// ### Error handling
///
/// Unless otherwise specified, during reads, "missing data/attribute" errors are handled by
/// returning optionals as nil. During writes, missing attribute errors are thrown.
///
/// Other failures are all thrown, including if messaging fails or the underlying AXUIElement
/// becomes invalid.
///
/// #### Possible Errors
/// - `Error.APIDisabled`: The accessibility API is disabled. Your application must request and
///                        receive special permission from the user to be able to use these APIs.
/// - `Error.InvalidUIElement`: The UI element has become invalid, perhaps because it was destroyed.
/// - `Error.CannotComplete`: There is a problem with messaging, perhaps because the application is
///                           being unresponsive. This error will be thrown when a message times
///                           out.
/// - `Error.NotImplemented`: The process does not fully support the accessibility API.
/// - Anything included in the docs of the method you are calling.
///
/// Any undocumented errors thrown are bugs and should be reported.
///
/// - seeAlso: [AXUIElement.h reference](https://developer.apple.com/library/mac/documentation/ApplicationServices/Reference/AXUIElement_header_reference/)
open class UIElement {
    public let element: AXUIElement

    /// Create a UIElement from a raw AXUIElement object.
    ///
    /// The state and role of the AXUIElement is not checked.
    public required init(_ nativeElement: AXUIElement) {
        // Since we are dealing with low-level C APIs, it never hurts to double check types.
        assert(CFGetTypeID(nativeElement) == AXUIElementGetTypeID(),
               "nativeElement is not an AXUIElement")

        element = nativeElement
    }

    /// Checks if the current process is a trusted accessibility client asynchronously.
    ///
    /// - parameter withPrompt: Whether to show the user a prompt if the process is untrusted. This
    ///                         happens asynchronously and does not affect the return value.
    /// - parameter completion: Called with the result on the main queue
    open class func isProcessTrusted(withPrompt showPrompt: Bool = false, 
                                   completion: @escaping (Bool) -> Void) {
        AXQueue.shared.execute({
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: showPrompt as CFBoolean
            ]
            return AXIsProcessTrustedWithOptions(options as CFDictionary)
        }, completion: { result in
            switch result {
            case .success(let trusted):
                completion(trusted)
            case .failure(_):
                completion(false)
            }
        })
    }

    /// Timeout in seconds for all UIElement messages. Use this to control how long a method call
    /// can delay execution. The default is `0` which means to use the system default.
    open class var globalMessagingTimeout: Float {
        get { return systemWideElement.messagingTimeout }
        set { systemWideElement.messagingTimeout = newValue }
    }

    // MARK: - Attributes

    /// Returns the list of all attributes asynchronously.
    ///
    /// Does not include parameterized attributes.
    /// - parameter completion: Called with the result on the main queue
    open func attributes(completion: @escaping (Result<[Attribute], Error>) -> Void) {
        attributesAsStrings { result in
            switch result {
            case .success(let attrs):
                for attr in attrs where Attribute(rawValue: attr) == nil {
                    print("Unrecognized attribute: \(attr)")
                }
                let attributes = attrs.compactMap({ Attribute(rawValue: $0) })
                completion(.success(attributes))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Returns attribute names as strings asynchronously.
    /// - parameter completion: Called with the result on the main queue
    open func attributesAsStrings(completion: @escaping (Result<[String], Error>) -> Void) {
        AXQueue.shared.execute({
            var names: CFArray?
            let error = AXUIElementCopyAttributeNames(self.element, &names)

            if error == .noValue || error == .attributeUnsupported {
                return []
            }

            guard error == .success else {
                throw error
            }

            // We must first convert the CFArray to a native array, then downcast to an array of
            // strings.
            return names! as [AnyObject] as! [String]
        }, completion: completion)
    }

    /// Returns whether `attribute` is supported by this element asynchronously.
    ///
    /// The `attribute` method returns nil for unsupported attributes and empty attributes alike,
    /// which is more convenient than dealing with exceptions (which are used for more serious
    /// errors). However, if you'd like to specifically test an attribute is actually supported, you
    /// can use this method.
    /// - parameter completion: Called with the result on the main queue
    open func attributeIsSupported(_ attribute: Attribute, completion: @escaping (Result<Bool, Error>) -> Void) {
        attributeIsSupported(attribute.rawValue, completion: completion)
    }

    open func attributeIsSupported(_ attribute: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        AXQueue.shared.execute({
            // Ask to copy 0 values, since we are only interested in the return code.
            var value: CFArray?
            let error = AXUIElementCopyAttributeValues(self.element, attribute as CFString, 0, 0, &value)

            if error == .attributeUnsupported {
                return false
            }

            if error == .noValue {
                return true
            }

            guard error == .success else {
                throw error
            }

            return true
        }, completion: completion)
    }

    /// Returns whether `attribute` is writeable asynchronously.
    /// - parameter completion: Called with the result on the main queue
    open func attributeIsSettable(_ attribute: Attribute, completion: @escaping (Result<Bool, Error>) -> Void) {
        attributeIsSettable(attribute.rawValue, completion: completion)
    }

    open func attributeIsSettable(_ attribute: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        AXQueue.shared.execute({
            var settable: DarwinBoolean = false
            let error = AXUIElementIsAttributeSettable(self.element, attribute as CFString, &settable)

            if error == .noValue || error == .attributeUnsupported {
                return false
            }

            guard error == .success else {
                throw error
            }

            return settable.boolValue
        }, completion: completion)
    }

    /// Returns the value of `attribute` asynchronously, if it exists.
    ///
    /// - parameter attribute: The name of a (non-parameterized) attribute.
    /// - parameter completion: Called with the result on the main queue. Returns an optional 
    ///                        containing the value of `attribute` as the desired type, or nil.
    ///                        If `attribute` is an array, all values are returned.
    ///
    /// - warning: This method force-casts the attribute to the desired type, which will complete
    ///            with an error if the cast fails. If you want to check the return type, ask for Any.
    open func attribute<T>(_ attribute: Attribute, completion: @escaping (Result<T?, Error>) -> Void) {
        self.attribute(attribute.rawValue, completion: completion)
    }

    open func attribute<T>(_ attribute: String, completion: @escaping (Result<T?, Error>) -> Void) {
        AXQueue.shared.execute({
            var value: AnyObject?
            let error = AXUIElementCopyAttributeValue(self.element, attribute as CFString, &value)

            if error == .noValue || error == .attributeUnsupported {
                return nil
            }

            guard error == .success else {
                throw error
            }

            guard let unpackedValue = (self.unpackAXValue(value!) as? T) else {
                throw AXError.illegalArgument
            }
            
            return unpackedValue
        }, completion: completion)
    }

    /// Sets the value of `attribute` to `value` asynchronously.
    ///
    /// - parameter completion: Called with the result on the main queue
    /// - note: Unlike read-only methods, this method will complete with an error if the attribute doesn't exist.
    ///
    /// - Possible errors:
    ///   - `Error.AttributeUnsupported`: `attribute` isn't supported.
    ///   - `Error.IllegalArgument`: `value` is an illegal value.
    ///   - `Error.Failure`: A temporary failure occurred.
    open func setAttribute(_ attribute: Attribute, value: Any, completion: @escaping (Result<Void, Error>) -> Void) {
        setAttribute(attribute.rawValue, value: value, completion: completion)
    }

    open func setAttribute(_ attribute: String, value: Any, completion: @escaping (Result<Void, Error>) -> Void) {
        AXQueue.shared.execute({
            let error = AXUIElementSetAttributeValue(self.element, attribute as CFString, self.packAXValue(value))

            guard error == .success else {
                throw error
            }
            return ()
        }, completion: completion)
    }

    /// Gets multiple attributes of the element at once.
    ///
    /// - parameter attributes: An array of attribute names. Nonexistent attributes are ignored.
    ///
    /// - returns: A dictionary mapping provided parameter names to their values. Parameters which
    ///            don't exist or have no value will be absent.
    ///
    /// - throws: If there are any errors other than .NoValue or .AttributeUnsupported, it will
    ///           throw the first one it encounters.
    ///
    /// - note: Presumably you would use this API for performance, though it's not explicitly
    ///         documented by Apple that there is actually a difference.
    open func getMultipleAttributes(_ names: Attribute...) throws -> [Attribute: Any] {
        return try getMultipleAttributes(names)
    }

    open func getMultipleAttributes(_ attributes: [Attribute]) throws -> [Attribute: Any] {
        let values = try fetchMultiAttrValues(attributes.map({ $0.rawValue }))
        return try packMultiAttrValues(attributes, values: values)
    }

    open func getMultipleAttributes(_ attributes: [String]) throws -> [String: Any] {
        let values = try fetchMultiAttrValues(attributes)
        return try packMultiAttrValues(attributes, values: values)
    }

    // Helper: Gets list of values
    fileprivate func fetchMultiAttrValues(_ attributes: [String]) throws -> [AnyObject] {
        var valuesCF: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(
            element,
            attributes as CFArray,
            // keep going on errors (particularly NoValue)
            AXCopyMultipleAttributeOptions(rawValue: 0),
            &valuesCF)

        guard error == .success else {
            throw error
        }

        return valuesCF! as [AnyObject]
    }

    // Helper: Packs names, values into dictionary
    fileprivate func packMultiAttrValues<Attr>(_ attributes: [Attr],
                                               values: [AnyObject]) throws -> [Attr: Any] {
        var result = [Attr: Any]()
        for (index, attribute) in attributes.enumerated() {
            if try checkMultiAttrValue(values[index]) {
                result[attribute] = unpackAXValue(values[index])
            }
        }
        return result
    }

    // Helper: Checks if value is present and not an error (throws on nontrivial errors).
    fileprivate func checkMultiAttrValue(_ value: AnyObject) throws -> Bool {
        // Check for null
        if value is NSNull {
            return false
        }

        // Check for error
        if CFGetTypeID(value) == AXValueGetTypeID() &&
            AXValueGetType(value as! AXValue).rawValue == kAXValueAXErrorType {
            var error: AXError = AXError.success
            AXValueGetValue(value as! AXValue, AXValueType(rawValue: kAXValueAXErrorType)!, &error)

            assert(error != .success)
            if error == .noValue || error == .attributeUnsupported {
                return false
            } else {
                throw error
            }
        }

        return true
    }

    // MARK: Array attributes

    /// Returns all the values of the attribute as an array of the given type asynchronously.
    ///
    /// - parameter attribute: The name of the array attribute.
    /// - parameter completion: Called with the result on the main queue
    /// - note: Possible error: `Error.IllegalArgument` if the attribute isn't an array.
    open func arrayAttribute<T>(_ attribute: Attribute, completion: @escaping (Result<[T]?, Error>) -> Void) {
        arrayAttribute(attribute.rawValue, completion: completion)
    }

    open func arrayAttribute<T>(_ attribute: String, completion: @escaping (Result<[T]?, Error>) -> Void) {
        self.attribute(attribute) { (result: Result<Any?, Error>) in
            switch result {
            case .success(let value):
                guard let value = value else {
                    completion(.success(nil))
                    return
                }
                guard let array = value as? [AnyObject] else {
                    // For consistency with the other array attribute APIs, return error if it's not an array.
                    completion(.failure(AXError.illegalArgument))
                    return
                }
                let mappedArray = array.map({ self.unpackAXValue($0) as! T })
                completion(.success(mappedArray))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Returns a subset of values from an array attribute.
    ///
    /// - parameter attribute: The name of the array attribute.
    /// - parameter startAtIndex: The index of the array to start taking values from.
    /// - parameter maxValues: The maximum number of values you want.
    ///
    /// - returns: An array of up to `maxValues` values starting at `startAtIndex`.
    ///   - The array is empty if `startAtIndex` is out of range.
    ///   - `nil` if the attribute doesn't exist or has no value.
    ///
    /// - throws: `Error.IllegalArgument` if the attribute isn't an array.
    open func valuesForAttribute<T: AnyObject>
    (_ attribute: Attribute, startAtIndex index: Int, maxValues: Int) throws -> [T]? {
        return try valuesForAttribute(attribute.rawValue, startAtIndex: index, maxValues: maxValues)
    }

    open func valuesForAttribute<T: AnyObject>
    (_ attribute: String, startAtIndex index: Int, maxValues: Int) throws -> [T]? {
        var values: CFArray?
        let error = AXUIElementCopyAttributeValues(
            element, attribute as CFString, index, maxValues, &values
        )

        if error == .noValue || error == .attributeUnsupported {
            return nil
        }

        guard error == .success else {
            throw error
        }

        let array = values! as [AnyObject]
        return array.map({ unpackAXValue($0) as! T })
    }

    /// Returns the number of values an array attribute has.
    /// - returns: The number of values, or `nil` if `attribute` isn't an array (or doesn't exist).
    open func valueCountForAttribute(_ attribute: Attribute) throws -> Int? {
        return try valueCountForAttribute(attribute.rawValue)
    }

    open func valueCountForAttribute(_ attribute: String) throws -> Int? {
        var count: Int = 0
        let error = AXUIElementGetAttributeValueCount(element, attribute as CFString, &count)

        if error == .attributeUnsupported || error == .illegalArgument {
            return nil
        }

        guard error == .success else {
            throw error
        }

        return count
    }

    // MARK: Parameterized attributes

    /// Returns a list of all parameterized attributes of the element.
    ///
    /// Parameterized attributes are attributes that require parameters to retrieve. For example,
    /// the cell contents of a spreadsheet might require the row and column of the cell you want.
    open func parameterizedAttributes() throws -> [Attribute] {
        return try parameterizedAttributesAsStrings().compactMap({ Attribute(rawValue: $0) })
    }

    open func parameterizedAttributesAsStrings() throws -> [String] {
        var names: CFArray?
        let error = AXUIElementCopyParameterizedAttributeNames(element, &names)

        if error == .noValue || error == .attributeUnsupported {
            return []
        }

        guard error == .success else {
            throw error
        }

        // We must first convert the CFArray to a native array, then downcast to an array of
        // strings.
        return names! as [AnyObject] as! [String]
    }

    /// Returns the value of the parameterized attribute `attribute` with parameter `param`.
    ///
    /// The expected type of `param` depends on the attribute. See the
    /// [NSAccessibility Informal Protocol Reference](https://developer.apple.com/library/mac/documentation/Cocoa/Reference/ApplicationKit/Protocols/NSAccessibility_Protocol/)
    /// for more info.
    open func parameterizedAttribute<T, U>(_ attribute: Attribute, param: U) throws -> T? {
        return try parameterizedAttribute(attribute.rawValue, param: param)
    }

    open func parameterizedAttribute<T, U>(_ attribute: String, param: U) throws -> T? {
        var value: AnyObject?
        let error = AXUIElementCopyParameterizedAttributeValue(
            element, attribute as CFString, param as AnyObject, &value
        )

        if error == .noValue || error == .attributeUnsupported {
            return nil
        }

        guard error == .success else {
            throw error
        }

        return (unpackAXValue(value!) as! T)
    }

    // MARK: Attribute helpers

    // Checks if the value is an AXValue and if so, unwraps it.
    // If the value is an AXUIElement, wraps it in UIElement.
    fileprivate func unpackAXValue(_ value: AnyObject) -> Any {
        switch CFGetTypeID(value) {
        case AXUIElementGetTypeID():
            return UIElement(value as! AXUIElement)
        case AXValueGetTypeID():
            let type = AXValueGetType(value as! AXValue)
            switch type {
            case .axError:
                var result: AXError = .success
                let success = AXValueGetValue(value as! AXValue, type, &result)
                assert(success)
                return result
            case .cfRange:
                var result: CFRange = CFRange()
                let success = AXValueGetValue(value as! AXValue, type, &result)
                assert(success)
                return result
            case .cgPoint:
                var result: CGPoint = CGPoint.zero
                let success = AXValueGetValue(value as! AXValue, type, &result)
                assert(success)
                return result
            case .cgRect:
                var result: CGRect = CGRect.zero
                let success = AXValueGetValue(value as! AXValue, type, &result)
                assert(success)
                return result
            case .cgSize:
                var result: CGSize = CGSize.zero
                let success = AXValueGetValue(value as! AXValue, type, &result)
                assert(success)
                return result
            case .illegal:
                return value
            @unknown default:
                return value
            }
        default:
            return value
        }
    }

    // Checks if the value is one supported by AXValue and if so, wraps it.
    // If the value is a UIElement, unwraps it to an AXUIElement.
    fileprivate func packAXValue(_ value: Any) -> AnyObject {
        switch value {
        case let val as UIElement:
            return val.element
        case var val as CFRange:
            return AXValueCreate(AXValueType(rawValue: kAXValueCFRangeType)!, &val)!
        case var val as CGPoint:
            return AXValueCreate(AXValueType(rawValue: kAXValueCGPointType)!, &val)!
        case var val as CGRect:
            return AXValueCreate(AXValueType(rawValue: kAXValueCGRectType)!, &val)!
        case var val as CGSize:
            return AXValueCreate(AXValueType(rawValue: kAXValueCGSizeType)!, &val)!
        default:
            return value as AnyObject // must be an object to pass to AX
        }
    }

    // MARK: - Actions

    /// Returns a list of actions that can be performed on the element.
    open func actions() throws -> [Action] {
        return try actionsAsStrings().compactMap({ Action(rawValue: $0) })
    }

    open func actionsAsStrings() throws -> [String] {
        var names: CFArray?
        let error = AXUIElementCopyActionNames(element, &names)

        if error == .noValue || error == .attributeUnsupported {
            return []
        }

        guard error == .success else {
            throw error
        }

        // We must first convert the CFArray to a native array, then downcast to an array of strings.
        return names! as [AnyObject] as! [String]
    }

    /// Returns the human-readable description of `action`.
    open func actionDescription(_ action: Action) throws -> String? {
        return try actionDescription(action.rawValue)
    }

    open func actionDescription(_ action: String) throws -> String? {
        var description: CFString?
        let error = AXUIElementCopyActionDescription(element, action as CFString, &description)

        if error == .noValue || error == .actionUnsupported {
            return nil
        }

        guard error == .success else {
            throw error
        }

        return description! as String
    }

    /// Performs the action `action` on the element, returning on success.
    ///
    /// Performs the action `action` on the element asynchronously.
    ///
    /// - parameter completion: Called with the result on the main queue
    /// - note: If the action times out, it might mean that the application is taking a long time to
    ///         actually perform the action. It doesn't necessarily mean that the action wasn't
    ///         performed.
    /// - note: Possible error: `Error.ActionUnsupported` if the action is not supported.
    open func performAction(_ action: Action, completion: @escaping (Result<Void, Error>) -> Void) {
        performAction(action.rawValue, completion: completion)
    }

    open func performAction(_ action: String, completion: @escaping (Result<Void, Error>) -> Void) {
        AXQueue.shared.execute({
            let error = AXUIElementPerformAction(self.element, action as CFString)

            guard error == .success else {
                throw error
            }
            return ()
        }, completion: completion)
    }

    // MARK: -

    /// Returns the process ID of the application that the element is a part of asynchronously.
    ///
    /// - parameter completion: Called with the result on the main queue. Errors only occur if the element is invalid.
    open func pid(completion: @escaping (Result<pid_t, Error>) -> Void) {
        AXQueue.shared.execute({
            var pid: pid_t = -1
            let error = AXUIElementGetPid(self.element, &pid)

            guard error == .success else {
                throw error
            }

            return pid
        }, completion: completion)
    }

    /// The timeout in seconds for all messages sent to this element. Use this to control how long a
    /// method call can delay execution. The default is `0`, which means to use the global timeout.
    ///
    /// - note: Only applies to this instance of UIElement, not other instances that happen to equal
    ///         it.
    /// - seeAlso: `UIElement.globalMessagingTimeout(_:)`
    open var messagingTimeout: Float = 0 {
        didSet {
            messagingTimeout = max(messagingTimeout, 0)
            let error = AXUIElementSetMessagingTimeout(element, messagingTimeout)

            // InvalidUIElement errors are only relevant when actually passing messages, so we can
            // ignore them here.
            guard error == .success || error == .invalidUIElement else {
                fatalError("Unexpected error setting messaging timeout: \(error)")
            }
        }
    }

    // Gets the element at the specified coordinates asynchronously.
    // This can only be called on applications and the system-wide element, so it is internal here.
    func elementAtPosition(_ x: Float, _ y: Float, completion: @escaping (Result<UIElement?, Error>) -> Void) {
        AXQueue.shared.execute({
            var result: AXUIElement?
            let error = AXUIElementCopyElementAtPosition(self.element, x, y, &result)

            if error == .noValue {
                return nil
            }

            guard error == .success else {
                throw error
            }

            return UIElement(result!)
        }, completion: completion)
    }

    // TODO: convenience functions for attributes
    // TODO: get any attribute as a UIElement or [UIElement] (or a subclass)
    // TODO: promoters
}

// MARK: - CustomStringConvertible

extension UIElement: CustomStringConvertible {
    public var description: String {
        // Since description must be synchronous, provide a basic description
        // Users can call async methods directly for detailed info
        return "<UIElement \(String(describing: element))>"
    }

    public var inspect: String {
        // Since inspect must be synchronous, provide a basic description
        // Users should call async methods directly for detailed inspection
        return "<UIElement \(String(describing: element)) - use async methods for detailed inspection>"
    }
}

// MARK: - Equatable

extension UIElement: Equatable {}
public func ==(lhs: UIElement, rhs: UIElement) -> Bool {
    return CFEqual(lhs.element, rhs.element)
}

// MARK: - Convenience getters

extension UIElement {
    /// Returns the role (type) of the element asynchronously, if it reports one.
    ///
    /// Almost all elements report a role, but this could return nil for elements that aren't
    /// finished initializing.
    ///
    /// - parameter completion: Called with the result on the main queue
    /// - seeAlso: [Roles](https://developer.apple.com/library/mac/documentation/AppKit/Reference/NSAccessibility_Protocol_Reference/index.html#//apple_ref/doc/constant_group/Roles)
    public func role(completion: @escaping (Result<Role?, Error>) -> Void) {
        self.attribute(.role) { (result: Result<String?, Error>) in
            switch result {
            case .success(let str):
                if let str = str {
                    completion(.success(Role(rawValue: str)))
                } else {
                    completion(.success(nil))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Returns the subrole of the element asynchronously.
    /// - parameter completion: Called with the result on the main queue
    /// - seeAlso: [Subroles](https://developer.apple.com/library/mac/documentation/AppKit/Reference/NSAccessibility_Protocol_Reference/index.html#//apple_ref/doc/constant_group/Subroles)
    public func subrole(completion: @escaping (Result<Subrole?, Error>) -> Void) {
        self.attribute(.subrole) { (result: Result<String?, Error>) in
            switch result {
            case .success(let str):
                if let str = str {
                    completion(.success(Subrole(rawValue: str)))
                } else {
                    completion(.success(nil))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}
