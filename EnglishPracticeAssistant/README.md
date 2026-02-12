# English Practice Assistant (macOS)

Menu-bar app that reads selected text and provides grammar + rephrase via a bring-your-own AI provider.

## Open in Xcode
1. Open `EnglishPracticeAssistant/Package.swift` in Xcode.
2. Select the `EnglishPracticeAssistant` target.
3. Add usage descriptions to the target Info settings:
   - `NSAccessibilityUsageDescription`: "Needs Accessibility access to read selected text in other apps."
   - `NSInputMonitoringUsageDescription`: "Needs Input Monitoring to listen for hotkeys."
4. Run the app.

## Create a .app bundle for permissions
Because this is a Swift Package executable target, Xcode does not generate a .app by default. To create a macOS app bundle for Accessibility/Input Monitoring permissions:\n\n```bash\n./scripts/package_app.sh\n```\n\nThen use the generated app at:\n```\nEnglishPracticeAssistant/dist/EnglishPracticeAssistant.app\n```\n\nGrant permissions to that `.app`, and launch it with:\n```bash\nopen ./dist/EnglishPracticeAssistant.app\n```\n+
## Permissions
- Accessibility: System Settings -> Privacy & Security -> Accessibility
- Input Monitoring: System Settings -> Privacy & Security -> Input Monitoring

## AI Provider API (Bring your own)
### Grammar + Rephrase
Request body (POST to `baseURL`):
```
{
  "task": "grammar_rephrase",
  "text": "...",
  "model": "..."
}
```
Response (JSON):
```
{ "corrected": "...", "rephrased": "...", "notes": "..." }
```

### AI TTS (optional)
Request body (POST to `baseURL`):
```
{
  "task": "tts",
  "text": "...",
  "voice": "...",
  "model": "..."
}
```
Response: raw audio bytes (mp3/wav).

## Defaults
- Hover read hotkey: Control
- Read selection: Option + R
- Grammar + Rephrase: Option + G
