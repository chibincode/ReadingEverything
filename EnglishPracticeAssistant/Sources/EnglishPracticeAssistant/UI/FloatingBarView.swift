import SwiftUI

struct FloatingBarView: View {
    @ObservedObject var appState: AppState
    let onDragStart: () -> Void
    let onDragChanged: () -> Void
    let onDragEnd: () -> Void

    @State private var dragGestureActive = false
    private let transitionDuration = 0.18

    private var mode: FloatingBarMode {
        appState.isReading ? .reading : .idle
    }

    var body: some View {
        HStack(spacing: 12) {
            PanelDragHandleView()
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { _ in
                            if !dragGestureActive {
                                dragGestureActive = true
                                onDragStart()
                            }
                            onDragChanged()
                        }
                        .onEnded { _ in
                            dragGestureActive = false
                            onDragEnd()
                        }
                )

            Divider()
                .frame(height: 16)

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

                Divider()
                    .frame(height: 16)
                    .transition(.opacity)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Button {
                        appState.translateSelection()
                    } label: {
                        actionLabel(
                            text: "Translate",
                            systemImage: "globe",
                            isRunning: appState.isTranslating
                        )
                    }
                    .buttonStyle(.borderless)
                    .disabled(appState.isTranslating)
                    .help("Translate selected text")

                    cancelActionButton(
                        isVisible: appState.isTranslating,
                        help: "Cancel translation"
                    ) {
                        appState.cancelTranslation()
                    }
                }
                .frame(width: 190, alignment: .leading)

                translateStatusRow
                    .frame(width: 190, alignment: .leading)
            }
            .frame(minWidth: 134, alignment: .leading)

            Divider()
                .frame(height: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Button {
                        appState.grammarCheck()
                    } label: {
                        actionLabel(
                            text: "Grammar Check",
                            systemImage: "text.badge.checkmark",
                            isRunning: appState.isGrammarChecking
                        )
                    }
                    .buttonStyle(.borderless)
                    .disabled(appState.isGrammarChecking)
                    .help("Grammar Check")

                    cancelActionButton(
                        isVisible: appState.isGrammarChecking,
                        help: "Cancel grammar check"
                    ) {
                        appState.cancelGrammarCheck()
                    }
                }
                .frame(width: 190, alignment: .leading)

                grammarStatusRow
                    .frame(width: 190, alignment: .leading)
            }
            .frame(minWidth: 134, alignment: .leading)

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
        .background(GlassSurfaceView(kind: .floatingBar, cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .fixedSize(horizontal: true, vertical: true)
        .animation(.easeInOut(duration: transitionDuration), value: mode)
    }

    @ViewBuilder
    private var translateStatusRow: some View {
        if let error = appState.translationInlineError, !error.isEmpty {
            feedbackRow(
                text: error,
                tone: .error,
                icon: "exclamationmark.circle.fill"
            )
            .help(error)
        } else if appState.showTranslationCancelledFlash {
            feedbackRow(
                text: "Cancelled",
                tone: .neutral,
                icon: "xmark.circle.fill"
            )
        } else if appState.showTranslationSuccessFlash {
            feedbackRow(
                text: "Done",
                tone: .success,
                icon: "checkmark.circle.fill"
            )
        }
    }

    @ViewBuilder
    private var grammarStatusRow: some View {
        if let error = appState.grammarInlineError, !error.isEmpty {
            feedbackRow(
                text: error,
                tone: .error,
                icon: "exclamationmark.circle.fill"
            )
            .help(error)
        } else if appState.showGrammarCancelledFlash {
            feedbackRow(
                text: "Cancelled",
                tone: .neutral,
                icon: "xmark.circle.fill"
            )
        } else if appState.showGrammarSuccessFlash {
            feedbackRow(
                text: "Done",
                tone: .success,
                icon: "checkmark.circle.fill"
            )
        }
    }

    private func actionLabel(text: String, systemImage: String, isRunning: Bool) -> some View {
        HStack(spacing: 6) {
            Group {
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .frame(width: 12, height: 12)

            Text(text)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cancelActionButton(
        isVisible: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(help)
        .frame(width: 14, height: 14)
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .accessibilityHidden(!isVisible)
    }

    private func feedbackRow(
        text: String,
        tone: FeedbackTone,
        icon: String?
    ) -> some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tone.color)
            }

            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tone.color)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
        .animation(.easeInOut(duration: 0.18), value: text)
    }
}

private enum FeedbackTone {
    case neutral
    case success
    case error

    var color: Color {
        switch self {
        case .neutral:
            return .secondary
        case .success:
            return .green
        case .error:
            return .red
        }
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
