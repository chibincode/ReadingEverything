import Cocoa
import Combine
import SwiftUI

@MainActor
final class DetectionOverlayController {
    private let detectionPanel: DetectionOverlayPanel
    private let metricsPanel: DetectionMetricsPanel
    private let settings = SettingsStore.shared
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        detectionPanel = DetectionOverlayPanel(contentRect: CGRect(x: 0, y: 0, width: 1, height: 1))
        metricsPanel = DetectionMetricsPanel(contentRect: CGRect(x: 0, y: 0, width: 1, height: 1))

        appState.$detectionPreview
            .receive(on: RunLoop.main)
            .sink { [weak self] preview in
                self?.updateDetection(preview)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(appState.$floatingBarDebug, settings.$showFloatingBarOffsetDebug)
            .receive(on: RunLoop.main)
            .sink { [weak self] debug, showDebug in
                self?.updateMetrics(debug: debug, enabled: showDebug)
            }
            .store(in: &cancellables)
    }

    private func updateDetection(_ preview: DetectionPreview?) {
        guard let preview,
              let rect = preview.rect,
              rect.width >= 2,
              rect.height >= 2 else {
            detectionPanel.orderOut(nil)
            return
        }

        let paddedRect = rect.insetBy(dx: -2, dy: -2)
        detectionPanel.setFrame(paddedRect, display: true)
        detectionPanel.contentView = NSHostingView(rootView: DetectionOverlayView(sourceLabel: preview.source.debugLabel))
        detectionPanel.orderFront(nil)
    }

    private func updateMetrics(debug: FloatingBarDebugInfo?, enabled: Bool) {
        guard enabled, let debug else {
            metricsPanel.orderOut(nil)
            return
        }

        let view = DetectionMetricsView(debug: debug)
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        let fit = host.fittingSize
        let width = max(220, ceil(fit.width))
        let height = max(70, ceil(fit.height))
        let anchor = CGPoint(x: debug.actualFrame.midX, y: debug.actualFrame.maxY + 8)
        let origin = clampedOrigin(around: anchor, panelSize: CGSize(width: width, height: height))
        metricsPanel.setFrame(CGRect(origin: origin, size: CGSize(width: width, height: height)), display: true)
        metricsPanel.contentView = host
        metricsPanel.orderFront(nil)
    }

    private func clampedOrigin(around point: CGPoint, panelSize: CGSize) -> CGPoint {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else {
            return point
        }
        let frame = screen.visibleFrame
        var x = point.x - panelSize.width / 2
        var y = point.y
        x = max(frame.minX + 8, min(x, frame.maxX - panelSize.width - 8))
        y = max(frame.minY + 8, min(y, frame.maxY - panelSize.height - 8))
        return CGPoint(x: x, y: y)
    }
}

private struct DetectionOverlayView: View {
    let sourceLabel: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.blue, lineWidth: 2)

            Text(sourceLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.blue.opacity(0.9))
                .clipShape(Capsule())
                .padding(4)
        }
        .background(Color.clear)
    }
}

private final class DetectionOverlayPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        level = .statusBar
        isOpaque = false
        hasShadow = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct DetectionMetricsView: View {
    let debug: FloatingBarDebugInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Floating Bar Debug")
                .font(.system(size: 11, weight: .semibold))
            Text("anchor: \(debug.anchorKind)")
            Text("expected: (\(format(debug.expectedOrigin.x)), \(format(debug.expectedOrigin.y)))")
            Text("actual: (\(format(debug.actualFrame.origin.x)), \(format(debug.actualFrame.origin.y)))")
            Text("offset: dx \(format(debug.deltaX))  dy \(format(debug.deltaY))")
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.black.opacity(0.75))
        )
    }

    private func format(_ value: CGFloat) -> String {
        String(Int(value.rounded()))
    }
}

private final class DetectionMetricsPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        level = .statusBar
        isOpaque = false
        hasShadow = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
