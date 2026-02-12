import Cocoa
import Foundation

final class HotkeyManager {
    var onHoverRead: (() -> Void)?
    var onReadSelection: (() -> Void)?
    var onGrammar: (() -> Void)?
    var onMouseUp: ((CGPoint) -> Void)?
    var onStopReading: (() -> Void)?

    private var bindings: HotkeyBindings
    private var eventTap: CFMachPort?
    private var lastTrigger = [String: Date]()
    private var lastHoverModifierDown = false

    init() {
        bindings = HotkeyBindings(
            hoverRead: KeyCombo.modifierOnly(.control),
            readSelection: KeyCombo(keyCode: 15, modifiers: [.option]),
            grammar: KeyCombo(keyCode: 5, modifiers: [.option])
        )
    }

    func start(bindings: HotkeyBindings) {
        self.bindings = bindings
        installEventTap()
    }

    func update(bindings: HotkeyBindings) {
        self.bindings = bindings
    }

    private func installEventTap() {
        guard eventTap == nil else { return }
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: eventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else { return }
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func handle(event: CGEvent, type: CGEventType) {
        switch type {
        case .keyDown:
            handleKeyDown(event)
        case .flagsChanged:
            handleFlagsChanged(event)
        case .leftMouseUp:
            // Use AppKit's global coordinate space for UI anchoring.
            let point = NSEvent.mouseLocation
            trigger(key: "mouseUp") { [weak self] in self?.onMouseUp?(point) }
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // Keep the tap alive if the system temporarily disables it.
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
        default:
            break
        }
    }

    private func handleKeyDown(_ event: CGEvent) {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)).intersection(.relevant)

        if keyCode == 53 {
            trigger(key: "stopReading") { [weak self] in self?.onStopReading?() }
        } else if matches(combo: bindings.readSelection, keyCode: keyCode, flags: flags) {
            trigger(key: "readSelection") { [weak self] in self?.onReadSelection?() }
        } else if matches(combo: bindings.grammar, keyCode: keyCode, flags: flags) {
            trigger(key: "grammar") { [weak self] in self?.onGrammar?() }
        }
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)).intersection(.relevant)
        let hoverModifier = bindings.hoverRead.modifierFlags.intersection(.relevant)
        guard !hoverModifier.isEmpty else { return }
        let isHoverModifierDown = flags.contains(hoverModifier)
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let isModifierPressEvent = isModifierKeyEvent(keyCode: keyCode, for: hoverModifier)

        if bindings.hoverRead.isModifierOnly && isHoverModifierDown && (isModifierPressEvent || !lastHoverModifierDown) {
            trigger(key: "hoverRead") { [weak self] in self?.onHoverRead?() }
        }
        lastHoverModifierDown = isHoverModifierDown
    }

    private func isModifierKeyEvent(keyCode: UInt16, for modifiers: NSEvent.ModifierFlags) -> Bool {
        if modifiers == .control {
            return keyCode == 59 || keyCode == 62
        }
        if modifiers == .option {
            return keyCode == 58 || keyCode == 61
        }
        if modifiers == .shift {
            return keyCode == 56 || keyCode == 60
        }
        if modifiers == .command {
            return keyCode == 55 || keyCode == 54
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
    manager.handle(event: event, type: type)
    return Unmanaged.passUnretained(event)
}
