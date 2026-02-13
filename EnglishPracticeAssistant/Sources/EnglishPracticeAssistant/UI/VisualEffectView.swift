import SwiftUI

enum GlassSurfaceKind: Equatable {
    case floatingBar
    case toast
    case resultPanel
}

/// Legacy material wrapper kept for compatibility while migrating to GlassSurfaceView.
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct GlassSurfaceView: NSViewRepresentable {
    let kind: GlassSurfaceKind
    let cornerRadius: CGFloat

    init(kind: GlassSurfaceKind, cornerRadius: CGFloat) {
        self.kind = kind
        self.cornerRadius = cornerRadius
    }

    func makeNSView(context: Context) -> RuntimeGlassSurfaceView {
        let view = RuntimeGlassSurfaceView()
        view.configure(kind: kind, cornerRadius: cornerRadius)
        return view
    }

    func updateNSView(_ nsView: RuntimeGlassSurfaceView, context: Context) {
        nsView.configure(kind: kind, cornerRadius: cornerRadius)
    }
}

private enum GlassCapability {
    static var shouldUseGlass: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 && runtimeGlassViewType != nil
    }

    private static let classNameCandidates = [
        "NSGlassEffectView",
        "AppKit.NSGlassEffectView",
        "NSLiquidGlassView",
        "AppKit.NSLiquidGlassView"
    ]

    static var runtimeGlassViewType: NSView.Type? {
        for className in classNameCandidates {
            if let cls = NSClassFromString(className) as? NSView.Type {
                return cls
            }
        }
        return nil
    }
}

final class RuntimeGlassSurfaceView: NSView {
    private var activeSurfaceView: NSView?
    private var lastKind: GlassSurfaceKind?
    private var usingGlass = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.masksToBounds = true
    }

    func configure(kind: GlassSurfaceKind, cornerRadius: CGFloat) {
        layer?.cornerRadius = cornerRadius

        let shouldUseGlass = GlassCapability.shouldUseGlass
        let needsRebuild = activeSurfaceView == nil || lastKind != kind || usingGlass != shouldUseGlass
        if needsRebuild {
            rebuildSurface(kind: kind, useGlass: shouldUseGlass)
        }
    }

    override func layout() {
        super.layout()
        activeSurfaceView?.frame = bounds
    }

    private func rebuildSurface(kind: GlassSurfaceKind, useGlass: Bool) {
        activeSurfaceView?.removeFromSuperview()

        let surface: NSView
        if useGlass, let glass = makeRuntimeGlassSurface() {
            surface = glass
            usingGlass = true
        } else {
            surface = makeFallbackSurface(kind: kind)
            usingGlass = false
        }

        surface.frame = bounds
        surface.autoresizingMask = [.width, .height]
        addSubview(surface)
        activeSurfaceView = surface
        lastKind = kind
    }

    private func makeRuntimeGlassSurface() -> NSView? {
        guard let type = GlassCapability.runtimeGlassViewType else {
            return nil
        }
        let view = type.init(frame: bounds)
        if view.responds(to: NSSelectorFromString("setState:")) {
            view.setValue(1, forKey: "state")
        }
        if view.responds(to: NSSelectorFromString("setEmphasized:")) {
            view.setValue(true, forKey: "emphasized")
        }
        return view
    }

    private func makeFallbackSurface(kind: GlassSurfaceKind) -> NSVisualEffectView {
        let view = NSVisualEffectView(frame: bounds)
        view.state = .active
        view.blendingMode = .withinWindow
        switch kind {
        case .floatingBar, .toast:
            view.material = .hudWindow
        case .resultPanel:
            view.material = .popover
        }
        return view
    }
}
