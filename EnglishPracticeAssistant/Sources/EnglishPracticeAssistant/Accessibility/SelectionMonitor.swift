import ApplicationServices
import Cocoa

final class SelectionMonitor: NSObject {
    var onSelectionChange: ((SelectionSnapshot?) -> Void)?

    private let pollInterval: TimeInterval = 0.25
    private var observer: AXObserver?
    private var observedApp: AXUIElement?
    private var observedAppPID: pid_t?
    private var pollTimer: Timer?

    func start() {
        stop()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appChanged(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appChanged(_:)), name: NSWorkspace.didDeactivateApplicationNotification, object: nil)
        startPolling()
        attachToFrontmostApp()
        fetchSelection()
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        pollTimer?.invalidate()
        pollTimer = nil
        detachObserver()
    }

    deinit {
        stop()
    }

    @objc private func appChanged(_ notification: Notification) {
        refreshObservedAppIfNeeded()
        fetchSelection()
    }

    private func attachToFrontmostApp() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        guard app.processIdentifier != observedAppPID else { return }

        detachObserver()
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        observedApp = axApp
        observedAppPID = app.processIdentifier

        var newObserver: AXObserver?
        let result = AXObserverCreate(app.processIdentifier, observerCallback, &newObserver)
        guard result == .success, let observer = newObserver else {
            // Some apps may reject AXObserver; polling still provides selection updates.
            return
        }
        self.observer = observer

        AXObserverAddNotification(observer, axApp, kAXSelectedTextChangedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
        AXObserverAddNotification(observer, axApp, kAXFocusedUIElementChangedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    private func detachObserver() {
        if let observer = observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        observedApp = nil
        observedAppPID = nil
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refreshObservedAppIfNeeded()
                self.fetchSelection()
            }
        }
        pollTimer?.tolerance = pollInterval * 0.4
    }

    private func refreshObservedAppIfNeeded() {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        if observedAppPID != pid {
            attachToFrontmostApp()
        }
    }

    func fetchSelection() {
        onSelectionChange?(currentSelection())
    }

    func currentSelection() -> SelectionSnapshot? {
        guard let focused = focusedElement() else {
            return nil
        }

        let markerRangeValue: AXValue? = AccessibilityHelpers.copyAttribute(focused, "AXSelectedTextMarkerRange")
        let rangeValue: AXValue? = AccessibilityHelpers.copyAttribute(focused, kAXSelectedTextRangeAttribute)
        if let rangeValue,
           let range = AccessibilityHelpers.rangeFromAXValue(rangeValue),
           range.length <= 0 {
            return nil
        }

        var text: String = AccessibilityHelpers.copyAttribute(focused, kAXSelectedTextAttribute) ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let rangeValue {
            if let rangedText: String = AccessibilityHelpers.copyParameterizedAttribute(
                focused,
                kAXStringForRangeParameterizedAttribute,
                rangeValue
            ) {
                text = rangedText
            }
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        var rect: CGRect? = nil
        if let markerRangeValue,
           let markerBoundsValue: AXValue = AccessibilityHelpers.copyParameterizedAttribute(
            focused,
            "AXBoundsForTextMarkerRange",
            markerRangeValue
           ) {
            rect = AccessibilityHelpers.rectFromAXValue(markerBoundsValue)
            rect = normalizeRectIfNeeded(rect, focusedElement: focused)
        }

        if rect == nil, let rangeValue,
           let boundsValue: AXValue = AccessibilityHelpers.copyParameterizedAttribute(
            focused,
            kAXBoundsForRangeParameterizedAttribute,
            rangeValue
           ) {
            rect = AccessibilityHelpers.rectFromAXValue(boundsValue)
            rect = normalizeRectIfNeeded(rect, focusedElement: focused)
        }

        if rect == nil {
            rect = focusedElementRect(focused)
            rect = normalizeRectIfNeeded(rect, focusedElement: focused)
        }

        if let candidate = rect, candidate.width < 2 || candidate.height < 2 {
            rect = nil
        }

        return SelectionSnapshot(
            text: text,
            rect: rect,
            appName: NSWorkspace.shared.frontmostApplication?.localizedName
        )
    }

    private func focusedElement() -> AXUIElement? {
        let candidate: AXUIElement? = {
            if let app = currentFrontmostAppElement(),
               let focused: AXUIElement = AccessibilityHelpers.copyAttribute(app, kAXFocusedUIElementAttribute) {
                return focused
            }

            if let app = observedApp,
               let focused: AXUIElement = AccessibilityHelpers.copyAttribute(app, kAXFocusedUIElementAttribute) {
                return focused
            }

            let systemWide = AXUIElementCreateSystemWide()
            let focused: AXUIElement? = AccessibilityHelpers.copyAttribute(systemWide, kAXFocusedUIElementAttribute)
            return focused
        }()

        guard let focused = candidate else { return nil }
        var focusedPID: pid_t = 0
        AXUIElementGetPid(focused, &focusedPID)
        if focusedPID == ProcessInfo.processInfo.processIdentifier {
            return nil
        }

        return focused
    }

    private func currentFrontmostAppElement() -> AXUIElement? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        return AXUIElementCreateApplication(pid)
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

private func focusedElementRect(_ element: AXUIElement) -> CGRect? {
    guard let posValue: AXValue = AccessibilityHelpers.copyAttribute(element, kAXPositionAttribute),
          let sizeValue: AXValue = AccessibilityHelpers.copyAttribute(element, kAXSizeAttribute),
          let origin = AccessibilityHelpers.pointFromAXValue(posValue),
          let size = AccessibilityHelpers.sizeFromAXValue(sizeValue) else {
        return nil
    }

    return CGRect(origin: origin, size: size)
}

private let observerCallback: AXObserverCallback = { _, _, _, refcon in
    guard let refcon else { return }
    let monitor = Unmanaged<SelectionMonitor>.fromOpaque(refcon).takeUnretainedValue()
    monitor.fetchSelection()
}
