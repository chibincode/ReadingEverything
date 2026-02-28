import Cocoa
import Combine
import SwiftUI

@MainActor
final class ResultPanelController {
    private let panel: FloatingPanel
    private let appState: AppState
    private let hostingView: NSHostingView<ResultPopoverView>
    private var cancellables = Set<AnyCancellable>()
    private var isDraggingPanel = false
    private var dragStartFrame: CGRect?
    private var manualOrigin: CGPoint?
    private var suppressNextOutsideMouseUp = false

    init(appState: AppState) {
        self.appState = appState
        panel = FloatingPanel(contentRect: CGRect(x: 0, y: 0, width: 560, height: 320))
        hostingView = NSHostingView(
            rootView: ResultPopoverView(
                appState: appState,
                onHeaderDragStart: {},
                onHeaderDragChanged: { _ in },
                onHeaderDragEnd: {}
            )
        )
        hostingView.rootView = ResultPopoverView(
            appState: appState,
            onHeaderDragStart: { [weak self] in self?.beginDrag() },
            onHeaderDragChanged: { [weak self] translation in self?.updateDrag(translation: translation) },
            onHeaderDragEnd: { [weak self] in self?.endDrag() }
        )
        panel.contentView = hostingView

        appState.$grammarCheckResult
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.update()
            }
            .store(in: &cancellables)

        appState.$translationResult
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.update()
            }
            .store(in: &cancellables)

        appState.$activeResultPanel
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.update()
            }
            .store(in: &cancellables)

        appState.$selectedGrammarOption
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.appState.activeResultPanel == .grammar, self.appState.grammarCheckResult != nil else {
                    return
                }
                self.resizePanelToFitContent(fixedOrigin: self.manualOrigin)
            }
            .store(in: &cancellables)
    }

    private func update() {
        guard hasContent else {
            panel.orderOut(nil)
            manualOrigin = nil
            isDraggingPanel = false
            dragStartFrame = nil
            return
        }

        if isDraggingPanel {
            panel.orderFront(nil)
            return
        }

        if panel.isVisible {
            let originToPreserve = manualOrigin ?? panel.frame.origin
            resizePanelToFitContent(fixedOrigin: originToPreserve)
            panel.orderFront(nil)
            return
        }

        resizePanelToFitContent(fixedOrigin: nil)

        let rect = appState.selection?.rect
        let targetPoint: CGPoint
        if let rect {
            targetPoint = CGPoint(x: rect.midX, y: rect.maxY + 60)
        } else {
            let mouse = NSEvent.mouseLocation
            targetPoint = CGPoint(x: mouse.x, y: mouse.y + 60)
        }
        let origin = clampedOrigin(for: targetPoint, panelSize: panel.frame.size)
        panel.setFrameOrigin(origin)
        panel.orderFront(nil)
    }

    private var hasContent: Bool {
        appState.grammarCheckResult != nil || appState.translationResult != nil
    }

    private func resizePanelToFitContent(fixedOrigin: CGPoint?) {
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        let width = min(700, max(560, ceil(fittingSize.width)))
        let screenHeight = panel.screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 800
        let maxHeight = max(300, min(560, screenHeight * 0.72))
        let height = min(maxHeight, max(300, ceil(fittingSize.height)))
        var nextFrame = panel.frame
        nextFrame.size = CGSize(width: width, height: height)
        if let fixedOrigin {
            nextFrame.origin = fixedOrigin
        }
        nextFrame = clampedFrame(nextFrame)

        let frameChanged = abs(panel.frame.width - nextFrame.width) > 0.5
            || abs(panel.frame.height - nextFrame.height) > 0.5
            || abs(panel.frame.origin.x - nextFrame.origin.x) > 0.5
            || abs(panel.frame.origin.y - nextFrame.origin.y) > 0.5
        guard frameChanged else {
            return
        }

        panel.setFrame(nextFrame, display: false)
        if fixedOrigin != nil {
            manualOrigin = nextFrame.origin
        }
    }

    private func beginDrag() {
        guard panel.isVisible else { return }
        isDraggingPanel = true
        dragStartFrame = panel.frame
    }

    private func updateDrag(translation: CGSize) {
        guard isDraggingPanel, let dragStartFrame else { return }
        var nextFrame = dragStartFrame
        nextFrame.origin.x += translation.width
        nextFrame.origin.y += translation.height
        nextFrame = clampedFrame(nextFrame)

        panel.setFrame(nextFrame, display: true)
        manualOrigin = nextFrame.origin
    }

    private func endDrag() {
        guard isDraggingPanel else { return }
        isDraggingPanel = false
        dragStartFrame = nil
        manualOrigin = panel.frame.origin
        suppressNextOutsideMouseUp = true
    }

    private func clampedFrame(_ frame: CGRect) -> CGRect {
        guard let screen = screenContaining(point: CGPoint(x: frame.midX, y: frame.midY)) else {
            return frame
        }

        let visible = screen.visibleFrame
        var x = frame.origin.x
        var y = frame.origin.y

        x = max(visible.minX + 8, min(x, visible.maxX - frame.width - 8))
        y = max(visible.minY + 8, min(y, visible.maxY - frame.height - 8))

        return CGRect(x: x, y: y, width: frame.width, height: frame.height)
    }

    private func screenContaining(point: CGPoint) -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
    }

    private func clampedOrigin(for point: CGPoint, panelSize: CGSize) -> CGPoint {
        guard let screen = screenContaining(point: point) else {
            return point
        }
        let frame = screen.visibleFrame
        var x = point.x - panelSize.width / 2
        var y = point.y
        if x < frame.minX { x = frame.minX + 8 }
        if x + panelSize.width > frame.maxX { x = frame.maxX - panelSize.width - 8 }
        if y + panelSize.height > frame.maxY { y = frame.maxY - panelSize.height - 8 }
        if y < frame.minY { y = frame.minY + 8 }
        return CGPoint(x: x, y: y)
    }

    func contains(point: CGPoint, extraPadding: CGFloat = 0) -> Bool {
        guard panel.isVisible else { return false }
        return panel.frame.insetBy(dx: -extraPadding, dy: -extraPadding).contains(point)
    }

    func shouldIgnoreGlobalMouseUp(point: CGPoint, extraPadding: CGFloat = 14) -> Bool {
        if suppressNextOutsideMouseUp {
            suppressNextOutsideMouseUp = false
            return true
        }

        if isDraggingPanel {
            return true
        }

        return contains(point: point, extraPadding: extraPadding)
    }
}
