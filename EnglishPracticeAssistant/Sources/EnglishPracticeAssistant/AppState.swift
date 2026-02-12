import Combine
import CoreGraphics
import Foundation

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var selection: SelectionSnapshot?
    @Published var grammarResult: GrammarResult?
    @Published var statusMessage: String?
    @Published var isReading = false
    @Published var readingAnchorRect: CGRect?
    @Published var activeReadSource: ReadSource?
    @Published var detectionPreview: DetectionPreview?
    @Published var selectionCommitPoint: CGPoint?
    @Published var floatingBarDebug: FloatingBarDebugInfo?

    let settings = SettingsStore.shared
    private let selectionMonitor = SelectionMonitor()
    private let hoverTextFetcher = HoverTextFetcher()
    private let hotkeyManager = HotkeyManager()
    private let speechManager = SpeechManager()
    private let aiClient = AIClient()

    private var cancellables = Set<AnyCancellable>()
    private var previewClearTask: Task<Void, Never>?
    private var selectionStabilizeTask: Task<Void, Never>?
    private var selectionClearTask: Task<Void, Never>?
    private var selectionMouseUpRefreshTask: Task<Void, Never>?
    private var selectionCommitPointClearTask: Task<Void, Never>?
    private var latestSelectionCandidate: SelectionSnapshot?
    private var pendingSelectionCandidate: SelectionSnapshot?
    private let selectionStabilizeDelayNs: UInt64 = 150_000_000
    private let selectionClearGraceDelayNs: UInt64 = 80_000_000
    private let selectionMouseUpRefreshDelayNs: UInt64 = 90_000_000
    private var suppressNextPlaybackEndedSelectionRefresh = false
    private var suppressStaleSelectionAfterMouseUp = false
    private var suppressedSelectionSignature: String?

    var showToast: ((String) -> Void)?
    var shouldIgnoreMouseUp: ((CGPoint) -> Bool)?

    func start() {
        selectionMonitor.onSelectionChange = { [weak self] snapshot in
            Task { @MainActor in
                guard let self else { return }
                guard !self.isReading else { return }
                self.scheduleSelectionPublication(snapshot)
            }
        }
        selectionMonitor.start()

        speechManager.onPlaybackStarted = { [weak self] in
            self?.selectionStabilizeTask?.cancel()
            self?.selectionClearTask?.cancel()
            self?.latestSelectionCandidate = nil
            self?.isReading = true
        }
        speechManager.onPlaybackEnded = { [weak self] in
            guard let self else { return }
            self.isReading = false
            self.activeReadSource = nil
            self.readingAnchorRect = nil
            if self.suppressNextPlaybackEndedSelectionRefresh {
                self.suppressNextPlaybackEndedSelectionRefresh = false
            } else {
                self.scheduleSelectionPublication(self.selectionMonitor.currentSelection())
            }
        }

        hotkeyManager.onHoverRead = { [weak self] in
            Task { @MainActor in
                self?.readFromHotkey()
            }
        }
        hotkeyManager.onReadSelection = { [weak self] in
            Task { @MainActor in
                self?.readSelection()
            }
        }
        hotkeyManager.onGrammar = { [weak self] in
            Task { @MainActor in
                self?.grammarRephrase()
            }
        }
        hotkeyManager.onStopReading = { [weak self] in
            Task { @MainActor in
                self?.stopReading()
            }
        }
        hotkeyManager.onMouseUp = { [weak self] point in
            Task { @MainActor in
                if self?.shouldIgnoreMouseUp?(point) == true {
                    return
                }
                self?.handleGlobalMouseUp(point: point)
            }
        }
        hotkeyManager.start(bindings: settings.hotkeyBindings)

        settings.$hotkeyBindings
            .receive(on: RunLoop.main)
            .sink { [weak self] bindings in
                self?.hotkeyManager.update(bindings: bindings)
            }
            .store(in: &cancellables)
    }

    func readSelection() {
        guard let target = resolveSelectionTarget(refresh: true) else {
            showToast?("No selected text")
            return
        }
        startReading(target)
    }

    func readFromHotkey() {
        // Ignore repeated start triggers while already reading to prevent re-anchor drift.
        guard !isReading else { return }

        if let selectionTarget = resolveSelectionTarget(refresh: true) {
            startReading(selectionTarget)
            return
        }

        if let hoverTarget = hoverTextFetcher.targetUnderMouse() {
            startReading(hoverTarget)
            return
        }

        showToast?("No readable text here")
    }

    func grammarRephrase() {
        guard let text = resolveSelectionTarget(refresh: true)?.text else {
            showToast?("No selected text")
            return
        }
        Task {
            do {
                let result = try await aiClient.grammarRephrase(text: text, config: settings.aiConfig)
                await MainActor.run {
                    self.grammarResult = result
                }
            } catch {
                await MainActor.run {
                    self.showToast?("AI request failed")
                }
            }
        }
    }

    func stopReading() {
        let wasReading = isReading
        if wasReading {
            suppressNextPlaybackEndedSelectionRefresh = true
        }
        speechManager.stop()
        isReading = false
        activeReadSource = nil
        readingAnchorRect = nil
        selection = nil
        selectionCommitPoint = nil
        floatingBarDebug = nil
        latestSelectionCandidate = nil
        pendingSelectionCandidate = nil
        selectionStabilizeTask?.cancel()
        selectionStabilizeTask = nil
        selectionClearTask?.cancel()
        selectionMouseUpRefreshTask?.cancel()
        selectionCommitPointClearTask?.cancel()

        if wasReading {
            scheduleSelectionPublication(selectionMonitor.currentSelection())
        }
    }

    private func resolveSelectionTarget(refresh: Bool) -> ReadTarget? {
        let snapshot: SelectionSnapshot?
        if refresh {
            snapshot = selectionMonitor.currentSelection()
            selection = snapshot
        } else {
            snapshot = selection
        }

        guard let snapshot else { return nil }
        let trimmed = snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return ReadTarget(text: trimmed, rect: snapshot.rect, source: .selection, appName: snapshot.appName)
    }

    private func startReading(_ target: ReadTarget) {
        activeReadSource = target.source
        readingAnchorRect = target.rect ?? selection?.rect
        isReading = true

        if settings.showDetectionOverlay {
            showDetectionPreview(for: target)
        }

        speak(text: target.text)
    }

    private func showDetectionPreview(for target: ReadTarget) {
        previewClearTask?.cancel()
        detectionPreview = DetectionPreview(rect: target.rect, source: target.source)

        previewClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.detectionPreview = nil
            }
        }
    }

    private func speak(text: String) {
        Task {
            do {
                if settings.useAITTS {
                    let audioData = try await aiClient.ttsAudio(
                        text: text,
                        config: settings.aiConfig,
                        preset: settings.aiPreset
                    )
                    try speechManager.play(audioData: audioData)
                } else {
                    try speechManager.speakSystem(text: text)
                }
            } catch {
                do {
                    try speechManager.speakSystem(text: text)
                } catch {
                    await MainActor.run {
                        self.showToast?("Speech failed")
                        self.isReading = false
                        self.activeReadSource = nil
                        self.readingAnchorRect = nil
                    }
                }
            }
        }
    }

    private func scheduleSelectionPublication(_ snapshot: SelectionSnapshot?) {
        if let snapshot {
            let incomingSignature = selectionSignature(for: snapshot)
            if suppressStaleSelectionAfterMouseUp, incomingSignature == suppressedSelectionSignature {
                // Suppress at most one stale post-click echo.
                suppressStaleSelectionAfterMouseUp = false
                suppressedSelectionSignature = nil
                return
            }
            suppressStaleSelectionAfterMouseUp = false
            suppressedSelectionSignature = nil

            selectionClearTask?.cancel()

            if selection == snapshot {
                latestSelectionCandidate = snapshot
                pendingSelectionCandidate = nil
                selectionStabilizeTask?.cancel()
                selectionStabilizeTask = nil
                return
            }

            if pendingSelectionCandidate == snapshot, selectionStabilizeTask != nil {
                latestSelectionCandidate = snapshot
                return
            }

            latestSelectionCandidate = snapshot
            pendingSelectionCandidate = snapshot
            selectionStabilizeTask?.cancel()

            selectionStabilizeTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: self?.selectionStabilizeDelayNs ?? 300_000_000)
                guard let self, !Task.isCancelled else { return }
                guard !self.isReading else { return }
                guard self.pendingSelectionCandidate == snapshot else { return }
                self.selection = snapshot
                self.selectionStabilizeTask = nil
                self.pendingSelectionCandidate = nil
            }
            return
        }

        selectionClearTask?.cancel()
        selectionClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.selectionClearGraceDelayNs ?? 80_000_000)
            guard let self, !Task.isCancelled else { return }
            guard !self.isReading else { return }
            if let recovered = self.selectionMonitor.currentSelection() {
                self.scheduleSelectionPublication(recovered)
                return
            }

            self.latestSelectionCandidate = nil
            self.pendingSelectionCandidate = nil
            self.selectionStabilizeTask?.cancel()
            self.selectionStabilizeTask = nil
            self.selection = nil
            self.selectionCommitPoint = nil
        }
    }

    private func handleGlobalMouseUp(point: CGPoint) {
        guard !isReading else { return }

        // Clicking outside should dismiss current bar immediately.
        suppressStaleSelectionAfterMouseUp = true
        suppressedSelectionSignature = selection.map { selectionSignature(for: $0) }
        selection = nil
        selectionCommitPoint = nil
        floatingBarDebug = nil
        latestSelectionCandidate = nil
        pendingSelectionCandidate = nil
        selectionStabilizeTask?.cancel()
        selectionStabilizeTask = nil
        selectionClearTask?.cancel()
        selectionMouseUpRefreshTask?.cancel()

        selectionMouseUpRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.selectionMouseUpRefreshDelayNs ?? 90_000_000)
            guard let self, !Task.isCancelled else { return }
            guard !self.isReading else { return }
            let refreshed = self.selectionMonitor.currentSelection()
            if refreshed != nil {
                self.selectionCommitPoint = point
                self.selectionCommitPointClearTask?.cancel()
                self.selectionCommitPointClearTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    guard let self, !Task.isCancelled else { return }
                    self.selectionCommitPoint = nil
                }
            } else {
                self.selectionCommitPoint = nil
            }
            self.scheduleSelectionPublication(refreshed)
        }
    }

    private func selectionSignature(for snapshot: SelectionSnapshot) -> String {
        let trimmed = snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(snapshot.appName ?? "unknown")|\(trimmed)"
    }
}
