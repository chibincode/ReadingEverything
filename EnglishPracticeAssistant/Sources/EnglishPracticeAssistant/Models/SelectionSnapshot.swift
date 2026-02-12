import Foundation
import CoreGraphics

struct SelectionSnapshot: Equatable {
    let text: String
    let rect: CGRect?
    let appName: String?
}

enum ReadSource: String, Equatable {
    case selection
    case hoverRange
    case hoverFallback

    var debugLabel: String {
        switch self {
        case .selection:
            return "selection"
        case .hoverRange:
            return "hover-range"
        case .hoverFallback:
            return "hover-fallback"
        }
    }
}

struct ReadTarget: Equatable {
    let text: String
    let rect: CGRect?
    let source: ReadSource
    let appName: String?
}

struct DetectionPreview: Equatable {
    let rect: CGRect?
    let source: ReadSource
}

struct FloatingBarDebugInfo: Equatable {
    let expectedOrigin: CGPoint
    let actualFrame: CGRect
    let anchorKind: String
    let selectionRect: CGRect?

    var deltaX: CGFloat { actualFrame.origin.x - expectedOrigin.x }
    var deltaY: CGFloat { actualFrame.origin.y - expectedOrigin.y }
}

struct GrammarResult: Equatable {
    let corrected: String
    let rephrased: String
    let notes: String
}
