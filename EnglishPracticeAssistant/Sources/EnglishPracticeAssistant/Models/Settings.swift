import Combine
import Foundation

struct HotkeyBindings: Codable, Equatable {
    var hoverRead: KeyCombo
    var readSelection: KeyCombo
    var grammar: KeyCombo
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

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var hotkeyBindings: HotkeyBindings
    @Published var aiConfig: AIProviderConfig
    @Published var aiPreset: AIProviderPreset
    @Published var useAITTS: Bool
    @Published var showDetectionOverlay: Bool
    @Published var showFloatingBarOffsetDebug: Bool

    private let defaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()

    private init() {
        hotkeyBindings = SettingsStore.loadHotkeys(from: defaults) ?? HotkeyBindings(
            hoverRead: KeyCombo.modifierOnly(.control),
            readSelection: KeyCombo(keyCode: 15, modifiers: [.option]),
            grammar: KeyCombo(keyCode: 5, modifiers: [.option])
        )
        aiConfig = SettingsStore.loadAIConfig(from: defaults) ?? AIProviderConfig(
            baseURL: "",
            model: "",
            voice: "",
            appID: "",
            resourceID: "",
            headersJSON: "",
            apiKey: KeychainStore.read(key: "apiKey") ?? ""
        )
        aiPreset = SettingsStore.loadAIPreset(from: defaults) ?? .custom
        useAITTS = defaults.bool(forKey: "useAITTS")
        showDetectionOverlay = defaults.bool(forKey: "showDetectionOverlay")
        showFloatingBarOffsetDebug = defaults.bool(forKey: "showFloatingBarOffsetDebug")

        $hotkeyBindings
            .sink { [weak self] bindings in
                self?.saveHotkeys(bindings)
            }
            .store(in: &cancellables)

        $aiConfig
            .sink { [weak self] config in
                self?.saveAIConfig(config)
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

    private static func loadHotkeys(from defaults: UserDefaults) -> HotkeyBindings? {
        guard let data = defaults.data(forKey: "hotkeyBindings") else { return nil }
        return try? JSONDecoder().decode(HotkeyBindings.self, from: data)
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

    private func saveAIConfig(_ config: AIProviderConfig) {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: "aiConfig")
        }
        if !config.apiKey.isEmpty {
            KeychainStore.save(key: "apiKey", value: config.apiKey)
        }
    }
}
