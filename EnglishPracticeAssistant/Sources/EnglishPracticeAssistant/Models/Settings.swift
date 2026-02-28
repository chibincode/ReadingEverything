import Combine
import Foundation

struct HotkeyBindings: Codable, Equatable {
    var readSelection: KeyCombo
    var translation: KeyCombo
    var grammar: KeyCombo

    static let defaultReadSelection = KeyCombo(keyCode: 1, modifiers: [.control])
    static let defaultTranslation = KeyCombo(keyCode: 15, modifiers: [.control])
    static let defaultGrammar = KeyCombo(keyCode: 3, modifiers: [.control])
    static let legacyDefaultGrammar = KeyCombo(keyCode: 5, modifiers: [.option])
    static let defaultBindings = HotkeyBindings(
        readSelection: defaultReadSelection,
        translation: defaultTranslation,
        grammar: defaultGrammar
    )

    private enum CodingKeys: String, CodingKey {
        case readSelection
        case translation
        case grammar
    }

    init(readSelection: KeyCombo, translation: KeyCombo, grammar: KeyCombo) {
        self.readSelection = readSelection
        self.translation = translation
        self.grammar = grammar
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        readSelection = try container.decodeIfPresent(KeyCombo.self, forKey: .readSelection) ?? Self.defaultReadSelection
        translation = try container.decodeIfPresent(KeyCombo.self, forKey: .translation) ?? Self.defaultTranslation

        let decodedGrammar = try container.decodeIfPresent(KeyCombo.self, forKey: .grammar) ?? Self.defaultGrammar
        grammar = decodedGrammar == Self.legacyDefaultGrammar ? Self.defaultGrammar : decodedGrammar
    }
}

struct AIProviderConfig: Codable, Equatable {
    var baseURL: String
    var model: String
    var voice: String
    var appID: String
    var resourceID: String
    var headersJSON: String
    var apiKey: String

    init(
        baseURL: String,
        model: String,
        voice: String,
        appID: String,
        resourceID: String,
        headersJSON: String,
        apiKey: String
    ) {
        self.baseURL = baseURL
        self.model = model
        self.voice = voice
        self.appID = appID
        self.resourceID = resourceID
        self.headersJSON = headersJSON
        self.apiKey = apiKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        voice = try container.decodeIfPresent(String.self, forKey: .voice) ?? ""
        appID = try container.decodeIfPresent(String.self, forKey: .appID) ?? ""
        resourceID = try container.decodeIfPresent(String.self, forKey: .resourceID) ?? ""
        headersJSON = try container.decodeIfPresent(String.self, forKey: .headersJSON) ?? ""
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
    }
}

struct GrammarProviderConfig: Codable, Equatable {
    var model: String
    var baseURL: String
    var headersJSON: String
    var apiKey: String

    init(
        model: String,
        baseURL: String,
        headersJSON: String,
        apiKey: String
    ) {
        self.model = model
        self.baseURL = baseURL
        self.headersJSON = headersJSON
        self.apiKey = apiKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        headersJSON = try container.decodeIfPresent(String.self, forKey: .headersJSON) ?? ""
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
    }
}

enum AIProviderPreset: String, Codable, CaseIterable, Equatable {
    case custom
    case doubaoArk
    case doubaoOpenSpeech

    var title: String {
        switch self {
        case .custom:
            return "Custom"
        case .doubaoArk:
            return "Doubao (Ark)"
        case .doubaoOpenSpeech:
            return "Doubao (OpenSpeech)"
        }
    }
}

enum GrammarProviderPreset: String, Codable, CaseIterable, Equatable {
    case glmDirect
    case geminiDirect
    case custom

    var title: String {
        switch self {
        case .glmDirect:
            return "GLM Direct"
        case .geminiDirect:
            return "Gemini Direct"
        case .custom:
            return "Custom Backend"
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    private static let hotkeyDefaultsVersion = 2
    private static let hotkeyDefaultsVersionKey = "hotkeyDefaultsAppliedVersion"
    private static let legacyGrammarAPIKeyAccount = "grammarApiKey"
    private static let grammarAPIKeyGLMAccount = "grammarApiKey_glmDirect"
    private static let grammarAPIKeyGeminiAccount = "grammarApiKey_geminiDirect"
    private static let grammarAPIKeyCustomAccount = "grammarApiKey_custom"
    private static let grammarModelByPresetKey = "grammarModelByPreset"

    @Published var hotkeyBindings: HotkeyBindings
    @Published var grammarProviderPreset: GrammarProviderPreset
    @Published var grammarConfig: GrammarProviderConfig
    @Published var aiConfig: AIProviderConfig
    @Published var aiPreset: AIProviderPreset
    @Published var useAITTS: Bool
    @Published var showDetectionOverlay: Bool
    @Published var showFloatingBarOffsetDebug: Bool

    private let defaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let loadedAIConfig = SettingsStore.loadAIConfig(from: defaults) ?? AIProviderConfig(
            baseURL: "",
            model: "",
            voice: "",
            appID: "",
            resourceID: "",
            headersJSON: "",
            apiKey: KeychainStore.read(key: "apiKey") ?? ""
        )
        let grammarSettings = SettingsStore.loadGrammarSettings(from: defaults, legacyAIConfig: loadedAIConfig)

        let loadedHotkeys = SettingsStore.loadHotkeys(from: defaults) ?? .defaultBindings
        hotkeyBindings = SettingsStore.applyHotkeyDefaultsMigrationIfNeeded(
            loadedHotkeys,
            defaults: defaults
        )
        grammarProviderPreset = grammarSettings.preset
        grammarConfig = grammarSettings.config
        aiConfig = loadedAIConfig
        aiPreset = SettingsStore.loadAIPreset(from: defaults) ?? .custom
        useAITTS = defaults.bool(forKey: "useAITTS")
        showDetectionOverlay = defaults.bool(forKey: "showDetectionOverlay")
        showFloatingBarOffsetDebug = defaults.bool(forKey: "showFloatingBarOffsetDebug")

        $hotkeyBindings
            .sink { [weak self] bindings in
                guard let self else { return }
                let sanitized = SettingsStore.sanitizeHotkeyBindings(bindings)
                if sanitized != bindings {
                    self.hotkeyBindings = sanitized
                    return
                }
                self.saveHotkeys(sanitized)
            }
            .store(in: &cancellables)

        $aiConfig
            .sink { [weak self] config in
                self?.saveAIConfig(config)
            }
            .store(in: &cancellables)

        $grammarProviderPreset
            .sink { [weak self] preset in
                self?.defaults.set(preset.rawValue, forKey: "grammarProviderPreset")
            }
            .store(in: &cancellables)

        $grammarConfig
            .sink { [weak self] config in
                self?.saveGrammarConfig(config)
            }
            .store(in: &cancellables)

        $aiPreset
            .sink { [weak self] preset in
                self?.defaults.set(preset.rawValue, forKey: "aiPreset")
            }
            .store(in: &cancellables)

        $useAITTS
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: "useAITTS")
            }
            .store(in: &cancellables)

        $showDetectionOverlay
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: "showDetectionOverlay")
            }
            .store(in: &cancellables)

        $showFloatingBarOffsetDebug
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: "showFloatingBarOffsetDebug")
            }
            .store(in: &cancellables)
    }

    func switchGrammarProviderPreset(to preset: GrammarProviderPreset) {
        guard preset != grammarProviderPreset else { return }

        let previousPreset = grammarProviderPreset
        saveGrammarAPIKey(grammarConfig.apiKey, for: previousPreset)
        saveGrammarModel(grammarConfig.model, for: previousPreset)

        grammarProviderPreset = preset

        var nextConfig = grammarConfig
        nextConfig.model = resolvedGrammarModel(
            for: preset,
            fallbackModel: ""
        )
        nextConfig.apiKey = loadGrammarAPIKey(
            for: preset,
            fallback: ""
        )
        grammarConfig = nextConfig
    }

    private static func loadHotkeys(from defaults: UserDefaults) -> HotkeyBindings? {
        guard let data = defaults.data(forKey: "hotkeyBindings") else { return nil }
        guard let decoded = try? JSONDecoder().decode(HotkeyBindings.self, from: data) else {
            return nil
        }
        return sanitizeHotkeyBindings(decoded)
    }

    private static func applyHotkeyDefaultsMigrationIfNeeded(
        _ bindings: HotkeyBindings,
        defaults: UserDefaults
    ) -> HotkeyBindings {
        let appliedVersion = defaults.integer(forKey: hotkeyDefaultsVersionKey)
        guard appliedVersion < hotkeyDefaultsVersion else {
            return bindings
        }

        defaults.set(hotkeyDefaultsVersion, forKey: hotkeyDefaultsVersionKey)
        return sanitizeHotkeyBindings(.defaultBindings)
    }

    private static func sanitizeHotkeyBindings(_ bindings: HotkeyBindings) -> HotkeyBindings {
        var sanitized = bindings
        sanitized.readSelection = sanitizeSingleHotkey(
            sanitized.readSelection,
            fallback: HotkeyBindings.defaultReadSelection
        )
        sanitized.translation = sanitizeSingleHotkey(
            sanitized.translation,
            fallback: HotkeyBindings.defaultTranslation
        )
        sanitized.grammar = sanitizeSingleHotkey(
            sanitized.grammar,
            fallback: HotkeyBindings.defaultGrammar
        )

        var used = Set<String>()
        ensureUnique(
            &sanitized.readSelection,
            fallback: HotkeyBindings.defaultReadSelection,
            used: &used
        )
        ensureUnique(
            &sanitized.translation,
            fallback: HotkeyBindings.defaultTranslation,
            used: &used
        )
        ensureUnique(
            &sanitized.grammar,
            fallback: HotkeyBindings.defaultGrammar,
            used: &used
        )
        return sanitized
    }

    private static func sanitizeSingleHotkey(_ combo: KeyCombo, fallback: KeyCombo) -> KeyCombo {
        guard isValidHotkey(combo) else {
            NSLog("Hotkey invalid. Falling back to default: %@", normalizedHotkey(fallback).displayString)
            return normalizedHotkey(fallback)
        }
        return normalizedHotkey(combo)
    }

    private static func isValidHotkey(_ combo: KeyCombo) -> Bool {
        let modifiers = combo.modifierFlags.intersection(.relevant)
        guard !modifiers.isEmpty else { return false }
        return !combo.isModifierOnly
    }

    private static func normalizedHotkey(_ combo: KeyCombo) -> KeyCombo {
        KeyCombo(keyCode: combo.keyCode, modifiers: combo.modifierFlags.intersection(.relevant))
    }

    private static func ensureUnique(_ combo: inout KeyCombo, fallback: KeyCombo, used: inout Set<String>) {
        let original = combo
        let candidates = [
            combo,
            normalizedHotkey(fallback),
            normalizedHotkey(HotkeyBindings.defaultReadSelection),
            normalizedHotkey(HotkeyBindings.defaultTranslation),
            normalizedHotkey(HotkeyBindings.defaultGrammar)
        ]

        for candidate in candidates {
            let signature = hotkeySignature(candidate)
            if !used.contains(signature) {
                combo = candidate
                used.insert(signature)
                if combo != original {
                    NSLog("Hotkey conflict resolved. Reset to %@", combo.displayString)
                }
                return
            }
        }

        // Last resort: keep current value even if it collides; this should be unreachable.
        used.insert(hotkeySignature(combo))
    }

    private static func hotkeySignature(_ combo: KeyCombo) -> String {
        let modifiers = combo.modifierFlags.intersection(.relevant).rawValue
        return "\(combo.keyCode)-\(modifiers)"
    }

    private func saveHotkeys(_ bindings: HotkeyBindings) {
        if let data = try? JSONEncoder().encode(bindings) {
            defaults.set(data, forKey: "hotkeyBindings")
        }
    }

    private static func loadAIConfig(from defaults: UserDefaults) -> AIProviderConfig? {
        guard let data = defaults.data(forKey: "aiConfig") else { return nil }
        return try? JSONDecoder().decode(AIProviderConfig.self, from: data)
    }

    private static func loadAIPreset(from defaults: UserDefaults) -> AIProviderPreset? {
        guard let raw = defaults.string(forKey: "aiPreset") else { return nil }
        return AIProviderPreset(rawValue: raw)
    }

    private static func loadGrammarPreset(from defaults: UserDefaults) -> GrammarProviderPreset? {
        guard let raw = defaults.string(forKey: "grammarProviderPreset") else { return nil }
        return GrammarProviderPreset(rawValue: raw)
    }

    private static func loadGrammarConfig(from defaults: UserDefaults) -> GrammarProviderConfig? {
        guard let data = defaults.data(forKey: "grammarConfig"),
              let config = try? JSONDecoder().decode(GrammarProviderConfig.self, from: data) else {
            return nil
        }
        return config
    }

    private static func loadGrammarSettings(
        from defaults: UserDefaults,
        legacyAIConfig: AIProviderConfig
    ) -> (preset: GrammarProviderPreset, config: GrammarProviderConfig) {
        let storedPreset = loadGrammarPreset(from: defaults)
        let storedConfig = loadGrammarConfig(from: defaults)

        if let storedPreset {
            var config = storedConfig ?? defaultGrammarConfig(for: storedPreset)
            config.model = resolvedGrammarModel(for: storedPreset, defaults: defaults, fallbackModel: config.model)
            config.apiKey = loadGrammarAPIKey(for: storedPreset, fallback: config.apiKey)
            return (storedPreset, config)
        }

        if let storedConfig {
            let inferredPreset: GrammarProviderPreset = storedConfig.baseURL
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty ? .geminiDirect : .custom
            var config = storedConfig
            config.model = resolvedGrammarModel(for: inferredPreset, defaults: defaults, fallbackModel: config.model)
            config.apiKey = loadGrammarAPIKey(for: inferredPreset, fallback: config.apiKey)
            return (inferredPreset, config)
        }

        if hasLegacyGrammarEndpoint(legacyAIConfig) {
            let preset: GrammarProviderPreset = .custom
            var config = GrammarProviderConfig(
                model: legacyAIConfig.model,
                baseURL: legacyAIConfig.baseURL,
                headersJSON: legacyAIConfig.headersJSON,
                apiKey: legacyAIConfig.apiKey
            )
            config.model = resolvedGrammarModel(for: preset, defaults: defaults, fallbackModel: config.model)
            config.apiKey = loadGrammarAPIKey(for: preset, fallback: config.apiKey)
            return (
                preset,
                config
            )
        }

        let preset: GrammarProviderPreset = .glmDirect
        var config = defaultGrammarConfig(for: preset)
        config.model = resolvedGrammarModel(for: preset, defaults: defaults, fallbackModel: config.model)
        config.apiKey = loadGrammarAPIKey(for: preset, fallback: config.apiKey)
        return (preset, config)
    }

    private static func hasLegacyGrammarEndpoint(_ config: AIProviderConfig) -> Bool {
        let values = [
            config.baseURL,
            config.model,
            config.headersJSON
        ]
        return values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func defaultGrammarConfig(for preset: GrammarProviderPreset) -> GrammarProviderConfig {
        switch preset {
        case .glmDirect:
            return GrammarProviderConfig(
                model: defaultGrammarModel(for: .glmDirect),
                baseURL: "",
                headersJSON: "",
                apiKey: ""
            )
        case .geminiDirect:
            return GrammarProviderConfig(
                model: defaultGrammarModel(for: .geminiDirect),
                baseURL: "",
                headersJSON: "",
                apiKey: ""
            )
        case .custom:
            return GrammarProviderConfig(
                model: "",
                baseURL: "",
                headersJSON: "",
                apiKey: ""
            )
        }
    }

    private static func defaultGrammarModel(for preset: GrammarProviderPreset) -> String {
        switch preset {
        case .glmDirect:
            return "glm-4-flash-250414"
        case .geminiDirect:
            return "gemini-3-flash-preview"
        case .custom:
            return ""
        }
    }

    private static func grammarAPIKeyAccount(for preset: GrammarProviderPreset) -> String {
        switch preset {
        case .glmDirect:
            return grammarAPIKeyGLMAccount
        case .geminiDirect:
            return grammarAPIKeyGeminiAccount
        case .custom:
            return grammarAPIKeyCustomAccount
        }
    }

    private static func loadGrammarAPIKey(
        for preset: GrammarProviderPreset,
        fallback: String
    ) -> String {
        let providerKey = KeychainStore.read(key: grammarAPIKeyAccount(for: preset))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !providerKey.isEmpty {
            return providerKey
        }

        let fallbackTrimmed = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fallbackTrimmed.isEmpty {
            return fallbackTrimmed
        }

        return KeychainStore.read(key: legacyGrammarAPIKeyAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func loadGrammarAPIKey(
        for preset: GrammarProviderPreset,
        fallback: String
    ) -> String {
        Self.loadGrammarAPIKey(for: preset, fallback: fallback)
    }

    private func saveGrammarAPIKey(_ apiKey: String, for preset: GrammarProviderPreset) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        KeychainStore.save(key: Self.grammarAPIKeyAccount(for: preset), value: trimmed)
    }

    private static func loadGrammarModelMap(from defaults: UserDefaults) -> [String: String] {
        guard let raw = defaults.dictionary(forKey: grammarModelByPresetKey) as? [String: String] else {
            return [:]
        }
        return raw.reduce(into: [:]) { result, pair in
            let trimmed = pair.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                result[pair.key] = trimmed
            }
        }
    }

    private func saveGrammarModelMap(_ map: [String: String]) {
        defaults.set(map, forKey: Self.grammarModelByPresetKey)
    }

    private static func resolvedGrammarModel(
        for preset: GrammarProviderPreset,
        defaults: UserDefaults,
        fallbackModel: String
    ) -> String {
        let map = loadGrammarModelMap(from: defaults)
        if let stored = map[preset.rawValue], !stored.isEmpty {
            return stored
        }
        let trimmedFallback = fallbackModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFallback.isEmpty {
            return trimmedFallback
        }
        return defaultGrammarModel(for: preset)
    }

    private func resolvedGrammarModel(
        for preset: GrammarProviderPreset,
        fallbackModel: String
    ) -> String {
        Self.resolvedGrammarModel(
            for: preset,
            defaults: defaults,
            fallbackModel: fallbackModel
        )
    }

    private func saveGrammarModel(_ model: String, for preset: GrammarProviderPreset) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        var map = Self.loadGrammarModelMap(from: defaults)
        if trimmed.isEmpty {
            map.removeValue(forKey: preset.rawValue)
        } else {
            map[preset.rawValue] = trimmed
        }
        saveGrammarModelMap(map)
    }

    private func saveAIConfig(_ config: AIProviderConfig) {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: "aiConfig")
        }
        if !config.apiKey.isEmpty {
            KeychainStore.save(key: "apiKey", value: config.apiKey)
        }
    }

    private func saveGrammarConfig(_ config: GrammarProviderConfig) {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: "grammarConfig")
        }
        saveGrammarModel(config.model, for: grammarProviderPreset)
        saveGrammarAPIKey(config.apiKey, for: grammarProviderPreset)
    }
}
