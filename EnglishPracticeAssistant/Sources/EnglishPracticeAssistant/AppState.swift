import Combine
import CoreGraphics
import Foundation

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var selection: SelectionSnapshot?
    @Published var grammarCheckResult: GrammarCheckResult?
    @Published var translationResult: TranslationResult?
    @Published var activeResultPanel: ResultPanelKind = .grammar
    @Published var selectedGrammarOption: GrammarOption = .cleanUp
    @Published var statusMessage: String?
    @Published var isGrammarChecking = false
    @Published var isTranslating = false
    @Published var grammarInlineError: String?
    @Published var translationInlineError: String?
    @Published var showGrammarSuccessFlash = false
    @Published var showTranslationSuccessFlash = false
    @Published var showGrammarCancelledFlash = false
    @Published var showTranslationCancelledFlash = false
    @Published var isReading = false
    @Published var readingAnchorRect: CGRect?
    @Published var activeReadSource: ReadSource?
    @Published var detectionPreview: DetectionPreview?
    @Published var selectionCommitPoint: CGPoint?
    @Published var floatingBarDebug: FloatingBarDebugInfo?
    @Published var hotkeyStatusMessage: String?

    let settings = SettingsStore.shared
    private let selectionMonitor = SelectionMonitor()
    private let hotkeyManager = HotkeyManager()
    private let speechManager = SpeechManager()
    private let aiClient = AIClient()

    private var cancellables = Set<AnyCancellable>()
    private var previewClearTask: Task<Void, Never>?
    private var selectionStabilizeTask: Task<Void, Never>?
    private var selectionClearTask: Task<Void, Never>?
    private var selectionMouseUpRefreshTask: Task<Void, Never>?
    private var selectionCommitPointClearTask: Task<Void, Never>?
    private var grammarCheckTask: Task<Void, Never>?
    private var translationTask: Task<Void, Never>?
    private var grammarSuccessFlashTask: Task<Void, Never>?
    private var translationSuccessFlashTask: Task<Void, Never>?
    private var grammarCancelledFlashTask: Task<Void, Never>?
    private var translationCancelledFlashTask: Task<Void, Never>?
    private var grammarCheckRequestID: UInt64 = 0
    private var translationRequestID: UInt64 = 0
    private var latestSelectionCandidate: SelectionSnapshot?
    private var pendingSelectionCandidate: SelectionSnapshot?
    private let selectionStabilizeDelayNs: UInt64 = 150_000_000
    private let selectionClearGraceDelayNs: UInt64 = 80_000_000
    private let selectionMouseUpRefreshDelayNs: UInt64 = 90_000_000
    private var suppressNextPlaybackEndedSelectionRefresh = false
    private var suppressStaleSelectionAfterMouseUp = false
    private var suppressedSelectionSignature: String?
    private var recentSelectionTarget: ReadTarget?
    private var recentSelectionUpdatedAt: Date?
    private let recentSelectionMaxAge: TimeInterval = 1.5
    private var lastHotkeyWarningMessage: String?
    private var lastHotkeyWarningAt: Date?

    var showToast: ((String) -> Void)?
    var openSettings: (() -> Void)?
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

        hotkeyManager.onReadSelection = { [weak self] in
            Task { @MainActor in
                self?.readSelection()
            }
        }
        hotkeyManager.onTranslate = { [weak self] in
            Task { @MainActor in
                self?.translateSelection()
            }
        }
        hotkeyManager.onGrammarCheck = { [weak self] in
            Task { @MainActor in
                self?.grammarCheck()
            }
        }
        hotkeyManager.onStopReading = { [weak self] in
            Task { @MainActor in
                self?.stopReading()
            }
        }
        hotkeyManager.onHotkeySystemUnavailable = { [weak self] message in
            Task { @MainActor in
                self?.handleHotkeySystemUnavailable(message)
            }
        }
        hotkeyManager.onHotkeySystemRecovered = { [weak self] in
            Task { @MainActor in
                self?.hotkeyStatusMessage = nil
            }
        }
        hotkeyManager.canStopReading = { [weak self] in
            self?.isReading == true
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
        guard let target = resolveSelectionTarget(refresh: true, allowRecentFallback: true) else {
            showToast?("No selected text")
            return
        }
        startReading(target)
    }

    func translateSelection() {
        guard let text = resolveSelectionTarget(refresh: true, allowRecentFallback: true)?.text else {
            showToast?("No selected text")
            return
        }
        runTranslation(text: text)
    }

    func retryTranslation(sourceText: String) {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            showToast?("No source text")
            return
        }
        runTranslation(text: text)
    }

    func grammarCheck() {
        guard let text = resolveSelectionTarget(refresh: true, allowRecentFallback: true)?.text else {
            showToast?("No selected text")
            return
        }
        runGrammarCheck(text: text, resetTabOnSuccess: true)
    }

    func retryGrammarCheck(sourceText: String, preserveSelectedOption: GrammarOption) {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            showToast?("No source text")
            return
        }
        selectedGrammarOption = preserveSelectedOption
        runGrammarCheck(text: text, resetTabOnSuccess: false)
    }

    private func runTranslation(text: String) {
        guard !isTranslating else { return }
        translationInlineError = nil
        showTranslationSuccessFlash = false
        showTranslationCancelledFlash = false
        translationSuccessFlashTask?.cancel()
        translationSuccessFlashTask = nil
        translationCancelledFlashTask?.cancel()
        translationCancelledFlashTask = nil

        if let validationMessage = validateLanguageProviderConfig() {
            translationInlineError = validationMessage
            showToast?(validationMessage)
            openSettings?()
            return
        }

        isTranslating = true
        translationRequestID &+= 1
        let requestID = translationRequestID
        let preset = settings.grammarProviderPreset
        let config = settings.grammarConfig

        translationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await aiClient.translate(
                    text: text,
                    preset: preset,
                    config: config,
                    targetLanguage: "zh-CN"
                )
                await MainActor.run {
                    guard self.translationRequestID == requestID else { return }
                    self.activeResultPanel = .translation
                    self.translationResult = result
                    self.grammarCheckResult = nil
                    self.isTranslating = false
                    self.translationTask = nil
                    self.translationInlineError = nil
                    self.showTranslationSuccessFlash = true
                    self.showTranslationCancelledFlash = false
                    self.translationSuccessFlashTask?.cancel()
                    self.translationSuccessFlashTask = Task { [weak self] in
                        try? await Task.sleep(nanoseconds: 850_000_000)
                        guard let self, !Task.isCancelled else { return }
                        self.showTranslationSuccessFlash = false
                        self.translationSuccessFlashTask = nil
                    }
                }
            } catch {
                await MainActor.run {
                    guard self.translationRequestID == requestID else { return }
                    self.isTranslating = false
                    self.translationTask = nil
                    self.showTranslationSuccessFlash = false
                    self.showTranslationCancelledFlash = false
                    self.translationSuccessFlashTask?.cancel()
                    self.translationSuccessFlashTask = nil
                    self.translationCancelledFlashTask?.cancel()
                    self.translationCancelledFlashTask = nil
                    if self.isTaskCancelled(error) {
                        return
                    }
                    let message = self.formatRequestError(error)
                    self.translationInlineError = message
                    self.showToast?("Translation failed: \(message)")
                }
            }
        }
    }

    private func runGrammarCheck(text: String, resetTabOnSuccess: Bool) {
        guard !isGrammarChecking else { return }
        grammarInlineError = nil
        showGrammarSuccessFlash = false
        showGrammarCancelledFlash = false
        grammarSuccessFlashTask?.cancel()
        grammarSuccessFlashTask = nil
        grammarCancelledFlashTask?.cancel()
        grammarCancelledFlashTask = nil

        if let validationMessage = validateLanguageProviderConfig() {
            grammarInlineError = validationMessage
            showToast?(validationMessage)
            openSettings?()
            return
        }

        isGrammarChecking = true
        grammarCheckRequestID &+= 1
        let requestID = grammarCheckRequestID
        let preset = settings.grammarProviderPreset
        let config = settings.grammarConfig

        grammarCheckTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await aiClient.grammarCheck(
                    text: text,
                    preset: preset,
                    config: config
                )
                await MainActor.run {
                    guard self.grammarCheckRequestID == requestID else { return }
                    self.activeResultPanel = .grammar
                    if resetTabOnSuccess {
                        self.selectedGrammarOption = .cleanUp
                    }
                    self.grammarCheckResult = result
                    self.translationResult = nil
                    self.grammarInlineError = nil
                    self.isGrammarChecking = false
                    self.grammarCheckTask = nil
                    self.showGrammarSuccessFlash = true
                    self.showGrammarCancelledFlash = false
                    self.grammarSuccessFlashTask?.cancel()
                    self.grammarSuccessFlashTask = Task { [weak self] in
                        try? await Task.sleep(nanoseconds: 850_000_000)
                        guard let self, !Task.isCancelled else { return }
                        self.showGrammarSuccessFlash = false
                        self.grammarSuccessFlashTask = nil
                    }
                }
            } catch {
                await MainActor.run {
                    guard self.grammarCheckRequestID == requestID else { return }
                    self.isGrammarChecking = false
                    self.grammarCheckTask = nil
                    self.showGrammarSuccessFlash = false
                    self.showGrammarCancelledFlash = false
                    self.grammarSuccessFlashTask?.cancel()
                    self.grammarSuccessFlashTask = nil
                    self.grammarCancelledFlashTask?.cancel()
                    self.grammarCancelledFlashTask = nil
                    if self.isTaskCancelled(error) {
                        return
                    }
                    let message = self.formatRequestError(error)
                    self.grammarInlineError = message
                    self.showToast?("Grammar Check failed: \(message)")
                }
            }
        }
    }

    func cancelGrammarCheck() {
        guard isGrammarChecking else { return }
        grammarCheckRequestID &+= 1
        grammarCheckTask?.cancel()
        grammarCheckTask = nil
        isGrammarChecking = false
        grammarInlineError = nil
        showGrammarSuccessFlash = false
        grammarSuccessFlashTask?.cancel()
        grammarSuccessFlashTask = nil
        showGrammarCancelledFlash = true
        grammarCancelledFlashTask?.cancel()
        grammarCancelledFlashTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 850_000_000)
            guard let self, !Task.isCancelled else { return }
            self.showGrammarCancelledFlash = false
            self.grammarCancelledFlashTask = nil
        }
        showToast?("Grammar Check cancelled")
    }

    func cancelTranslation() {
        guard isTranslating else { return }
        translationRequestID &+= 1
        translationTask?.cancel()
        translationTask = nil
        isTranslating = false
        translationInlineError = nil
        showTranslationSuccessFlash = false
        translationSuccessFlashTask?.cancel()
        translationSuccessFlashTask = nil
        showTranslationCancelledFlash = true
        translationCancelledFlashTask?.cancel()
        translationCancelledFlashTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 850_000_000)
            guard let self, !Task.isCancelled else { return }
            self.showTranslationCancelledFlash = false
            self.translationCancelledFlashTask = nil
        }
        showToast?("Translation cancelled")
    }

    func dismissResultPanel() {
        grammarCheckResult = nil
        translationResult = nil
        activeResultPanel = .grammar
    }

    func readTextAloud(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        activeReadSource = nil
        readingAnchorRect = nil
        isReading = true
        speak(text: trimmed)
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
        grammarSuccessFlashTask?.cancel()
        grammarSuccessFlashTask = nil
        translationSuccessFlashTask?.cancel()
        translationSuccessFlashTask = nil
        grammarCancelledFlashTask?.cancel()
        grammarCancelledFlashTask = nil
        translationCancelledFlashTask?.cancel()
        translationCancelledFlashTask = nil
        showGrammarSuccessFlash = false
        showTranslationSuccessFlash = false
        showGrammarCancelledFlash = false
        showTranslationCancelledFlash = false

        if wasReading {
            scheduleSelectionPublication(selectionMonitor.currentSelection())
        }
    }

    private func resolveSelectionTarget(refresh: Bool, allowRecentFallback: Bool = false) -> ReadTarget? {
        let snapshot: SelectionSnapshot?
        if refresh {
            snapshot = selectionMonitor.currentSelection()
            selection = snapshot
        } else {
            snapshot = selection
        }

        if let snapshot,
           let freshTarget = readTarget(from: snapshot) {
            rememberSelectionTarget(freshTarget)
            return freshTarget
        }

        if allowRecentFallback,
           let fallbackTarget = recentSelectionTarget,
           let updatedAt = recentSelectionUpdatedAt,
           Date().timeIntervalSince(updatedAt) <= recentSelectionMaxAge {
            return fallbackTarget
        }

        return nil
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

    private func readTarget(from snapshot: SelectionSnapshot) -> ReadTarget? {
        let trimmed = snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return ReadTarget(text: trimmed, rect: snapshot.rect, source: .selection, appName: snapshot.appName)
    }

    private func rememberSelectionTarget(_ target: ReadTarget) {
        recentSelectionTarget = target
        recentSelectionUpdatedAt = Date()
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
            if let target = readTarget(from: snapshot) {
                rememberSelectionTarget(target)
            }

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

    private func validateLanguageProviderConfig() -> String? {
        let config = settings.grammarConfig
        let key = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)

        switch settings.grammarProviderPreset {
        case .glmDirect:
            if key.isEmpty {
                return "Missing GLM API key"
            }
            if model.isEmpty {
                return "Missing GLM model"
            }
        case .geminiDirect:
            if key.isEmpty {
                return "Missing Gemini API key"
            }
            if model.isEmpty {
                return "Missing Gemini model"
            }
        case .custom:
            let baseURL = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if baseURL.isEmpty {
                return "Missing custom backend base URL"
            }
            if model.isEmpty {
                return "Missing custom backend model"
            }
            if key.isEmpty {
                return "Missing custom backend API key"
            }
        }
        return nil
    }

    private func formatRequestError(_ error: Error) -> String {
        if let aiError = error as? AIError {
            switch aiError {
            case .invalidConfig:
                return "Invalid provider config"
            case .invalidResponse:
                return "Invalid response"
            case let .httpError(code, message):
                if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return "HTTP \(code): \(message)"
                }
                return "HTTP \(code)"
            case .timeout:
                return "Request timed out after 20s"
            case .cancelled:
                return "Request cancelled"
            case let .network(message):
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    return "Network error"
                }
                return "Network error: \(trimmed)"
            }
        }

        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "Unknown error" : message
    }

    private func isTaskCancelled(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let aiError = error as? AIError, case .cancelled = aiError {
            return true
        }
        return false
    }

    private func handleHotkeySystemUnavailable(_ message: String) {
        hotkeyStatusMessage = message

        let now = Date()
        let shouldShowToast: Bool
        if lastHotkeyWarningMessage != message {
            shouldShowToast = true
        } else if let lastHotkeyWarningAt {
            shouldShowToast = now.timeIntervalSince(lastHotkeyWarningAt) > 10
        } else {
            shouldShowToast = true
        }

        if shouldShowToast {
            showToast?(message)
            lastHotkeyWarningMessage = message
            lastHotkeyWarningAt = now
        }
    }
}
