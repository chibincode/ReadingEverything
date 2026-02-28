import Cocoa
import SwiftUI

struct HotkeyRecorderView: View {
    @Binding var combo: KeyCombo
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var recordingHint: String?
    private let modifierOnlyKeyCodes: Set<UInt16> = [54, 55, 56, 58, 59, 60, 61, 62]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(combo.displayString.isEmpty ? "None" : combo.displayString)
                    .font(.system(size: 12, weight: .medium))
                    .frame(minWidth: 120, alignment: .leading)
                Button(isRecording ? "Press keys…" : "Record") {
                    toggleRecording()
                }
            }
            if let recordingHint, !recordingHint.isEmpty {
                Text(recordingHint)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
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
        recordingHint = "Press modifier + key"
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 {
                recordingHint = nil
                stopRecording()
                return nil
            }

            let flags = event.modifierFlags.intersection(.relevant)
            guard !flags.isEmpty else {
                recordingHint = "Use modifier + key, e.g. Ctrl+R"
                return nil
            }
            guard !modifierOnlyKeyCodes.contains(event.keyCode) else {
                recordingHint = "Modifier-only hotkeys are not allowed"
                return nil
            }

            let newCombo = KeyCombo(keyCode: event.keyCode, modifiers: flags)
            combo = newCombo
            recordingHint = nil
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        recordingHint = nil
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
