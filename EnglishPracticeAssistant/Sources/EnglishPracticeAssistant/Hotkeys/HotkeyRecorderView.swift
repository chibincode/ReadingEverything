import Cocoa
import SwiftUI

struct HotkeyRecorderView: View {
    @Binding var combo: KeyCombo
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(combo.displayString.isEmpty ? "None" : combo.displayString)
                .font(.system(size: 12, weight: .medium))
                .frame(minWidth: 120, alignment: .leading)
            Button(isRecording ? "Press keys…" : "Record") {
                toggleRecording()
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                if let modifierCombo = KeyCombo.fromFlagsChanged(event) {
                    combo = modifierCombo
                    stopRecording()
                    return nil
                }
                return event
            }

            let flags = event.modifierFlags.intersection(.relevant)
            let newCombo = KeyCombo(keyCode: event.keyCode, modifiers: flags)
            combo = newCombo
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

extension KeyCombo {
    static func fromFlagsChanged(_ event: NSEvent) -> KeyCombo? {
        let flags = event.modifierFlags.intersection(.relevant)
        if flags.contains(.control) && event.keyCode == 59 {
            return KeyCombo.modifierOnly(.control)
        }
        if flags.contains(.option) && event.keyCode == 58 {
            return KeyCombo.modifierOnly(.option)
        }
        if flags.contains(.shift) && event.keyCode == 56 {
            return KeyCombo.modifierOnly(.shift)
        }
        if flags.contains(.command) && event.keyCode == 55 {
            return KeyCombo.modifierOnly(.command)
        }
        return nil
    }
}
