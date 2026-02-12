import SwiftUI

@main
struct EnglishPracticeAssistantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(settings: SettingsStore.shared)
                .frame(minWidth: 520, minHeight: 520)
        }
    }
}
