import Cocoa
import Combine
import SwiftUI

@MainActor
final class ResultPanelController {
    private let panel: FloatingPanel
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
        panel = FloatingPanel(contentRect: CGRect(x: 0, y: 0, width: 420, height: 220))
        let content = ResultPopoverView(appState: appState)
        panel.contentView = NSHostingView(rootView: content)

        appState.$grammarResult
            .receive(on: RunLoop.main)
            .sink { [weak self] result in
                self?.update(for: result)
            }
            .store(in: &cancellables)
    }

    private func update(for result: GrammarResult?) {
        guard result != nil else {
            panel.orderOut(nil)
            return
        }
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

    private func clampedOrigin(for point: CGPoint, panelSize: CGSize) -> CGPoint {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else {
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

    func contains(point: CGPoint) -> Bool {
        guard panel.isVisible else { return false }
        return panel.frame.contains(point)
    }
}
