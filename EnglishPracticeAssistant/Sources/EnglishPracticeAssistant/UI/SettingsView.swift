import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @State private var accessibilityEnabled = PermissionCenter.accessibilityEnabled
    @State private var inputMonitoringEnabled = PermissionCenter.inputMonitoringEnabled
    @State private var ttsTestText = "This is a test from English Practice Assistant."
    @State private var ttsTestStatus = ""
    @State private var isTestingTTS = false
    @State private var showAdvancedProviderFields = false
    private let aiClient = AIClient()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox(label: Text("Permissions")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        StatusDot(isOn: accessibilityEnabled)
                        Text("Accessibility")
                        Spacer()
                        Button("Request") {
                            PermissionCenter.requestAccessibility()
                            refreshPermissions()
                        }
                        Button("Open Settings") {
                            PermissionCenter.openPrivacySettings()
                        }
                    }
                    HStack {
                        StatusDot(isOn: inputMonitoringEnabled)
                        Text("Input Monitoring")
                        Spacer()
                        Button("Check") {
                            refreshPermissions()
                        }
                        Button("Open Settings") {
                            PermissionCenter.openPrivacySettings()
                        }
                    }
                    Text("If hotkeys do not work, enable Input Monitoring.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }

            GroupBox(label: Text("Hotkeys")) {
                VStack(alignment: .leading, spacing: 12) {
                    HotkeyRow(title: "Hover Read", combo: $settings.hotkeyBindings.hoverRead)
                    HotkeyRow(title: "Read Selection", combo: $settings.hotkeyBindings.readSelection)
                    HotkeyRow(title: "Grammar + Rephrase", combo: $settings.hotkeyBindings.grammar)
                }
                .padding(8)
            }

            GroupBox(label: Text("Debug")) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Show detection overlay before reading", isOn: $settings.showDetectionOverlay)
                    Toggle("Show floating bar offset debug", isOn: $settings.showFloatingBarOffsetDebug)
                    Text("When enabled, a short-lived highlight box shows the detected read area (for internal testing).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Offset debug shows expected anchor vs actual bar frame and dx/dy.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }

            GroupBox(label: Text("AI Provider")) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Use AI TTS", isOn: $settings.useAITTS)
                    Picker("Preset", selection: $settings.aiPreset) {
                        ForEach(AIProviderPreset.allCases, id: \.self) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .onChange(of: settings.aiPreset) { newPreset in
                        applyPreset(newPreset)
                        showAdvancedProviderFields = (newPreset == .custom)
                    }

                    if settings.aiPreset != .custom {
                        Toggle("Show advanced provider fields", isOn: $showAdvancedProviderFields)
                    }

                    if settings.aiPreset == .custom || showAdvancedProviderFields {
                        TextField(baseURLPlaceholder, text: $settings.aiConfig.baseURL)
                    }
                    if usesOpenSpeechFlow {
                        TextField("App ID", text: $settings.aiConfig.appID)
                        TextField("Resource ID", text: $settings.aiConfig.resourceID)
                        TextField("Speaker", text: $settings.aiConfig.voice)
                    } else {
                        TextField("Model / Endpoint ID", text: $settings.aiConfig.model)
                        TextField("Voice", text: $settings.aiConfig.voice)
                    }
                    SecureField(apiKeyPlaceholder, text: $settings.aiConfig.apiKey)
                    if settings.aiPreset == .custom || showAdvancedProviderFields {
                        TextEditor(text: $settings.aiConfig.headersJSON)
                            .frame(height: 80)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2)))
                            .font(.system(size: 12))
                    }
                    quickSetupNotes

                    TextField("TTS test text", text: $ttsTestText)
                    HStack(spacing: 10) {
                        Button(isTestingTTS ? "Testing..." : "Test AI TTS") {
                            runTTSTest()
                        }
                        .disabled(isTestingTTS || !canRunTTSTest)
                        if !ttsTestStatus.isEmpty {
                            Text(ttsTestStatus)
                                .font(.footnote)
                                .foregroundStyle(ttsTestStatus.hasPrefix("Success") ? .green : .red)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(8)
            }

            Spacer()
        }
        .padding(20)
        .onAppear {
            refreshPermissions()
            showAdvancedProviderFields = (settings.aiPreset == .custom)
            if settings.aiPreset != .custom && !hasUserConfiguredAIProvider {
                applyPreset(settings.aiPreset)
            }
        }
    }

    private func refreshPermissions() {
        accessibilityEnabled = PermissionCenter.accessibilityEnabled
        inputMonitoringEnabled = PermissionCenter.inputMonitoringEnabled
    }

    private var usesOpenSpeechFlow: Bool {
        if settings.aiPreset == .doubaoOpenSpeech {
            return true
        }
        if settings.aiPreset == .custom {
            return settings.aiConfig.baseURL.lowercased().contains("openspeech.bytedance.com")
        }
        return false
    }

    private var baseURLPlaceholder: String {
        if usesOpenSpeechFlow {
            return "Base URL (e.g. https://openspeech.bytedance.com/api/v3/tts/unidirectional)"
        }
        return "Base URL (e.g. https://ark.cn-beijing.volces.com/api/v3)"
    }

    private var apiKeyPlaceholder: String {
        usesOpenSpeechFlow ? "Access Key" : "API Key"
    }

    @ViewBuilder
    private var quickSetupNotes: some View {
        switch settings.aiPreset {
        case .doubaoOpenSpeech:
            Group {
                Text("Doubao (OpenSpeech) quick setup:")
                    .font(.footnote.weight(.semibold))
                Text("Base URL: https://openspeech.bytedance.com/api/v3/tts/unidirectional")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Fill App ID + Resource ID from VolcEngine OpenSpeech console (no Bearer auth on this endpoint).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("API Key field maps to X-Api-Access-Key. Model is omitted by default in this app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .doubaoArk:
            Group {
                Text("Doubao (Ark) quick setup:")
                    .font(.footnote.weight(.semibold))
                Text("Base URL: https://ark.cn-beijing.volces.com/api/v3")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Model can be your endpoint id, e.g. 116118d5-3e33-4b9b-a411-5f41faa6844b")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("API Key must be Ark API Key (Bearer). Do not use OpenSpeech Access Key here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .custom:
            Group {
                Text("Custom provider:")
                    .font(.footnote.weight(.semibold))
                Text("Use Headers JSON for custom auth or extra fields.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var canRunTTSTest: Bool {
        let hasBase = !settings.aiConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasKey = !settings.aiConfig.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if usesOpenSpeechFlow {
            let hasAppID = !settings.aiConfig.appID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasResource = !settings.aiConfig.resourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasSpeaker = !settings.aiConfig.voice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return hasBase && hasKey && hasAppID && hasResource && hasSpeaker
        }
        let hasModel = !settings.aiConfig.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasBase && hasKey && hasModel
    }

    private var hasUserConfiguredAIProvider: Bool {
        let config = settings.aiConfig
        let values = [
            config.baseURL,
            config.model,
            config.voice,
            config.appID,
            config.resourceID,
            config.apiKey,
            config.headersJSON
        ]
        return values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func applyPreset(_ preset: AIProviderPreset) {
        guard preset != .custom else { return }

        let apiKey = settings.aiConfig.apiKey
        switch preset {
        case .doubaoArk:
            settings.aiConfig = AIProviderConfig(
                baseURL: "https://ark.cn-beijing.volces.com/api/v3",
                model: "116118d5-3e33-4b9b-a411-5f41faa6844b",
                voice: "alloy",
                appID: "",
                resourceID: "",
                headersJSON: "",
                apiKey: apiKey
            )
        case .doubaoOpenSpeech:
            settings.aiConfig = AIProviderConfig(
                baseURL: "https://openspeech.bytedance.com/api/v3/tts/unidirectional",
                model: "",
                voice: "BV001_streaming",
                appID: "",
                resourceID: "",
                headersJSON: "",
                apiKey: apiKey
            )
        case .custom:
            break
        }
    }

    private func runTTSTest() {
        guard canRunTTSTest else {
            if usesOpenSpeechFlow {
                ttsTestStatus = "Fill Base URL, App ID, Resource ID, Speaker, and Access Key first."
            } else {
                ttsTestStatus = "Fill Base URL, Model, and API Key first."
            }
            return
        }
        let config = settings.aiConfig
        let text = ttsTestText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            ttsTestStatus = "Enter test text."
            return
        }

        isTestingTTS = true
        ttsTestStatus = "Testing..."

        Task {
            do {
                let audio = try await aiClient.ttsAudio(text: text, config: config, preset: settings.aiPreset)
                await MainActor.run {
                    isTestingTTS = false
                    ttsTestStatus = "Success: received \(audio.count) bytes."
                }
            } catch {
                await MainActor.run {
                    isTestingTTS = false
                    ttsTestStatus = "Failed: \(formatAIError(error))"
                }
            }
        }
    }

    private func formatAIError(_ error: Error) -> String {
        if let aiError = error as? AIError {
            switch aiError {
            case .invalidConfig:
                return "Invalid config."
            case .invalidResponse:
                return "Invalid response."
            case let .httpError(code, message):
                if let message, !message.isEmpty {
                    if code == 401 {
                        if usesOpenSpeechFlow {
                            return "HTTP 401: OpenSpeech auth failed. Check App ID + Access Key + Resource ID are from the same OpenSpeech project."
                        }
                        return "HTTP 401: Ark auth failed. Use Ark API Key (Bearer), not OpenSpeech Access Key."
                    }
                    return "HTTP \(code): \(message)"
                }
                if code == 401 {
                    if usesOpenSpeechFlow {
                        return "HTTP 401: OpenSpeech auth failed. Check App ID + Access Key + Resource ID."
                    }
                    return "HTTP 401: Ark auth failed. Check Ark API Key and endpoint region."
                }
                return "HTTP \(code)"
            }
        }
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "Unknown error." : message
    }
}

private struct HotkeyRow: View {
    let title: String
    @Binding var combo: KeyCombo

    var body: some View {
        HStack {
            Text(title)
                .frame(width: 140, alignment: .leading)
            HotkeyRecorderView(combo: $combo)
            Spacer()
        }
    }
}

private struct StatusDot: View {
    let isOn: Bool

    var body: some View {
        Circle()
            .fill(isOn ? Color.green : Color.red)
            .frame(width: 8, height: 8)
    }
}
