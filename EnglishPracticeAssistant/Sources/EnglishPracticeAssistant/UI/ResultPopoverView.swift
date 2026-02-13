import SwiftUI

struct ResultPopoverView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let result = appState.grammarResult {
                ResultSection(title: "Corrected", text: result.corrected)
                ResultSection(title: "Rephrased", text: result.rephrased)
                if !result.notes.isEmpty {
                    ResultSection(title: "Notes", text: result.notes)
                }
                HStack {
                    Button("Copy Corrected") {
                        copy(result.corrected)
                    }
                    Button("Copy Rephrased") {
                        copy(result.rephrased)
                    }
                    Spacer()
                    Button("Close") {
                        appState.grammarResult = nil
                    }
                }
            } else {
                Text("No results")
            }
        }
        .padding(16)
        .background(GlassSurfaceView(kind: .resultPanel, cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

private struct ResultSection: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 13))
                .textSelection(.enabled)
        }
    }
}
