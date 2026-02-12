import ApplicationServices
import Cocoa

enum AccessibilityHelpers {
    static func copyAttribute<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? T
    }

    static func copyParameterizedAttribute<T>(_ element: AXUIElement, _ attribute: String, _ parameter: AnyObject) -> T? {
        var value: AnyObject?
        let result = AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, parameter, &value)
        guard result == .success else { return nil }
        return value as? T
    }

    static func rectFromAXValue(_ value: AXValue) -> CGRect? {
        var rect = CGRect.zero
        if AXValueGetValue(value, .cgRect, &rect) {
            return rect
        }
        return nil
    }

    static func pointFromAXValue(_ value: AXValue) -> CGPoint? {
        var point = CGPoint.zero
        if AXValueGetValue(value, .cgPoint, &point) {
            return point
        }
        return nil
    }

    static func sizeFromAXValue(_ value: AXValue) -> CGSize? {
        var size = CGSize.zero
        if AXValueGetValue(value, .cgSize, &size) {
            return size
        }
        return nil
    }

    static func rangeFromAXValue(_ value: AXValue) -> CFRange? {
        var range = CFRange(location: 0, length: 0)
        if AXValueGetValue(value, .cfRange, &range) {
            return range
        }
        return nil
    }
}
