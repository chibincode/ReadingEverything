import Cocoa
import Foundation

final class HotkeyManager {
    var onReadSelection: (() -> Void)?
    var onTranslate: (() -> Void)?
    var onGrammarCheck: (() -> Void)?
    var onMouseUp: ((CGPoint) -> Void)?
    var onStopReading: (() -> Void)?
    var canStopReading: (() -> Bool)?
    var onHotkeySystemUnavailable: ((String) -> Void)?
    var onHotkeySystemRecovered: (() -> Void)?

    private var bindings: HotkeyBindings
    private var eventTap: CFMachPort?
    private var lastTrigger = [String: Date]()
    private var retryTimer: Timer?
    private var lastAvailabilityMessage: String?
    private(set) var isEventTapReady = false

    init() {
        bindings = .defaultBindings
    }

    deinit {
        retryTimer?.invalidate()
    }

    func start(bindings: HotkeyBindings) {
        self.bindings = bindings
        ensureEventTapInstalled()
    }

    func update(bindings: HotkeyBindings) {
        self.bindings = bindings
        ensureEventTapInstalled()
    }

    func ensureEventTapInstalled() {
        if let existingTap = eventTap {
            if !CGEvent.tapIsEnabled(tap: existingTap) {
                CGEvent.tapEnable(tap: existingTap, enable: true)
            }

            if CGEvent.tapIsEnabled(tap: existingTap) {
                markHotkeyReady()
            } else {
                markHotkeyUnavailable(reason: hotkeyUnavailableReason())
                scheduleRetry()
            }
            return
        }

        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
        guard let createdTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: eventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            markHotkeyUnavailable(reason: hotkeyUnavailableReason())
            scheduleRetry()
            return
        }

        eventTap = createdTap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, createdTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: createdTap, enable: true)
        markHotkeyReady()
    }

    private func markHotkeyUnavailable(reason: String) {
        isEventTapReady = false
        if lastAvailabilityMessage != reason {
            lastAvailabilityMessage = reason
            onHotkeySystemUnavailable?(reason)
        }
    }

    private func markHotkeyReady() {
        let shouldNotifyRecovery = !isEventTapReady || lastAvailabilityMessage != nil
        isEventTapReady = true
        retryTimer?.invalidate()
        retryTimer = nil
        lastAvailabilityMessage = nil
        if shouldNotifyRecovery {
            onHotkeySystemRecovered?()
        }
    }

    private func scheduleRetry() {
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.ensureEventTapInstalled()
        }
        retryTimer?.tolerance = 0.5
    }

    private func hotkeyUnavailableReason() -> String {
        if !PermissionCenter.inputMonitoringEnabled {
            return "Hotkeys unavailable. Enable Input Monitoring in Settings."
        }
        return "Hotkeys unavailable. Failed to install event tap."
    }

    func handle(event: CGEvent, type: CGEventType) -> Bool {
        switch type {
        case .keyDown:
            return handleKeyDown(event)
        case .leftMouseUp:
            // Use AppKit's global coordinate space for UI anchoring.
            let point = NSEvent.mouseLocation
            trigger(key: "mouseUp") { [weak self] in self?.onMouseUp?(point) }
            return false
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // Keep the tap alive if the system temporarily disables it.
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
                markHotkeyReady()
            }
            return false
        default:
            return false
        }
    }

    private func handleKeyDown(_ event: CGEvent) -> Bool {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)).intersection(.relevant)

        if keyCode == 53 {
            if canStopReading?() == false {
                return false
            }
            trigger(key: "stopReading") { [weak self] in self?.onStopReading?() }
            return true
        }
        if matches(combo: bindings.readSelection, keyCode: keyCode, flags: flags) {
            trigger(key: "readSelection") { [weak self] in self?.onReadSelection?() }
            return true
        }
        if matches(combo: bindings.translation, keyCode: keyCode, flags: flags) {
            trigger(key: "translation") { [weak self] in self?.onTranslate?() }
            return true
        }
        if matches(combo: bindings.grammar, keyCode: keyCode, flags: flags) {
            trigger(key: "grammarCheck") { [weak self] in self?.onGrammarCheck?() }
            return true
        }
        return false
    }

    private func matches(combo: KeyCombo, keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        if combo.isModifierOnly {
            return false
        }
        return combo.keyCode == keyCode && combo.modifierFlags.intersection(.relevant) == flags
    }

    private func trigger(key: String, action: () -> Void) {
        let now = Date()
        if let last = lastTrigger[key], now.timeIntervalSince(last) < 0.25 {
            return
        }
        lastTrigger[key] = now
        action()
    }
}

private let eventCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
    let consumed = manager.handle(event: event, type: type)
    if consumed {
        return nil
    }
    return Unmanaged.passUnretained(event)
}
