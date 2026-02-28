import Foundation
import CoreGraphics

struct SelectionSnapshot: Equatable {
    let text: String
    let rect: CGRect?
    let appName: String?
}

enum ReadSource: String, Equatable {
    case selection

    var debugLabel: String {
        "selection"
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

enum GrammarOption: String, CaseIterable, Equatable, Hashable {
    case cleanUp
    case betterFlow
    case concise

    var title: String {
        switch self {
        case .cleanUp:
            return "Clean Up"
        case .betterFlow:
            return "Better Flow"
        case .concise:
            return "Concise"
        }
    }
}

struct GrammarCheckResult: Equatable {
    let sourceText: String
    let cleanUp: String
    let betterFlow: String
    let concise: String
    let notes: String
    let usedLegacyFallback: Bool

    func text(for option: GrammarOption) -> String {
        switch option {
        case .cleanUp:
            return cleanUp
        case .betterFlow:
            return betterFlow
        case .concise:
            return concise
        }
    }
}

enum ResultPanelKind: Equatable {
    case grammar
    case translation
}

struct TranslationResult: Equatable {
    let sourceText: String
    let translatedText: String
    let detectedSourceLanguage: String
    let targetLanguage: String
    let notes: String
    let usedLegacyFallback: Bool
}
