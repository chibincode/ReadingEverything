import ApplicationServices
import Cocoa

final class HoverTextFetcher {
    func targetUnderMouse() -> ReadTarget? {
        let mouse = NSEvent.mouseLocation
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName
        let system = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(system, Float(mouse.x), Float(mouse.y), &element)
        guard result == .success, let target = element else { return nil }
        guard !isElementFromThisApp(target) else { return nil }

        // Preferred path: ask AX for the text range at current pointer position.
        if let precise = targetForPosition(in: target, point: mouse, appName: appName) {
            return precise
        }

        // Fallback path: walk up a few parent nodes and probe common text attributes.
        var current: AXUIElement? = target
        for _ in 0..<6 {
            guard let node = current else { break }
            if isElementFromThisApp(node) {
                current = AccessibilityHelpers.copyAttribute(node, kAXParentAttribute)
                continue
            }
            if let hit = fallbackTarget(from: node, appName: appName) {
                return hit
            }
            current = AccessibilityHelpers.copyAttribute(node, kAXParentAttribute)
        }

        return nil
    }

    private func targetForPosition(in element: AXUIElement, point: CGPoint, appName: String?) -> ReadTarget? {
        var mutablePoint = point
        guard let pointValue = AXValueCreate(.cgPoint, &mutablePoint) else { return nil }
        guard let rangeValue: AXValue = AccessibilityHelpers.copyParameterizedAttribute(
            element,
            kAXRangeForPositionParameterizedAttribute,
            pointValue
        ) else { return nil }

        let rect: CGRect?
        if let boundsValue: AXValue = AccessibilityHelpers.copyParameterizedAttribute(
            element,
            kAXBoundsForRangeParameterizedAttribute,
            rangeValue
        ) {
            rect = normalizeRectIfNeeded(AccessibilityHelpers.rectFromAXValue(boundsValue), focusedElement: element)
        } else {
            rect = nil
        }

        if let value: String = AccessibilityHelpers.copyParameterizedAttribute(
            element,
            kAXStringForRangeParameterizedAttribute,
            rangeValue
        ) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return ReadTarget(text: clampLength(trimmed), rect: rect, source: .hoverRange, appName: appName)
            }
        }

        if let value: NSAttributedString = AccessibilityHelpers.copyParameterizedAttribute(
            element,
            kAXAttributedStringForRangeParameterizedAttribute,
            rangeValue
        ) {
            let trimmed = value.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return ReadTarget(text: clampLength(trimmed), rect: rect, source: .hoverRange, appName: appName)
            }
        }

        return nil
    }

    private func fallbackTarget(from element: AXUIElement, appName: String?) -> ReadTarget? {
        let candidates: [String] = [
            kAXValueAttribute,
            kAXTitleAttribute,
            kAXDescriptionAttribute,
            kAXHelpAttribute
        ]

        for attribute in candidates {
            if let value: String = AccessibilityHelpers.copyAttribute(element, attribute) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return ReadTarget(
                        text: clampLength(trimmed),
                        rect: rectForElement(element),
                        source: .hoverFallback,
                        appName: appName
                    )
                }
            }
        }

        return nil
    }

    private func rectForElement(_ element: AXUIElement) -> CGRect? {
        guard let posValue: AXValue = AccessibilityHelpers.copyAttribute(element, kAXPositionAttribute),
              let sizeValue: AXValue = AccessibilityHelpers.copyAttribute(element, kAXSizeAttribute),
              let origin = AccessibilityHelpers.pointFromAXValue(posValue),
              let size = AccessibilityHelpers.sizeFromAXValue(sizeValue) else {
            return nil
        }
        return CGRect(origin: origin, size: size)
    }

    private func clampLength(_ text: String) -> String {
        let maxLength = 2000
        if text.count > maxLength {
            return String(text.prefix(maxLength))
        }
        return text
    }

    private func isElementFromThisApp(_ element: AXUIElement) -> Bool {
        var pid: pid_t = 0
        let result = AXUIElementGetPid(element, &pid)
        guard result == .success else { return false }
        return pid == ProcessInfo.processInfo.processIdentifier
    }
}

private func normalizeRectIfNeeded(_ rect: CGRect?, focusedElement: AXUIElement) -> CGRect? {
    guard let rect else { return nil }
    guard let window: AXUIElement = AccessibilityHelpers.copyAttribute(focusedElement, kAXWindowAttribute) else {
        return rect
    }
    guard let posValue: AXValue = AccessibilityHelpers.copyAttribute(window, kAXPositionAttribute),
          let sizeValue: AXValue = AccessibilityHelpers.copyAttribute(window, kAXSizeAttribute),
          let origin = AccessibilityHelpers.pointFromAXValue(posValue),
          let size = AccessibilityHelpers.sizeFromAXValue(sizeValue) else {
        return rect
    }

    let windowFrame = CGRect(origin: origin, size: size)
    if windowFrame.contains(rect) {
        return rect
    }

    if rect.origin.x >= 0,
       rect.origin.y >= 0,
       rect.maxX <= windowFrame.width,
       rect.maxY <= windowFrame.height {
        return CGRect(
            x: rect.origin.x + windowFrame.origin.x,
            y: rect.origin.y + windowFrame.origin.y,
            width: rect.width,
            height: rect.height
        )
    }

    return rect
}
