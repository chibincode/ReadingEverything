import Foundation

final class AIClient {
    func grammarRephrase(text: String, config: AIProviderConfig) async throws -> GrammarResult {
        let body: [String: Any] = [
            "task": "grammar_rephrase",
            "text": text,
            "model": config.model
        ]
        let data = try await postJSON(config: config, body: body)
        let decoded = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = decoded as? [String: Any] else {
            throw AIError.invalidResponse
        }
        let corrected = dict["corrected"] as? String ?? ""
        let rephrased = dict["rephrased"] as? String ?? ""
        let notes = dict["notes"] as? String ?? ""
        if corrected.isEmpty && rephrased.isEmpty {
            throw AIError.invalidResponse
        }
        return GrammarResult(corrected: corrected, rephrased: rephrased, notes: notes)
    }

    func ttsAudio(text: String, config: AIProviderConfig, preset: AIProviderPreset) async throws -> Data {
        let provider = resolveTTSProvider(preset: preset, baseURL: config.baseURL)

        if provider == .doubaoOpenSpeech {
            guard let request = makeOpenSpeechTTSRequest(text: text, config: config) else {
                throw AIError.invalidConfig
            }
            let (data, response) = try await send(request)
            return try parseTTSAudio(data: data, response: response)
        }

        if let request = makeArkTTSRequest(text: text, config: config) {
            let (data, response) = try await send(request)
            return try parseTTSAudio(data: data, response: response)
        }

        let body: [String: Any] = [
            "task": "tts",
            "text": text,
            "model": config.model,
            "voice": config.voice
        ]
        return try await postJSON(config: config, body: body)
    }

    private func postJSON(config: AIProviderConfig, body: [String: Any]) async throws -> Data {
        guard let url = URL(string: config.baseURL), !config.baseURL.isEmpty else {
            throw AIError.invalidConfig
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyHeaders(to: &request, config: config)
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        let (data, response) = try await send(request)
        try validateHTTP(response: response, data: data)
        return data
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }

    private func applyHeaders(
        to request: inout URLRequest,
        config: AIProviderConfig,
        includeBearerAuth: Bool = true,
        includeCustomHeaders: Bool = true
    ) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if includeCustomHeaders {
            let extraHeaders = parseHeadersJSON(config.headersJSON)
            for (key, value) in extraHeaders {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        guard includeBearerAuth else { return }
        let existingAuth = request
            .value(forHTTPHeaderField: "Authorization")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if existingAuth.isEmpty {
            let auth = authorizationHeaderValue(from: config.apiKey)
            if !auth.isEmpty {
                request.setValue(auth, forHTTPHeaderField: "Authorization")
            }
        }
    }

    private func resolveTTSProvider(preset: AIProviderPreset, baseURL: String) -> TTSProvider {
        switch preset {
        case .doubaoOpenSpeech:
            return .doubaoOpenSpeech
        case .doubaoArk:
            return .arkCompatible
        case .custom:
            return isOpenSpeechURL(baseURL) ? .doubaoOpenSpeech : .arkCompatible
        }
    }

    private func makeArkTTSRequest(text: String, config: AIProviderConfig) -> URLRequest? {
        guard let baseURL = URL(string: config.baseURL), !config.baseURL.isEmpty else {
            return nil
        }
        guard let host = baseURL.host?.lowercased(), host.contains("volces.com") else {
            return nil
        }
        guard !config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let ttsURL = arkTTSURL(from: baseURL)
        var request = URLRequest(url: ttsURL)
        request.httpMethod = "POST"
        applyHeaders(to: &request, config: config)

        let body: [String: Any] = [
            "model": config.model,
            "input": text,
            "voice": config.voice,
            "response_format": "mp3"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        return request
    }

    private func makeOpenSpeechTTSRequest(text: String, config: AIProviderConfig) -> URLRequest? {
        guard let url = URL(string: config.baseURL), !config.baseURL.isEmpty else {
            return nil
        }

        let appID = config.appID.trimmingCharacters(in: .whitespacesAndNewlines)
        let resourceID = config.resourceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let accessKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let speaker = config.voice.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appID.isEmpty, !resourceID.isEmpty, !accessKey.isEmpty, !speaker.isEmpty else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyHeaders(to: &request, config: config, includeBearerAuth: false, includeCustomHeaders: false)
        request.setValue(appID, forHTTPHeaderField: "X-Api-App-Id")
        request.setValue(accessKey, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: "X-Api-Request-Id")

        let reqParams: [String: Any] = [
            "text": text,
            "speaker": speaker,
            "audio_params": [
                "format": "mp3",
                "sample_rate": 24000
            ]
        ]

        let body: [String: Any] = [
            "user": ["uid": appID],
            "req_params": reqParams
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        return request
    }

    private func arkTTSURL(from baseURL: URL) -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL
        }

        let trimmedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmedPath.contains("audio/speech") {
            return baseURL
        }

        let prefix: String
        if trimmedPath.isEmpty {
            prefix = "api/v3"
        } else if let apiV3Prefix = extractAPIV3Prefix(from: trimmedPath) {
            prefix = apiV3Prefix
        } else {
            prefix = "api/v3"
        }

        components.path = "/" + prefix + "/audio/speech"
        components.query = nil
        return components.url ?? baseURL
    }

    private func parseTTSAudio(data: Data, response: URLResponse) throws -> Data {
        try validateHTTP(response: response, data: data)

        if let http = response as? HTTPURLResponse {
            let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            if contentType.contains("audio/") || contentType.contains("octet-stream") {
                guard !data.isEmpty else { throw AIError.invalidResponse }
                return data
            }
        }

        if let decoded = decodeAudioPayload(data) {
            return decoded
        }

        throw AIError.invalidResponse
    }

    private func decodeAudioPayload(_ data: Data) -> Data? {
        if let object = try? JSONSerialization.jsonObject(with: data, options: []),
           let decoded = decodeAudio(fromJSONObject: object) {
            return decoded
        }

        guard let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        var merged = Data()
        let lines = text.split(whereSeparator: \.isNewline)
        for rawLine in lines {
            var line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("data:") {
                line = String(line.dropFirst("data:".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if line == "[DONE]" {
                continue
            }
            guard let lineData = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData, options: []),
                  let chunk = decodeAudio(fromJSONObject: object) else {
                continue
            }
            merged.append(chunk)
        }
        return merged.isEmpty ? nil : merged
    }

    private func decodeAudio(fromJSONObject object: Any) -> Data? {
        if let dict = object as? [String: Any] {
            if let base64 = firstBase64AudioCandidate(in: dict),
               let decoded = decodeBase64Audio(base64) {
                return decoded
            }
            if let dataValue = dict["data"] {
                return decodeAudio(fromJSONObject: dataValue)
            }
            if let resultValue = dict["result"] {
                return decodeAudio(fromJSONObject: resultValue)
            }
            return nil
        }

        if let array = object as? [Any] {
            var merged = Data()
            for item in array {
                if let decoded = decodeAudio(fromJSONObject: item) {
                    merged.append(decoded)
                }
            }
            return merged.isEmpty ? nil : merged
        }
        return nil
    }

    private func extractAPIV3Prefix(from path: String) -> String? {
        let tokens = path.split(separator: "/")
        guard let apiIndex = tokens.firstIndex(where: { $0.lowercased() == "api" }) else {
            return nil
        }
        let v3Index = tokens.index(after: apiIndex)
        guard v3Index < tokens.endIndex, tokens[v3Index].lowercased() == "v3" else {
            return nil
        }
        return tokens[...v3Index].joined(separator: "/")
    }

    private func isOpenSpeechURL(_ baseURL: String) -> Bool {
        guard let host = URL(string: baseURL)?.host?.lowercased() else {
            return false
        }
        return host.contains("openspeech.bytedance.com")
    }

    private func firstBase64AudioCandidate(in dict: [String: Any]) -> String? {
        let keys = ["audio", "data", "output_audio", "audio_base64", "b64_audio"]
        for key in keys {
            if let value = dict[key], let text = extractBase64String(from: value) {
                return text
            }
        }
        return nil
    }

    private func extractBase64String(from value: Any) -> String? {
        if let text = value as? String, !text.isEmpty {
            return text
        }
        if let dict = value as? [String: Any] {
            for key in ["audio", "data", "output_audio", "audio_base64", "b64_audio"] {
                if let nested = dict[key], let text = extractBase64String(from: nested) {
                    return text
                }
            }
        }
        return nil
    }

    private func decodeBase64Audio(_ raw: String) -> Data? {
        if let direct = Data(base64Encoded: raw) {
            return direct
        }
        if let comma = raw.firstIndex(of: ",") {
            let suffix = String(raw[raw.index(after: comma)...])
            return Data(base64Encoded: suffix)
        }
        return nil
    }

    private func authorizationHeaderValue(from raw: String) -> String {
        var token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return "" }

        if token.lowercased().hasPrefix("authorization:") {
            token = String(token.dropFirst("authorization:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if token.hasPrefix("\""), token.hasSuffix("\""), token.count > 1 {
            token = String(token.dropFirst().dropLast())
        }

        if token.lowercased().hasPrefix("bearer ") {
            let trimmed = String(token.dropFirst("bearer ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "" : "Bearer \(trimmed)"
        }

        return "Bearer \(token)"
    }

    private func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw AIError.httpError(code: http.statusCode, message: extractErrorMessage(from: data))
        }
    }

    private func extractErrorMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }

        if let object = try? JSONSerialization.jsonObject(with: data, options: []),
           let dict = object as? [String: Any] {
            if let message = dict["message"] as? String, !message.isEmpty {
                return message
            }
            if let errorDict = dict["error"] as? [String: Any] {
                if let message = errorDict["message"] as? String, !message.isEmpty {
                    return message
                }
                if let code = errorDict["code"] as? String, !code.isEmpty {
                    return code
                }
            }
            if let code = dict["code"] as? String, !code.isEmpty {
                return code
            }
            if let errorMsg = dict["error_msg"] as? String, !errorMsg.isEmpty {
                return errorMsg
            }
            if let msg = dict["msg"] as? String, !msg.isEmpty {
                return msg
            }
        }

        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return String(text.prefix(240))
        }

        return nil
    }

    private func parseHeadersJSON(_ raw: String) -> [String: String] {
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = raw.data(using: .utf8) else { return [:] }
        let decoded = try? JSONSerialization.jsonObject(with: data, options: [])
        return decoded as? [String: String] ?? [:]
    }
}

private enum TTSProvider {
    case arkCompatible
    case doubaoOpenSpeech
}

enum AIError: Error {
    case invalidConfig
    case invalidResponse
    case httpError(code: Int, message: String?)
}
