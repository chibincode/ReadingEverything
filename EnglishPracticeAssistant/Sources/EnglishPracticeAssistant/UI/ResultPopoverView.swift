import AppKit
import SwiftUI

struct ResultPopoverView: View {
    @ObservedObject var appState: AppState
    let onHeaderDragStart: () -> Void
    let onHeaderDragChanged: (CGSize) -> Void
    let onHeaderDragEnd: () -> Void

    @State private var measuredRewriteTextHeight: CGFloat = Layout.grammarBodyMinHeight
    @State private var measuredTranslationTextHeight: CGFloat = Layout.translationBodyMinHeight

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch panelContent {
            case let .grammar(result):
                grammarCard(result)
            case let .translation(result):
                translationCard(result)
            case .none:
                Text("No results")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(GlassSurfaceView(kind: .resultPanel, cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var panelContent: PanelContent? {
        switch appState.activeResultPanel {
        case .grammar:
            if let result = appState.grammarCheckResult {
                return .grammar(result)
            }
            if let result = appState.translationResult {
                return .translation(result)
            }
        case .translation:
            if let result = appState.translationResult {
                return .translation(result)
            }
            if let result = appState.grammarCheckResult {
                return .grammar(result)
            }
        }
        return nil
    }

    @ViewBuilder
    private func grammarCard(_ result: GrammarCheckResult) -> some View {
        let selectedText = selectedText(for: result)
        let renderedDiff = GrammarDiffRenderer.render(source: result.sourceText, rewritten: selectedText)

        draggableHeader(title: "Grammar Check")

        Picker("Rewrite Style", selection: $appState.selectedGrammarOption) {
            ForEach(GrammarOption.allCases, id: \.self) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)

        ScrollView {
            Text(renderedDiff)
                .font(.system(size: Layout.rewriteFontSize, weight: .regular))
                .lineSpacing(Layout.rewriteLineSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: RewriteTextHeightPreferenceKey.self,
                            value: proxy.size.height
                        )
                    }
                )
        }
        .frame(maxWidth: .infinity)
        .frame(height: preferredGrammarBodyHeight)
        .padding(14)
        .background(bodyBackground)
        .overlay(bodyBorder)
        .onPreferenceChange(RewriteTextHeightPreferenceKey.self) { measuredHeight in
            measuredRewriteTextHeight = measuredHeight
        }

        if !result.notes.isEmpty {
            Text(result.notes)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        HStack(spacing: 12) {
            Button {
                appState.readTextAloud(selectedText)
            } label: {
                Label("Read", systemImage: "speaker.wave.2")
            }

            Button {
                copy(selectedText)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            Button {
                appState.retryGrammarCheck(
                    sourceText: result.sourceText,
                    preserveSelectedOption: appState.selectedGrammarOption
                )
            } label: {
                Label(appState.isGrammarChecking ? "Checking..." : "Retry", systemImage: "arrow.clockwise")
            }
            .disabled(appState.isGrammarChecking)

            Spacer()

            Button("Close") {
                appState.dismissResultPanel()
            }
        }
    }

    @ViewBuilder
    private func translationCard(_ result: TranslationResult) -> some View {
        draggableHeader(title: "Translation")

        if !result.sourceText.isEmpty {
            Text(result.sourceText)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
        }

        HStack(spacing: 10) {
            LanguageChip(title: "Auto Detect")
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            LanguageChip(title: "中文(简体)")
        }

        if !result.detectedSourceLanguage.isEmpty {
            Text("Detected source: \(result.detectedSourceLanguage)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        ScrollView {
            Text(result.translatedText)
                .font(.system(size: Layout.translationFontSize, weight: .regular))
                .lineSpacing(Layout.translationLineSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TranslationTextHeightPreferenceKey.self,
                            value: proxy.size.height
                        )
                    }
                )
        }
        .frame(maxWidth: .infinity)
        .frame(height: preferredTranslationBodyHeight)
        .padding(14)
        .background(bodyBackground)
        .overlay(bodyBorder)
        .onPreferenceChange(TranslationTextHeightPreferenceKey.self) { measuredHeight in
            measuredTranslationTextHeight = measuredHeight
        }

        if !result.notes.isEmpty {
            Text(result.notes)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        HStack(spacing: 12) {
            Button {
                appState.readTextAloud(result.translatedText)
            } label: {
                Label("Read", systemImage: "speaker.wave.2")
            }

            Button {
                copy(result.translatedText)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            Button {
                appState.retryTranslation(sourceText: result.sourceText)
            } label: {
                Label(appState.isTranslating ? "Translating..." : "Retry", systemImage: "arrow.clockwise")
            }
            .disabled(appState.isTranslating)

            Spacer()

            Button("Close") {
                appState.dismissResultPanel()
            }
        }
    }

    private func draggableHeader(title: String) -> some View {
        HStack(spacing: 8) {
            PanelDragHandleView()
                .overlay(
                    ResultHeaderDragCaptureView(
                        onDragStart: onHeaderDragStart,
                        onDragChanged: onHeaderDragChanged,
                        onDragEnd: onHeaderDragEnd
                    )
                )

            Text(title)
                .font(.system(size: 16, weight: .semibold))
            Spacer(minLength: 0)
        }
    }

    private var preferredGrammarBodyHeight: CGFloat {
        let targetHeight = measuredRewriteTextHeight + Layout.bodyVerticalPadding
        return min(Layout.grammarBodyMaxHeight, max(Layout.grammarBodyMinHeight, targetHeight))
    }

    private var preferredTranslationBodyHeight: CGFloat {
        let targetHeight = measuredTranslationTextHeight + Layout.bodyVerticalPadding
        return min(Layout.translationBodyMaxHeight, max(Layout.translationBodyMinHeight, targetHeight))
    }

    private var bodyBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primary.opacity(0.04))
    }

    private var bodyBorder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
    }

    private func selectedText(for result: GrammarCheckResult) -> String {
        result.text(for: appState.selectedGrammarOption)
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

private enum PanelContent {
    case grammar(GrammarCheckResult)
    case translation(TranslationResult)
}

private enum Layout {
    static let rewriteFontSize: CGFloat = 14
    static let rewriteLineSpacing: CGFloat = 2
    static let grammarBodyMinHeight: CGFloat = 120
    static let grammarBodyMaxHeight: CGFloat = 300

    static let translationFontSize: CGFloat = 16
    static let translationLineSpacing: CGFloat = 3
    static let translationBodyMinHeight: CGFloat = 140
    static let translationBodyMaxHeight: CGFloat = 340

    static let bodyVerticalPadding: CGFloat = 20
}

private struct RewriteTextHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = Layout.grammarBodyMinHeight

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct TranslationTextHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = Layout.translationBodyMinHeight

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct LanguageChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
    }
}

private struct ResultHeaderDragCaptureView: NSViewRepresentable {
    let onDragStart: () -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnd: () -> Void

    func makeNSView(context: Context) -> ResultHeaderDragCaptureNSView {
        let view = ResultHeaderDragCaptureNSView()
        view.onDragStart = onDragStart
        view.onDragChanged = onDragChanged
        view.onDragEnd = onDragEnd
        view.toolTip = "Drag"
        return view
    }

    func updateNSView(_ nsView: ResultHeaderDragCaptureNSView, context: Context) {
        nsView.onDragStart = onDragStart
        nsView.onDragChanged = onDragChanged
        nsView.onDragEnd = onDragEnd
        nsView.toolTip = "Drag"
    }
}

private final class ResultHeaderDragCaptureNSView: NSView {
    var onDragStart: (() -> Void)?
    var onDragChanged: ((CGSize) -> Void)?
    var onDragEnd: (() -> Void)?

    private var dragStartMouseLocation: CGPoint?
    private var isDragging = false

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        dragStartMouseLocation = NSEvent.mouseLocation
        if !isDragging {
            isDragging = true
            onDragStart?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let dragStartMouseLocation else { return }
        let current = NSEvent.mouseLocation
        let translation = CGSize(
            width: current.x - dragStartMouseLocation.x,
            height: current.y - dragStartMouseLocation.y
        )
        onDragChanged?(translation)
    }

    override func mouseUp(with event: NSEvent) {
        finishDragging()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            finishDragging()
        }
    }

    private func finishDragging() {
        guard isDragging else { return }
        isDragging = false
        dragStartMouseLocation = nil
        onDragEnd?()
    }
}
