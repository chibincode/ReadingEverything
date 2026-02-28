import Foundation
import os

final class AIClient {
    private let legacyFallbackStatusCodes: Set<Int> = [400, 404, 422]
    private let grammarRequestTimeout: TimeInterval = 20
    private let grammarRetryDelayNs: UInt64 = 600_000_000
    private let grammarMaxAttempts = 2
    private let grammarRetryableHTTPStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504]
    private let glmChatCompletionsEndpoint = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
    private let logger = Logger(subsystem: "EnglishPracticeAssistant", category: "GrammarCheck")

    func grammarCheck(
        text: String,
        preset: GrammarProviderPreset,
        config: GrammarProviderConfig
    ) async throws -> GrammarCheckResult {
        switch preset {
        case .glmDirect:
            return try await grammarCheckViaGLM(text: text, config: config)
        case .geminiDirect:
            return try await grammarCheckViaGemini(text: text, config: config)
        case .custom:
            return try await grammarCheckViaCustomBackend(text: text, config: config)
        }
    }

    func translate(
        text: String,
        preset: GrammarProviderPreset,
        config: GrammarProviderConfig,
        targetLanguage: String
    ) async throws -> TranslationResult {
        switch preset {
        case .glmDirect:
            return try await translateViaGLM(
                text: text,
                config: config,
                targetLanguage: targetLanguage
            )
        case .geminiDirect:
            return try await translateViaGemini(
                text: text,
                config: config,
                targetLanguage: targetLanguage
            )
        case .custom:
            return try await translateViaCustomBackend(
                text: text,
                config: config,
                targetLanguage: targetLanguage
            )
        }
    }

    private func grammarCheckViaGemini(text: String, config: GrammarProviderConfig) async throws -> GrammarCheckResult {
        let primaryModel = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !primaryModel.isEmpty else { throw AIError.invalidConfig }

        var candidateModels: [String] = []
        for model in [primaryModel, "gemini-3-flash-preview", "gemini-2.5-flash"] {
            if !candidateModels.contains(model) {
                candidateModels.append(model)
            }
        }

        var lastError: Error = AIError.invalidResponse
        for (index, model) in candidateModels.enumerated() {
            do {
                return try await grammarCheckViaGeminiModel(text: text, model: model, apiKey: config.apiKey)
            } catch {
                let normalized = normalizeGrammarError(error)
                lastError = normalized
                if shouldFallbackModel(for: normalized), index + 1 < candidateModels.count {
                    logger.info(
                        "Fallback Gemini model from \(model, privacy: .public) to \(candidateModels[index + 1], privacy: .public)"
                    )
                    continue
                }
                throw normalized
            }
        }

        throw lastError
    }

    private func grammarCheckViaGLM(text: String, config: GrammarProviderConfig) async throws -> GrammarCheckResult {
        let primaryModel = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !primaryModel.isEmpty else { throw AIError.invalidConfig }

        var candidateModels: [String] = []
        for model in [primaryModel, "glm-4-flash-250414", "glm-4.5-flash", "glm-5-air"] {
            if !candidateModels.contains(model) {
                candidateModels.append(model)
            }
        }

        var lastError: Error = AIError.invalidResponse
        for (index, model) in candidateModels.enumerated() {
            do {
                return try await grammarCheckViaGLMModel(text: text, model: model, apiKey: config.apiKey)
            } catch {
                let normalized = normalizeGrammarError(error)
                lastError = normalized
                if shouldFallbackModel(for: normalized), index + 1 < candidateModels.count {
                    logger.info(
                        "Fallback GLM model from \(model, privacy: .public) to \(candidateModels[index + 1], privacy: .public)"
                    )
                    continue
                }
                throw normalized
            }
        }

        throw lastError
    }

    private func grammarCheckViaGLMModel(
        text: String,
        model: String,
        apiKey: String
    ) async throws -> GrammarCheckResult {
        let prompt = """
        Rewrite the provided text into three alternatives.
        Return JSON only with keys: clean_up, better_flow, concise, notes.
        Keep original meaning.

        text:
        \(text)
        """

        let body: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "system",
                    "content": "You are a precise writing assistant. Output valid JSON only."
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "temperature": 0.2,
            "response_format": [
                "type": "json_object"
            ]
        ]

        let data = try await postGrammarJSON(
            urlString: glmChatCompletionsEndpoint,
            apiKey: apiKey,
            headersJSON: "",
            body: body,
            includeBearerAuth: true,
            includeCustomHeaders: false,
            provider: "glm_direct",
            model: model,
            taskLabel: "grammar_check"
        )

        return try parseGLMGrammarResult(data: data, sourceText: text)
    }

    private func grammarCheckViaGeminiModel(
        text: String,
        model: String,
        apiKey: String
    ) async throws -> GrammarCheckResult {
        let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):generateContent"
        let prompt = """
        Rewrite the provided text into three alternatives.
        Return JSON only with keys: clean_up, better_flow, concise, notes.
        Keep original meaning.

        text:
        \(text)
        """

        let body: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.2,
                "responseMimeType": "application/json"
            ]
        ]

        let data = try await postGrammarJSON(
            urlString: endpoint,
            apiKey: apiKey,
            headersJSON: "",
            body: body,
            includeBearerAuth: false,
            includeCustomHeaders: false,
            extraHeaders: ["x-goog-api-key": apiKey],
            provider: "gemini_direct",
            model: model,
            taskLabel: "grammar_check"
        )

        return try parseGeminiGrammarResult(data: data, sourceText: text)
    }

    private func grammarCheckViaCustomBackend(text: String, config: GrammarProviderConfig) async throws -> GrammarCheckResult {
        let body: [String: Any] = [
            "task": "grammar_check",
            "text": text,
            "model": config.model,
            "variants": ["clean_up", "better_flow", "concise"]
        ]
        do {
            let data = try await postGrammarJSON(
                urlString: config.baseURL,
                apiKey: config.apiKey,
                headersJSON: config.headersJSON,
                body: body,
                provider: "custom_backend",
                model: config.model,
                taskLabel: "grammar_check"
            )
            return try parseGrammarResult(data: data, sourceText: text)
        } catch let AIError.httpError(code, _) where legacyFallbackStatusCodes.contains(code) {
            let legacyBody: [String: Any] = [
                "task": "grammar_rephrase",
                "text": text,
                "model": config.model
            ]
            let data = try await postGrammarJSON(
                urlString: config.baseURL,
                apiKey: config.apiKey,
                headersJSON: config.headersJSON,
                body: legacyBody,
                provider: "custom_backend",
                model: config.model,
                taskLabel: "grammar_rephrase"
            )
            return try parseGrammarResult(data: data, sourceText: text, forcedLegacyFallback: true)
        }
    }

    private func shouldFallbackModel(for error: Error) -> Bool {
        guard case let AIError.httpError(code, message) = error else {
            return false
        }
        guard code == 400 || code == 404 else {
            return false
        }
        let lowered = (message ?? "").lowercased()
        if lowered.isEmpty {
            return true
        }
        let keywords = [
            "model",
            "not found",
            "not available",
            "not supported",
            "unsupported",
            "unknown",
            "does not exist",
            "invalid model",
            "模型",
            "不存在",
            "不可用",
            "不支持",
            "无效"
        ]
        return keywords.contains(where: { lowered.contains($0) })
    }

    private func parseGrammarResult(
        data: Data,
        sourceText: String,
        forcedLegacyFallback: Bool = false
    ) throws -> GrammarCheckResult {
        let decoded = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = decoded as? [String: Any] else {
            throw AIError.invalidResponse
        }

        return try grammarResult(from: dict, sourceText: sourceText, forcedLegacyFallback: forcedLegacyFallback)
    }

    private func parseGeminiGrammarResult(data: Data, sourceText: String) throws -> GrammarCheckResult {
        let decoded = try JSONSerialization.jsonObject(with: data, options: [])
        if let dict = decoded as? [String: Any] {
            if let payload = findGrammarPayload(in: dict) {
                return try grammarResult(from: payload, sourceText: sourceText)
            }
            if let candidateText = firstGeminiCandidateText(in: dict),
               let payload = parseJSONStringObject(from: candidateText) {
                return try grammarResult(from: payload, sourceText: sourceText)
            }
        }
        throw AIError.invalidResponse
    }

    private func parseGLMGrammarResult(data: Data, sourceText: String) throws -> GrammarCheckResult {
        let decoded = try JSONSerialization.jsonObject(with: data, options: [])
        if let dict = decoded as? [String: Any] {
            if let payload = findGrammarPayload(in: dict) {
                return try grammarResult(from: payload, sourceText: sourceText)
            }
            if let candidateText = firstOpenAIChoiceText(in: dict),
               let payload = parseJSONStringObject(from: candidateText) {
                return try grammarResult(from: payload, sourceText: sourceText)
            }
        }
        throw AIError.invalidResponse
    }

    private func grammarResult(
        from dict: [String: Any],
        sourceText: String,
        forcedLegacyFallback: Bool = false
    ) throws -> GrammarCheckResult {
        
        let cleanUp = nonEmptyString(from: dict["clean_up"])
        let betterFlow = nonEmptyString(from: dict["better_flow"])
        let conciseFromNew = nonEmptyString(from: dict["concise"])
        let legacyCorrected = nonEmptyString(from: dict["corrected"])
        let legacyRephrased = nonEmptyString(from: dict["rephrased"])
        let notes = nonEmptyString(from: dict["notes"])

        var resolvedCleanUp = cleanUp
        var resolvedBetterFlow = betterFlow
        var resolvedConcise = conciseFromNew
        var usedLegacyFallback = forcedLegacyFallback

        if resolvedCleanUp.isEmpty, !legacyCorrected.isEmpty {
            resolvedCleanUp = legacyCorrected
            usedLegacyFallback = true
        }
        if resolvedBetterFlow.isEmpty, !legacyRephrased.isEmpty {
            resolvedBetterFlow = legacyRephrased
            usedLegacyFallback = true
        }
        if resolvedConcise.isEmpty {
            if !legacyRephrased.isEmpty {
                resolvedConcise = legacyRephrased
                usedLegacyFallback = true
            } else if !legacyCorrected.isEmpty {
                resolvedConcise = legacyCorrected
                usedLegacyFallback = true
            }
        }

        if resolvedCleanUp.isEmpty && resolvedBetterFlow.isEmpty && resolvedConcise.isEmpty {
            throw AIError.invalidResponse
        }

        if resolvedCleanUp.isEmpty {
            resolvedCleanUp = !resolvedBetterFlow.isEmpty ? resolvedBetterFlow : resolvedConcise
        }
        if resolvedBetterFlow.isEmpty {
            resolvedBetterFlow = !resolvedCleanUp.isEmpty ? resolvedCleanUp : resolvedConcise
        }
        if resolvedConcise.isEmpty {
            resolvedConcise = !resolvedBetterFlow.isEmpty ? resolvedBetterFlow : resolvedCleanUp
        }

        return GrammarCheckResult(
            sourceText: sourceText.trimmingCharacters(in: .whitespacesAndNewlines),
            cleanUp: resolvedCleanUp,
            betterFlow: resolvedBetterFlow,
            concise: resolvedConcise,
            notes: notes,
            usedLegacyFallback: usedLegacyFallback
        )
    }

    private func translateViaGemini(
        text: String,
        config: GrammarProviderConfig,
        targetLanguage: String
    ) async throws -> TranslationResult {
        let primaryModel = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !primaryModel.isEmpty else { throw AIError.invalidConfig }

        var candidateModels: [String] = []
        for model in [primaryModel, "gemini-3-flash-preview", "gemini-2.5-flash"] {
            if !candidateModels.contains(model) {
                candidateModels.append(model)
            }
        }

        var lastError: Error = AIError.invalidResponse
        for (index, model) in candidateModels.enumerated() {
            do {
                return try await translateViaGeminiModel(
                    text: text,
                    model: model,
                    apiKey: config.apiKey,
                    targetLanguage: targetLanguage
                )
            } catch {
                let normalized = normalizeGrammarError(error)
                lastError = normalized
                if shouldFallbackModel(for: normalized), index + 1 < candidateModels.count {
                    logger.info(
                        "Fallback Gemini model from \(model, privacy: .public) to \(candidateModels[index + 1], privacy: .public)"
                    )
                    continue
                }
                throw normalized
            }
        }

        throw lastError
    }

    private func translateViaGeminiModel(
        text: String,
        model: String,
        apiKey: String,
        targetLanguage: String
    ) async throws -> TranslationResult {
        let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):generateContent"
        let prompt = """
        Translate the provided text to the target language.
        Target language: \(targetLanguage).
        Auto-detect the source language.
        Return JSON only with keys: translation, detected_source_language, notes.

        text:
        \(text)
        """

        let body: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.2,
                "responseMimeType": "application/json"
            ]
        ]

        let data = try await postGrammarJSON(
            urlString: endpoint,
            apiKey: apiKey,
            headersJSON: "",
            body: body,
            includeBearerAuth: false,
            includeCustomHeaders: false,
            extraHeaders: ["x-goog-api-key": apiKey],
            provider: "gemini_direct",
            model: model,
            taskLabel: "translation"
        )

        return try parseGeminiTranslationResult(
            data: data,
            sourceText: text,
            targetLanguage: targetLanguage
        )
    }

    private func translateViaGLM(
        text: String,
        config: GrammarProviderConfig,
        targetLanguage: String
    ) async throws -> TranslationResult {
        let primaryModel = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !primaryModel.isEmpty else { throw AIError.invalidConfig }

        var candidateModels: [String] = []
        for model in [primaryModel, "glm-4-flash-250414", "glm-4.5-flash", "glm-5-air"] {
            if !candidateModels.contains(model) {
                candidateModels.append(model)
            }
        }

        var lastError: Error = AIError.invalidResponse
        for (index, model) in candidateModels.enumerated() {
            do {
                return try await translateViaGLMModel(
                    text: text,
                    model: model,
                    apiKey: config.apiKey,
                    targetLanguage: targetLanguage
                )
            } catch {
                let normalized = normalizeGrammarError(error)
                lastError = normalized
                if shouldFallbackModel(for: normalized), index + 1 < candidateModels.count {
                    logger.info(
                        "Fallback GLM model from \(model, privacy: .public) to \(candidateModels[index + 1], privacy: .public)"
                    )
                    continue
                }
                throw normalized
            }
        }

        throw lastError
    }

    private func translateViaGLMModel(
        text: String,
        model: String,
        apiKey: String,
        targetLanguage: String
    ) async throws -> TranslationResult {
        let prompt = """
        Translate the provided text to the target language.
        Target language: \(targetLanguage).
        Auto-detect the source language.
        Return JSON only with keys: translation, detected_source_language, notes.

        text:
        \(text)
        """

        let body: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "system",
                    "content": "You are a precise translation assistant. Output valid JSON only."
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "temperature": 0.2,
            "response_format": [
                "type": "json_object"
            ]
        ]

        let data = try await postGrammarJSON(
            urlString: glmChatCompletionsEndpoint,
            apiKey: apiKey,
            headersJSON: "",
            body: body,
            includeBearerAuth: true,
            includeCustomHeaders: false,
            provider: "glm_direct",
            model: model,
            taskLabel: "translation"
        )

        return try parseGLMTranslationResult(
            data: data,
            sourceText: text,
            targetLanguage: targetLanguage
        )
    }

    private func translateViaCustomBackend(
        text: String,
        config: GrammarProviderConfig,
        targetLanguage: String
    ) async throws -> TranslationResult {
        let body: [String: Any] = [
            "task": "translate",
            "text": text,
            "model": config.model,
            "source_language": "auto",
            "target_language": targetLanguage
        ]

        do {
            let data = try await postGrammarJSON(
                urlString: config.baseURL,
                apiKey: config.apiKey,
                headersJSON: config.headersJSON,
                body: body,
                provider: "custom_backend",
                model: config.model,
                taskLabel: "translate"
            )
            return try parseTranslationResult(
                data: data,
                sourceText: text,
                targetLanguage: targetLanguage
            )
        } catch let AIError.httpError(code, _) where legacyFallbackStatusCodes.contains(code) {
            let legacyBody: [String: Any] = [
                "task": "translation",
                "text": text,
                "model": config.model,
                "source_language": "auto",
                "target_language": targetLanguage
            ]
            let data = try await postGrammarJSON(
                urlString: config.baseURL,
                apiKey: config.apiKey,
                headersJSON: config.headersJSON,
                body: legacyBody,
                provider: "custom_backend",
                model: config.model,
                taskLabel: "translation"
            )
            return try parseTranslationResult(
                data: data,
                sourceText: text,
                targetLanguage: targetLanguage,
                forcedLegacyFallback: true
            )
        }
    }

    private func parseTranslationResult(
        data: Data,
        sourceText: String,
        targetLanguage: String,
        forcedLegacyFallback: Bool = false
    ) throws -> TranslationResult {
        let decoded = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = decoded as? [String: Any] else {
            throw AIError.invalidResponse
        }
        return try translationResult(
            from: dict,
            sourceText: sourceText,
            targetLanguage: targetLanguage,
            forcedLegacyFallback: forcedLegacyFallback
        )
    }

    private func parseGeminiTranslationResult(
        data: Data,
        sourceText: String,
        targetLanguage: String
    ) throws -> TranslationResult {
        let decoded = try JSONSerialization.jsonObject(with: data, options: [])
        if let dict = decoded as? [String: Any] {
            if let payload = findTranslationPayload(in: dict) {
                return try translationResult(
                    from: payload,
                    sourceText: sourceText,
                    targetLanguage: targetLanguage
                )
            }
            if let candidateText = firstGeminiCandidateText(in: dict),
               let payload = parseJSONStringObject(from: candidateText) {
                return try translationResult(
                    from: payload,
                    sourceText: sourceText,
                    targetLanguage: targetLanguage
                )
            }
        }
        throw AIError.invalidResponse
    }

    private func parseGLMTranslationResult(
        data: Data,
        sourceText: String,
        targetLanguage: String
    ) throws -> TranslationResult {
        let decoded = try JSONSerialization.jsonObject(with: data, options: [])
        if let dict = decoded as? [String: Any] {
            if let payload = findTranslationPayload(in: dict) {
                return try translationResult(
                    from: payload,
                    sourceText: sourceText,
                    targetLanguage: targetLanguage
                )
            }
            if let candidateText = firstOpenAIChoiceText(in: dict),
               let payload = parseJSONStringObject(from: candidateText) {
                return try translationResult(
                    from: payload,
                    sourceText: sourceText,
                    targetLanguage: targetLanguage
                )
            }
        }
        throw AIError.invalidResponse
    }

    private func translationResult(
        from dict: [String: Any],
        sourceText: String,
        targetLanguage: String,
        forcedLegacyFallback: Bool = false
    ) throws -> TranslationResult {
        let primaryTranslation = nonEmptyString(from: dict["translation"])
        let candidateTranslation = firstNonEmptyString(
            from: dict,
            keys: ["translated_text", "translatedText", "output", "result"]
        )
        let fallbackPayloadTranslation: String = {
            if let nested = dict["data"] as? [String: Any] {
                return firstNonEmptyString(from: nested, keys: ["translation", "translated_text", "result"])
            }
            if let nested = dict["result"] as? [String: Any] {
                return firstNonEmptyString(from: nested, keys: ["translation", "translated_text", "text"])
            }
            if let nested = dict["output"] as? [String: Any] {
                return firstNonEmptyString(from: nested, keys: ["translation", "translated_text", "text"])
            }
            return ""
        }()

        var resolvedTranslation = primaryTranslation
        var usedLegacyFallback = forcedLegacyFallback

        if resolvedTranslation.isEmpty, !candidateTranslation.isEmpty {
            resolvedTranslation = candidateTranslation
            usedLegacyFallback = true
        }
        if resolvedTranslation.isEmpty, !fallbackPayloadTranslation.isEmpty {
            resolvedTranslation = fallbackPayloadTranslation
            usedLegacyFallback = true
        }
        if resolvedTranslation.isEmpty {
            throw AIError.invalidResponse
        }

        let sourceLanguage = firstNonEmptyString(
            from: dict,
            keys: [
                "detected_source_language",
                "source_language",
                "sourceLanguage",
                "from"
            ]
        )
        let notes = firstNonEmptyString(from: dict, keys: ["notes", "note", "explanation"])

        return TranslationResult(
            sourceText: sourceText.trimmingCharacters(in: .whitespacesAndNewlines),
            translatedText: resolvedTranslation,
            detectedSourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            notes: notes,
            usedLegacyFallback: usedLegacyFallback
        )
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
        try await postJSON(
            urlString: config.baseURL,
            apiKey: config.apiKey,
            headersJSON: config.headersJSON,
            body: body
        )
    }

    private func postGrammarJSON(
        urlString: String,
        apiKey: String,
        headersJSON: String,
        body: [String: Any],
        includeBearerAuth: Bool = true,
        includeCustomHeaders: Bool = true,
        extraHeaders: [String: String] = [:],
        provider: String,
        model: String,
        taskLabel: String
    ) async throws -> Data {
        try await withGrammarRetry(provider: provider, model: model, taskLabel: taskLabel) { attempt in
            guard let url = URL(string: urlString), !urlString.isEmpty else {
                throw AIError.invalidConfig
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = grammarRequestTimeout
            applyHeaders(
                to: &request,
                apiKey: apiKey,
                headersJSON: headersJSON,
                includeBearerAuth: includeBearerAuth,
                includeCustomHeaders: includeCustomHeaders,
                extraHeaders: extraHeaders
            )
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

            let start = Date()
            do {
                let (data, response) = try await send(request)
                try validateHTTP(response: response, data: data)
                let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
                logger.info(
                    "Grammar request success provider=\(provider, privacy: .public) task=\(taskLabel, privacy: .public) model=\(model, privacy: .public) attempt=\(attempt) duration_ms=\(elapsedMs)"
                )
                return data
            } catch {
                let normalized = normalizeGrammarError(error)
                let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
                logger.error(
                    "Grammar request failed provider=\(provider, privacy: .public) task=\(taskLabel, privacy: .public) model=\(model, privacy: .public) attempt=\(attempt) duration_ms=\(elapsedMs) error=\(String(describing: normalized), privacy: .public)"
                )
                throw normalized
            }
        }
    }

    private func withGrammarRetry<T>(
        provider: String,
        model: String,
        taskLabel: String,
        operation: (Int) async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 1...grammarMaxAttempts {
            do {
                return try await operation(attempt)
            } catch {
                let normalized = normalizeGrammarError(error)
                lastError = normalized
                let shouldRetry = attempt < grammarMaxAttempts && shouldRetryGrammarError(normalized)
                if shouldRetry {
                    logger.info(
                        "Retry grammar request provider=\(provider, privacy: .public) task=\(taskLabel, privacy: .public) model=\(model, privacy: .public) next_attempt=\(attempt + 1)"
                    )
                    try await Task.sleep(nanoseconds: grammarRetryDelayNs)
                    continue
                }
                throw normalized
            }
        }
        throw lastError ?? AIError.invalidResponse
    }

    private func shouldRetryGrammarError(_ error: Error) -> Bool {
        switch error {
        case AIError.timeout:
            return true
        case AIError.network:
            return true
        case let AIError.httpError(code, _):
            return grammarRetryableHTTPStatusCodes.contains(code)
        default:
            return false
        }
    }

    private func normalizeGrammarError(_ error: Error) -> AIError {
        if let aiError = error as? AIError {
            return aiError
        }

        if error is CancellationError {
            return .cancelled
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return .timeout
            case .cancelled:
                return .cancelled
            case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
                 .notConnectedToInternet, .dnsLookupFailed, .internationalRoamingOff,
                 .callIsActive, .dataNotAllowed, .cannotLoadFromNetwork:
                return .network(message: urlError.localizedDescription)
            default:
                return .network(message: urlError.localizedDescription)
            }
        }

        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return .network(message: message.isEmpty ? "Unknown network error" : message)
    }

    private func postJSON(
        urlString: String,
        apiKey: String,
        headersJSON: String,
        body: [String: Any],
        includeBearerAuth: Bool = true,
        includeCustomHeaders: Bool = true,
        extraHeaders: [String: String] = [:]
    ) async throws -> Data {
        guard let url = URL(string: urlString), !urlString.isEmpty else {
            throw AIError.invalidConfig
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyHeaders(
            to: &request,
            apiKey: apiKey,
            headersJSON: headersJSON,
            includeBearerAuth: includeBearerAuth,
            includeCustomHeaders: includeCustomHeaders,
            extraHeaders: extraHeaders
        )
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
        applyHeaders(
            to: &request,
            apiKey: config.apiKey,
            headersJSON: config.headersJSON,
            includeBearerAuth: includeBearerAuth,
            includeCustomHeaders: includeCustomHeaders
        )
    }

    private func applyHeaders(
        to request: inout URLRequest,
        apiKey: String,
        headersJSON: String,
        includeBearerAuth: Bool = true,
        includeCustomHeaders: Bool = true,
        extraHeaders: [String: String] = [:]
    ) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if includeCustomHeaders {
            let parsedHeaders = parseHeadersJSON(headersJSON)
            for (key, value) in parsedHeaders {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        guard includeBearerAuth else { return }
        let existingAuth = request
            .value(forHTTPHeaderField: "Authorization")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if existingAuth.isEmpty {
            let auth = authorizationHeaderValue(from: apiKey)
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

    private func findGrammarPayload(in object: Any) -> [String: Any]? {
        if let dict = object as? [String: Any] {
            let keys = Set(dict.keys.map { $0.lowercased() })
            let candidateKeys = ["clean_up", "better_flow", "concise", "corrected", "rephrased"]
            if candidateKeys.contains(where: { keys.contains($0) }) {
                return dict
            }

            for value in dict.values {
                if let nested = findGrammarPayload(in: value) {
                    return nested
                }
            }
            return nil
        }

        if let array = object as? [Any] {
            for item in array {
                if let nested = findGrammarPayload(in: item) {
                    return nested
                }
            }
        }
        return nil
    }

    private func findTranslationPayload(in object: Any) -> [String: Any]? {
        if let dict = object as? [String: Any] {
            let keys = Set(dict.keys.map { $0.lowercased() })
            let candidateKeys = ["translation", "translated_text", "translatedtext", "source_language"]
            if candidateKeys.contains(where: { keys.contains($0) }) {
                return dict
            }

            for value in dict.values {
                if let nested = findTranslationPayload(in: value) {
                    return nested
                }
            }
            return nil
        }

        if let array = object as? [Any] {
            for item in array {
                if let nested = findTranslationPayload(in: item) {
                    return nested
                }
            }
        }
        return nil
    }

    private func firstGeminiCandidateText(in dict: [String: Any]) -> String? {
        guard let candidates = dict["candidates"] as? [[String: Any]] else {
            return nil
        }
        for candidate in candidates {
            guard let content = candidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else {
                continue
            }
            for part in parts {
                let text = nonEmptyString(from: part["text"])
                if !text.isEmpty {
                    return text
                }
            }
        }
        return nil
    }

    private func firstOpenAIChoiceText(in dict: [String: Any]) -> String? {
        guard let choices = dict["choices"] as? [[String: Any]] else {
            return nil
        }

        for choice in choices {
            if let message = choice["message"] as? [String: Any] {
                let text = extractOpenAIContentText(from: message["content"])
                if !text.isEmpty {
                    return text
                }
            }

            let text = nonEmptyString(from: choice["text"])
            if !text.isEmpty {
                return text
            }
        }

        return nil
    }

    private func extractOpenAIContentText(from value: Any?) -> String {
        let direct = nonEmptyString(from: value)
        if !direct.isEmpty {
            return direct
        }

        if let parts = value as? [[String: Any]] {
            var pieces: [String] = []
            for part in parts {
                let text = nonEmptyString(from: part["text"])
                if !text.isEmpty {
                    pieces.append(text)
                    continue
                }
                let nested = nonEmptyString(from: part["content"])
                if !nested.isEmpty {
                    pieces.append(nested)
                }
            }
            return pieces.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let part = value as? [String: Any] {
            let text = nonEmptyString(from: part["text"])
            if !text.isEmpty {
                return text
            }
            let nested = nonEmptyString(from: part["content"])
            if !nested.isEmpty {
                return nested
            }
        }

        return ""
    }

    private func parseJSONStringObject(from raw: String) -> [String: Any]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = parseJSONObject(from: trimmed) {
            return direct
        }

        let deFenced = stripCodeFence(from: trimmed)
        if let parsed = parseJSONObject(from: deFenced) {
            return parsed
        }

        guard let start = deFenced.firstIndex(of: "{"),
              let end = deFenced.lastIndex(of: "}") else {
            return nil
        }

        let candidate = String(deFenced[start...end])
        return parseJSONObject(from: candidate)
    }

    private func parseJSONObject(from text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = object as? [String: Any] else {
            return nil
        }
        return dict
    }

    private func stripCodeFence(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }

        var lines = trimmed.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return trimmed }
        lines.removeFirst()
        if let last = lines.last, last.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") {
            lines.removeLast()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func nonEmptyString(from value: Any?) -> String {
        guard let text = value as? String else {
            return ""
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func firstNonEmptyString(from dict: [String: Any], keys: [String]) -> String {
        for key in keys {
            let value = nonEmptyString(from: dict[key])
            if !value.isEmpty {
                return value
            }
        }
        return ""
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
    case timeout
    case cancelled
    case network(message: String)
}
