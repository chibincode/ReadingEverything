import Cocoa
import Combine
import SwiftUI

@MainActor
final class FloatingBarController {
    private let panel: FloatingPanel
    private let appState: AppState
    private let hostingView: NSHostingView<FloatingBarView>
    private var cancellables = Set<AnyCancellable>()
    private var lastAnchorRect: CGRect?
    private var lastIsReading = false
    private var placement: FloatingBarPlacement = .trackingSelection
    private var lastSelectionSignature: String?
    private var pendingUnlockAfterRead = false
    private var stableSelectionOrigin: CGPoint?
    private var isDraggingBar = false
    private var dragStartFrame: CGRect?
    private var manualOrigin: CGPoint?
    private var manualOriginSelectionSignature: String?
    private var suppressNextOutsideMouseUp = false

    init(appState: AppState) {
        self.appState = appState
        panel = FloatingPanel(contentRect: CGRect(x: 0, y: 0, width: 380, height: 46))
        hostingView = NSHostingView(
            rootView: FloatingBarView(
                appState: appState,
                onDragStart: {},
                onDragChanged: { _ in },
                onDragEnd: {}
            )
        )
        hostingView.rootView = FloatingBarView(
            appState: appState,
            onDragStart: { [weak self] in self?.beginDrag() },
            onDragChanged: { [weak self] translation in self?.updateDrag(translation: translation) },
            onDragEnd: { [weak self] in self?.endDrag() }
        )
        panel.contentView = hostingView

        Publishers.CombineLatest4(
            appState.$selection,
            appState.$isReading,
            appState.$readingAnchorRect,
            appState.$selectionCommitPoint
        )
            .receive(on: RunLoop.main)
            .sink { [weak self] selection, isReading, readingAnchorRect, selectionCommitPoint in
                self?.update(
                    selection: selection,
                    isReading: isReading,
                    readingAnchorRect: readingAnchorRect,
                    selectionCommitPoint: selectionCommitPoint
                )
            }
            .store(in: &cancellables)
    }

    private func update(
        selection: SelectionSnapshot?,
        isReading: Bool,
        readingAnchorRect: CGRect?,
        selectionCommitPoint: CGPoint?
    ) {
        syncManualPlacement(for: selection)

        let transitionedIntoReading = isReading && !lastIsReading
        let transitionedOutOfReading = !isReading && lastIsReading
        lastIsReading = isReading

        if isDraggingBar {
            panel.orderFront(nil)
            publishDebug(
                expectedOrigin: panel.frame.origin,
                anchorKind: "manual-dragging",
                selectionRect: readingAnchorRect ?? selection?.rect
            )
            return
        }

        if transitionedIntoReading {
            lockPlacementForReading(selection: selection, readingAnchorRect: readingAnchorRect)
        }

        if isReading {
            if case .lockedReading(let frame) = placement {
                panel.setFrame(frame, display: false)
                panel.orderFront(nil)
                publishDebug(expectedOrigin: frame.origin, anchorKind: "locked", selectionRect: readingAnchorRect ?? selection?.rect)
                return
            }

            lockPlacementForReading(selection: selection, readingAnchorRect: readingAnchorRect)
            if case .lockedReading(let frame) = placement {
                panel.setFrame(frame, display: false)
                panel.orderFront(nil)
                publishDebug(expectedOrigin: frame.origin, anchorKind: "locked", selectionRect: readingAnchorRect ?? selection?.rect)
            }
            return
        }

        if transitionedOutOfReading {
            if case .lockedReading(let frame) = placement {
                resizePanelToContent(keepCenter: false, animated: false, fixedOrigin: frame.origin)
                let stabilizedFrame = panel.frame
                panel.setFrame(stabilizedFrame, display: false)
                stableSelectionOrigin = stabilizedFrame.origin
                panel.orderFront(nil)
                publishDebug(expectedOrigin: stabilizedFrame.origin, anchorKind: "post-reading", selectionRect: selection?.rect)
            }
            placement = .trackingSelection
            pendingUnlockAfterRead = true
        }

        placement = .trackingSelection
        if let selection {
            let signature = selectionSignature(for: selection)

            if let manualOrigin, manualOriginSelectionSignature == signature {
                lastSelectionSignature = signature
                pendingUnlockAfterRead = false
                resizePanelToContent(keepCenter: false, animated: false, fixedOrigin: manualOrigin)
                panel.orderFront(nil)
                stableSelectionOrigin = panel.frame.origin
                publishDebug(
                    expectedOrigin: panel.frame.origin,
                    anchorKind: "manual-drag",
                    selectionRect: selection.rect
                )
                return
            }

            let shouldKeepCurrentPlacement = panel.isVisible && (signature == lastSelectionSignature || pendingUnlockAfterRead)
            lastSelectionSignature = signature

            if shouldKeepCurrentPlacement {
                pendingUnlockAfterRead = false
                if let stableSelectionOrigin, panel.frame.origin != stableSelectionOrigin {
                    panel.setFrameOrigin(stableSelectionOrigin)
                }
                panel.orderFront(nil)
                publishDebug(
                    expectedOrigin: stableSelectionOrigin ?? panel.frame.origin,
                    anchorKind: "selection-locked",
                    selectionRect: selection.rect
                )
                return
            }

            resizePanelToContent(keepCenter: false, animated: false)
            pendingUnlockAfterRead = false

            if let rect = selection.rect {
                lastAnchorRect = rect
            }

            if !panel.isVisible, let selectionCommitPoint {
                showPanelAtPoint(selectionCommitPoint, selectionRect: selection.rect)
                stableSelectionOrigin = panel.frame.origin
                appState.selectionCommitPoint = nil
            } else if let rect = selection.rect {
                showPanelAtSelectionRect(rect)
                stableSelectionOrigin = panel.frame.origin
            } else if panel.isVisible {
                panel.orderFront(nil)
                publishDebug(
                    expectedOrigin: stableSelectionOrigin ?? panel.frame.origin,
                    anchorKind: "selection-visible-no-rect",
                    selectionRect: nil
                )
            } else {
                clearDebug()
                panel.orderOut(nil)
            }
            return
        }

        lastAnchorRect = nil
        lastSelectionSignature = nil
        pendingUnlockAfterRead = false
        stableSelectionOrigin = nil
        clearDebug()
        panel.orderOut(nil)
    }

    private func lockPlacementForReading(selection: SelectionSnapshot?, readingAnchorRect: CGRect?) {
        let anchor = readingAnchorRect ?? selection?.rect ?? lastAnchorRect
        lastAnchorRect = anchor ?? lastAnchorRect
        let currentSelectionSignature: String? = {
            guard let selection else { return nil }
            return selectionSignature(for: selection)
        }()
        let manualOriginForSelection: CGPoint? = {
            guard let currentSelectionSignature else { return nil }
            guard manualOriginSelectionSignature == currentSelectionSignature else { return nil }
            return manualOrigin
        }()

        if !panel.isVisible {
            if let manualOriginForSelection {
                let startFrame = clampedFrame(CGRect(origin: manualOriginForSelection, size: panel.frame.size))
                panel.setFrame(startFrame, display: false)
                panel.orderFront(nil)
            } else {
                showPanelAtSelectionRect(anchor)
            }
        }

        guard panel.isVisible else { return }

        let stableOrigin = manualOriginForSelection ?? stableSelectionOrigin ?? panel.frame.origin
        resizePanelToContent(keepCenter: false, animated: false, fixedOrigin: stableOrigin)
        let lockedFrame = CGRect(origin: stableOrigin, size: panel.frame.size)
        stableSelectionOrigin = stableOrigin
        placement = .lockedReading(frame: lockedFrame)
        panel.setFrame(lockedFrame, display: false)
        panel.orderFront(nil)
        publishDebug(expectedOrigin: lockedFrame.origin, anchorKind: "locked", selectionRect: anchor)
    }

    private func showPanelAtSelectionRect(_ rect: CGRect?) {
        guard let rect else {
            clearDebug()
            panel.orderOut(nil)
            return
        }

        let targetPoint = CGPoint(x: rect.midX, y: rect.maxY + 8)
        let origin = clampedOrigin(for: targetPoint, panelSize: panel.frame.size)
        panel.setFrameOrigin(origin)
        panel.orderFront(nil)
        publishDebug(expectedOrigin: origin, anchorKind: "selection-rect", selectionRect: rect)
    }

    private func showPanelAtPoint(_ point: CGPoint, selectionRect: CGRect?) {
        let targetPoint = CGPoint(x: point.x, y: point.y + 14)
        let origin = clampedOrigin(for: targetPoint, panelSize: panel.frame.size)
        panel.setFrameOrigin(origin)
        panel.orderFront(nil)
        publishDebug(expectedOrigin: origin, anchorKind: "mouse-commit", selectionRect: selectionRect)
    }

    private func resizePanelToContent(keepCenter: Bool, animated: Bool, fixedOrigin: CGPoint? = nil) {
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        let newSize = CGSize(
            width: max(220, ceil(fittingSize.width)),
            height: max(42, ceil(fittingSize.height))
        )

        guard abs(panel.frame.width - newSize.width) > 0.5 || abs(panel.frame.height - newSize.height) > 0.5 else {
            return
        }

        var nextFrame = panel.frame

        if let fixedOrigin {
            nextFrame.origin = fixedOrigin
            nextFrame.size = newSize
        } else if keepCenter {
            let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
            nextFrame = CGRect(
                x: center.x - (newSize.width / 2),
                y: center.y - (newSize.height / 2),
                width: newSize.width,
                height: newSize.height
            )
        } else {
            nextFrame.size = newSize
        }

        if fixedOrigin == nil {
            nextFrame = clampedFrame(nextFrame)
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().setFrame(nextFrame, display: false)
            }
        } else {
            panel.setFrame(nextFrame, display: false)
        }
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

        if isDraggingBar {
            return true
        }

        return contains(point: point, extraPadding: extraPadding)
    }

    private func beginDrag() {
        guard panel.isVisible else { return }
        isDraggingBar = true
        dragStartFrame = panel.frame
    }

    private func updateDrag(translation: CGSize) {
        guard isDraggingBar, let dragStartFrame else { return }
        var nextFrame = dragStartFrame
        nextFrame.origin.x += translation.width
        nextFrame.origin.y -= translation.height
        nextFrame = clampedFrame(nextFrame)
        panel.setFrame(nextFrame, display: true)
        stableSelectionOrigin = nextFrame.origin
        if case .lockedReading = placement {
            placement = .lockedReading(frame: nextFrame)
        }
        publishDebug(
            expectedOrigin: nextFrame.origin,
            anchorKind: "manual-dragging",
            selectionRect: appState.selection?.rect ?? appState.readingAnchorRect
        )
    }

    private func endDrag() {
        guard isDraggingBar else { return }
        isDraggingBar = false
        dragStartFrame = nil
        manualOrigin = panel.frame.origin
        if let selection = appState.selection {
            manualOriginSelectionSignature = selectionSignature(for: selection)
        } else {
            manualOriginSelectionSignature = nil
        }
        suppressNextOutsideMouseUp = true
        stableSelectionOrigin = panel.frame.origin
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

    private func publishDebug(expectedOrigin: CGPoint, anchorKind: String, selectionRect: CGRect?) {
        appState.floatingBarDebug = FloatingBarDebugInfo(
            expectedOrigin: expectedOrigin,
            actualFrame: panel.frame,
            anchorKind: anchorKind,
            selectionRect: selectionRect
        )
    }

    private func clearDebug() {
        appState.floatingBarDebug = nil
    }

    private func selectionSignature(for snapshot: SelectionSnapshot) -> String {
        let text = snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Rect often refines in a follow-up AX tick; keep signature text-based to prevent a second jump.
        return "\(snapshot.appName ?? "unknown")|\(text)"
    }

    private func syncManualPlacement(for selection: SelectionSnapshot?) {
        guard let selection else {
            clearManualPlacement()
            return
        }

        guard let manualSignature = manualOriginSelectionSignature else {
            return
        }

        let currentSignature = selectionSignature(for: selection)
        if manualSignature != currentSignature {
            clearManualPlacement()
        }
    }

    private func clearManualPlacement() {
        manualOrigin = nil
        manualOriginSelectionSignature = nil
    }
}

private enum FloatingBarPlacement {
    case trackingSelection
    case lockedReading(frame: CGRect)
}

final class FloatingPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
