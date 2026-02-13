import Cocoa
import Combine
import SwiftUI

@MainActor
final class ToastController {
    private let panel: FloatingPanel
    private let appState: AppState
    private var dismissWorkItem: DispatchWorkItem?

    init(appState: AppState) {
        self.appState = appState
        panel = FloatingPanel(contentRect: CGRect(x: 0, y: 0, width: 220, height: 40))
        let content = ToastView(message: "")
        panel.contentView = NSHostingView(rootView: content)

        appState.showToast = { [weak self] message in
            self?.show(message: message)
        }
    }

    private func show(message: String) {
        panel.contentView = NSHostingView(rootView: ToastView(message: message))
        let mouse = NSEvent.mouseLocation
        let origin = CGPoint(x: mouse.x - panel.frame.width / 2, y: mouse.y + 16)
        panel.setFrameOrigin(origin)
        panel.orderFront(nil)

        dismissWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.panel.orderOut(nil)
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }
}

private struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(GlassSurfaceView(kind: .toast, cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
