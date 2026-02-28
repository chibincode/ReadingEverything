# English Practice Assistant (macOS)

Menu-bar app that reads selected text, provides Grammar Check suggestions, translates selected text, and supports optional AI TTS.

## Open in Xcode
1. Open `EnglishPracticeAssistant/Package.swift` in Xcode.
2. Select the `EnglishPracticeAssistant` target.
3. Add usage descriptions to the target Info settings:
   - `NSAccessibilityUsageDescription`: "Needs Accessibility access to read selected text in other apps."
   - `NSInputMonitoringUsageDescription`: "Needs Input Monitoring to listen for hotkeys."
4. Run the app.

## Create a .app bundle for permissions
Because this is a Swift Package executable target, Xcode does not generate a `.app` by default. To create a macOS app bundle for Accessibility/Input Monitoring permissions:

```bash
./scripts/package_app.sh
```

Then use the generated app at:

```text
EnglishPracticeAssistant/dist/EnglishPracticeAssistant.app
```

Grant permissions to that `.app`, and launch it with:

```bash
open ./dist/EnglishPracticeAssistant.app
```

## Permissions
- Accessibility: System Settings -> Privacy & Security -> Accessibility
- Input Monitoring: System Settings -> Privacy & Security -> Input Monitoring

## Grammar Provider (Grammar Check only)
Grammar Check uses its own provider settings and is independent from TTS provider settings.
For new installs, the default grammar/translation provider preset is `GLM Direct`.
- GLM Direct / Gemini Direct model field supports preset dropdown + custom model input.
- Grammar provider API keys are stored per provider (`GLM` / `Gemini` / `Custom`) and auto-restored when switching.
- API key fields support `Show` / `Hide` for manual verification.

### Option A: GLM Direct (default for new installs)
- Model example: `glm-4-flash-250414`
- API key: GLM API key
- Endpoint used by app:

```text
https://open.bigmodel.cn/api/paas/v4/chat/completions
```

The app uses Chat Completions in JSON mode and expects:

```json
{
  "clean_up": "...",
  "better_flow": "...",
  "concise": "...",
  "notes": "..."
}
```

For model-unavailable errors, app tries fallback models in order:
`[configured model, glm-4-flash-250414, glm-4.5-flash, glm-5-air]`.

### Option B: Gemini Direct
- Model example: `gemini-3-flash-preview`
- API key: Gemini API key
- Endpoint used by app:

```text
https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent
```

The app prompts Gemini to return JSON with:

```json
{
  "clean_up": "...",
  "better_flow": "...",
  "concise": "...",
  "notes": "..."
}
```

### Option C: Custom Backend
Primary request body (POST to your `baseURL`):

```json
{
  "task": "grammar_check",
  "text": "...",
  "model": "...",
  "variants": ["clean_up", "better_flow", "concise"]
}
```

Preferred response:

```json
{
  "clean_up": "...",
  "better_flow": "...",
  "concise": "...",
  "notes": "..."
}
```

If your backend returns compatible HTTP errors (400/404/422), app retries once using legacy task:

```json
{
  "task": "grammar_rephrase",
  "text": "...",
  "model": "..."
}
```

Legacy response is still accepted:

```json
{
  "corrected": "...",
  "rephrased": "...",
  "notes": "..."
}
```

## Translation (single-shot)
- Translation is single-shot in V1 (no follow-up chat loop).
- Direction is fixed to `Auto Detect -> 中文(简体)` (`target_language = zh-CN`).
- Translation uses the same provider configuration as Grammar Check (`GLM Direct` / `Gemini Direct` / `Custom Backend`).

GLM Direct and Gemini Direct ask for JSON:

```json
{
  "translation": "...",
  "detected_source_language": "...",
  "notes": "..."
}
```

Custom backend primary request:

```json
{
  "task": "translate",
  "text": "...",
  "model": "...",
  "source_language": "auto",
  "target_language": "zh-CN"
}
```

If backend returns compatible HTTP errors (`400/404/422`), app retries once with:

```json
{
  "task": "translation",
  "text": "...",
  "model": "...",
  "source_language": "auto",
  "target_language": "zh-CN"
}
```

## TTS Provider (optional)
Request body (POST to `baseURL`):

```json
{
  "task": "tts",
  "text": "...",
  "voice": "...",
  "model": "..."
}
```

Response: raw audio bytes (mp3/wav).

## Defaults
- Read selection: Ctrl + S
- Translate: Ctrl + R
- Grammar Check: Ctrl + F

## Hotkey behavior
- Matched app hotkeys are intercepted and are not passed through to the target app.
