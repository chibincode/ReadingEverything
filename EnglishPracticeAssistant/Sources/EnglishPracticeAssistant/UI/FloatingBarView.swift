import SwiftUI

struct FloatingBarView: View {
    @ObservedObject var appState: AppState
    private let transitionDuration = 0.18

    private var mode: FloatingBarMode {
        appState.isReading ? .reading : .idle
    }

    var body: some View {
        HStack(spacing: 12) {
            if mode == .reading {
                HStack(spacing: 6) {
                    ReadingWaveView()
                    Text("Reading")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(minWidth: 92, alignment: .leading)
                .transition(.opacity.combined(with: .move(edge: .leading)))

                Divider()
                    .frame(height: 16)
                    .transition(.opacity)
            }

            if mode == .idle {
                Button {
                    appState.readSelection()
                } label: {
                    Label("Read", systemImage: "speaker.wave.2.fill")
                }
                .buttonStyle(.borderless)
                .labelStyle(.titleAndIcon)
                .frame(minWidth: 92, alignment: .leading)
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }

            Button {
                appState.grammarRephrase()
            } label: {
                Label("Grammar", systemImage: "text.badge.checkmark")
            }
            .buttonStyle(.borderless)
            .labelStyle(.titleAndIcon)
            .frame(minWidth: 106, alignment: .leading)

            if mode == .reading {
                Divider()
                    .frame(height: 16)
                    .transition(.opacity)

                Button {
                    appState.stopReading()
                } label: {
                    Label("Stop", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .labelStyle(.titleAndIcon)
                .help("Stop (Esc)")
                .frame(minWidth: 72, alignment: .leading)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .fixedSize(horizontal: true, vertical: true)
        .animation(.easeInOut(duration: transitionDuration), value: mode)
    }
}

private struct ReadingWaveView: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { index in
                    let phase = (t * 8.0) + Double(index) * 0.9
                    let amplitude = (sin(phase) + 1) * 0.5
                    Capsule(style: .continuous)
                        .fill(Color.blue)
                        .frame(width: 3, height: 6 + (amplitude * 10))
                }
            }
            .frame(width: 20, height: 16)
        }
    }
}

private enum FloatingBarMode {
    case idle
    case reading
}
