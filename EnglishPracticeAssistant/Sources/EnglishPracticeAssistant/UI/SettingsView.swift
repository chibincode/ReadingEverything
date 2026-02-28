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
    private let customModelTag = "__custom_model__"
    private let glmModelOptions = ["glm-4-flash-250414", "glm-4.5-flash", "glm-5-air"]
    private let geminiModelOptions = ["gemini-3-flash-preview", "gemini-2.5-flash", "gemini-2.5-pro"]

    var body: some View {
        ScrollView {
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
                        HotkeyRow(title: "Read Selection", combo: $settings.hotkeyBindings.readSelection)
                        HotkeyRow(title: "Translate", combo: $settings.hotkeyBindings.translation)
                        HotkeyRow(title: "Grammar Check", combo: $settings.hotkeyBindings.grammar)
                        Text("Matched hotkeys are intercepted and will not pass through to the target app.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                }

                GroupBox(label: Text("Grammar Provider")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Preset", selection: grammarPresetBinding) {
                            ForEach(GrammarProviderPreset.allCases, id: \.self) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }

                        switch settings.grammarProviderPreset {
                        case .glmDirect:
                            grammarModelPicker(
                                options: glmModelOptions,
                                customPlaceholder: "glm-4-flash-250414"
                            )
                            labeledRevealableSecretField(
                                "API Key",
                                text: $settings.grammarConfig.apiKey,
                                placeholder: "GLM API Key"
                            )
                            Text("Directly calls GLM Chat Completions endpoint: https://open.bigmodel.cn/api/paas/v4/chat/completions")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        case .geminiDirect:
                            grammarModelPicker(
                                options: geminiModelOptions,
                                customPlaceholder: "gemini-3-flash-preview"
                            )
                            labeledRevealableSecretField(
                                "API Key",
                                text: $settings.grammarConfig.apiKey,
                                placeholder: "Gemini API Key"
                            )
                            Text("Directly calls Gemini generateContent endpoint with JSON output.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        case .custom:
                            labeledTextField(
                                "Base URL",
                                text: $settings.grammarConfig.baseURL,
                                placeholder: "Custom backend URL"
                            )
                            labeledTextField(
                                "Model / Endpoint ID",
                                text: $settings.grammarConfig.model,
                                placeholder: "Model / Endpoint ID"
                            )
                            labeledRevealableSecretField(
                                "API Key",
                                text: $settings.grammarConfig.apiKey,
                                placeholder: "API Key"
                            )
                            Text("Headers JSON")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextEditor(text: $settings.grammarConfig.headersJSON)
                                .frame(height: 80)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2)))
                                .font(.system(size: 12))
                            Text("Tries grammar_check first, then falls back to grammar_rephrase on compatible errors.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
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

                GroupBox(label: Text("AI Provider (TTS)")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Use AI TTS", isOn: $settings.useAITTS)
                        Picker("Preset", selection: $settings.aiPreset) {
                            ForEach(AIProviderPreset.allCases, id: \.self) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        .onChange(of: settings.aiPreset) { newPreset in
                            applyPreset(newPreset)
                            if newPreset == .doubaoOpenSpeech {
                                normalizeOpenSpeechConfig()
                            }
                            showAdvancedProviderFields = (newPreset == .custom)
                        }

                        if settings.aiPreset != .custom {
                            Toggle("Show advanced provider fields", isOn: $showAdvancedProviderFields)
                        }

                        if settings.aiPreset == .custom || showAdvancedProviderFields {
                            labeledTextField("Base URL", text: $settings.aiConfig.baseURL, placeholder: baseURLPlaceholder)
                        }
                        if usesOpenSpeechFlow {
                            labeledTextField("App ID", text: $settings.aiConfig.appID, placeholder: "App ID")
                            if settings.aiPreset == .doubaoOpenSpeech {
                                openSpeechResourcePicker
                                openSpeechSpeakerPicker
                            } else {
                                labeledTextField("Resource ID", text: $settings.aiConfig.resourceID, placeholder: "Resource ID")
                                labeledTextField("Speaker", text: $settings.aiConfig.voice, placeholder: "Speaker")
                            }
                        } else {
                            labeledTextField("Model / Endpoint ID", text: $settings.aiConfig.model, placeholder: "Model / Endpoint ID")
                            labeledTextField("Voice", text: $settings.aiConfig.voice, placeholder: "Voice")
                        }
                        labeledRevealableSecretField(
                            usesOpenSpeechFlow ? "Access Key" : "API Key",
                            text: $settings.aiConfig.apiKey,
                            placeholder: apiKeyPlaceholder
                        )
                        if settings.aiPreset == .custom || showAdvancedProviderFields {
                            Text("Headers JSON")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextEditor(text: $settings.aiConfig.headersJSON)
                                .frame(height: 80)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2)))
                                .font(.system(size: 12))
                        }
                        quickSetupNotes

                        labeledTextField("TTS Test Text", text: $ttsTestText, placeholder: "TTS test text")
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .onAppear {
            refreshPermissions()
            showAdvancedProviderFields = (settings.aiPreset == .custom)
            if settings.aiPreset != .custom && !hasUserConfiguredAIProvider {
                applyPreset(settings.aiPreset)
            }
            if settings.aiPreset == .doubaoOpenSpeech {
                normalizeOpenSpeechConfig()
            }
            ensureDefaultGrammarModel(for: settings.grammarProviderPreset)
        }
    }

    private func refreshPermissions() {
        accessibilityEnabled = PermissionCenter.accessibilityEnabled
        inputMonitoringEnabled = PermissionCenter.inputMonitoringEnabled
    }

    private var grammarPresetBinding: Binding<GrammarProviderPreset> {
        Binding(
            get: { settings.grammarProviderPreset },
            set: { newPreset in
                settings.switchGrammarProviderPreset(to: newPreset)
                ensureDefaultGrammarModel(for: newPreset)
            }
        )
    }

    private func grammarModelSelectionBinding(options: [String]) -> Binding<String> {
        Binding(
            get: {
                let trimmed = settings.grammarConfig.model.trimmingCharacters(in: .whitespacesAndNewlines)
                if options.contains(trimmed) {
                    return trimmed
                }
                return customModelTag
            },
            set: { selected in
                let current = settings.grammarConfig.model.trimmingCharacters(in: .whitespacesAndNewlines)
                if selected == customModelTag {
                    if options.contains(current) {
                        settings.grammarConfig.model = ""
                    }
                    return
                }
                settings.grammarConfig.model = selected
            }
        )
    }

    private func grammarModelPicker(options: [String], customPlaceholder: String) -> some View {
        let selection = grammarModelSelectionBinding(options: options)
        let useCustomInput = selection.wrappedValue == customModelTag

        return Group {
            Text("Model")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Model", selection: selection) {
                ForEach(options, id: \.self) { model in
                    Text(model).tag(model)
                }
                Text("Custom...").tag(customModelTag)
            }
            .pickerStyle(.menu)

            if useCustomInput {
                TextField(customPlaceholder, text: $settings.grammarConfig.model)
            }
        }
    }

    private func ensureDefaultGrammarModel(for preset: GrammarProviderPreset) {
        let trimmed = settings.grammarConfig.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return }

        switch preset {
        case .glmDirect:
            settings.grammarConfig.model = "glm-4-flash-250414"
        case .geminiDirect:
            settings.grammarConfig.model = "gemini-3-flash-preview"
        case .custom:
            break
        }
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
                voice: "zh_female_sophie_conversation_wvae_bigtts",
                appID: "",
                resourceID: "seed-tts-1.0",
                headersJSON: "",
                apiKey: apiKey
            )
        case .custom:
            break
        }
    }

    @ViewBuilder
    private var openSpeechResourcePicker: some View {
        Text("Resource ID")
            .font(.caption)
            .foregroundStyle(.secondary)
        Picker("Resource ID", selection: Binding(
            get: { canonicalResourceID(settings.aiConfig.resourceID) },
            set: { newValue in
                settings.aiConfig.resourceID = newValue
                normalizeOpenSpeechConfig()
            }
        )) {
            ForEach(openSpeechResourceOptions, id: \.self) { resourceID in
                Text(resourceID).tag(resourceID)
            }
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private var openSpeechSpeakerPicker: some View {
        Text("Speaker")
            .font(.caption)
            .foregroundStyle(.secondary)
        Picker("Speaker", selection: $settings.aiConfig.voice) {
            ForEach(openSpeechVoiceOptions(for: canonicalResourceID(settings.aiConfig.resourceID))) { option in
                Text(option.label).tag(option.voiceType)
            }
        }
        .pickerStyle(.menu)
    }

    private let openSpeechResourceOptions = ["seed-tts-1.0", "seed-tts-2.0"]

    private func openSpeechVoiceOptions(for resourceID: String) -> [OpenSpeechVoiceOption] {
        let all: [OpenSpeechVoiceOption] = [
            .init(resourceID: "seed-tts-1.0", voiceType: "zh_female_qingxinnvsheng_mars_bigtts", note: "女生温柔语速慢"),
            .init(resourceID: "seed-tts-1.0", voiceType: "zh_female_shuangkuaisisi_moon_bigtts", note: "女生语速正常"),
            .init(resourceID: "seed-tts-1.0", voiceType: "zh_female_sophie_conversation_wvae_bigtts", note: "女生语速正常靠谱"),
            .init(resourceID: "seed-tts-1.0", voiceType: "zh_male_M100_conversation_wvae_bigtts", note: "男生语速正常"),
            .init(resourceID: "seed-tts-2.0", voiceType: "zh_female_vv_uranus_bigtts", note: "可爱女生推荐, 英文语数慢")
        ]
        return all.filter { $0.resourceID == resourceID }
    }

    private func canonicalResourceID(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch trimmed {
        case "volc.service_type.10029":
            return "seed-tts-1.0"
        case "volc.service_type.10048":
            return "seed-tts-1.0-concurr"
        default:
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func normalizeOpenSpeechConfig() {
        let canonical = canonicalResourceID(settings.aiConfig.resourceID)
        if openSpeechResourceOptions.contains(canonical) {
            settings.aiConfig.resourceID = canonical
        } else {
            settings.aiConfig.resourceID = "seed-tts-1.0"
        }

        let options = openSpeechVoiceOptions(for: settings.aiConfig.resourceID)
        let preferredDefault = "zh_female_sophie_conversation_wvae_bigtts"
        if settings.aiConfig.resourceID == "seed-tts-1.0",
           options.contains(where: { $0.voiceType == preferredDefault }) {
            settings.aiConfig.voice = preferredDefault
        } else if let current = options.first(where: { $0.voiceType == settings.aiConfig.voice }) {
            settings.aiConfig.voice = current.voiceType
        } else if let first = options.first {
            settings.aiConfig.voice = first.voiceType
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
            case .timeout:
                return "Request timed out after 20s."
            case .cancelled:
                return "Request cancelled."
            case let .network(message):
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "Network error." : "Network error: \(trimmed)"
            }
        }
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "Unknown error." : message
    }

    @ViewBuilder
    private func labeledTextField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        Text(label)
            .font(.caption)
            .foregroundStyle(.secondary)
        TextField(placeholder, text: text)
    }

    @ViewBuilder
    private func labeledRevealableSecretField(
        _ label: String,
        text: Binding<String>,
        placeholder: String
    ) -> some View {
        Text(label)
            .font(.caption)
            .foregroundStyle(.secondary)
        RevealableSecretField(placeholder: placeholder, text: text)
    }
}

private struct RevealableSecretField: View {
    let placeholder: String
    @Binding var text: String
    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 10) {
            if isRevealed {
                TextField(placeholder, text: $text)
            } else {
                SecureField(placeholder, text: $text)
            }

            Button(isRevealed ? "Hide" : "Show") {
                isRevealed.toggle()
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12, weight: .medium))
        }
    }
}

private struct OpenSpeechVoiceOption: Identifiable {
    let resourceID: String
    let voiceType: String
    let note: String

    var id: String { voiceType }

    var label: String {
        "\(voiceType)（\(note)）"
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
