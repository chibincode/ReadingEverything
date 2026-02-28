import Foundation
import SwiftUI

enum GrammarDiffRenderer {
    static func render(source: String, rewritten: String) -> AttributedString {
        let sourceTokens = tokenize(source)
        let rewrittenTokens = tokenize(rewritten)
        let operations = diffOperations(source: sourceTokens, rewritten: rewrittenTokens)
        let segments = mergeOperations(operations)

        var rendered = AttributedString()
        for segment in segments {
            rendered += attributedSegment(for: segment)
        }
        return rendered
    }

    private static func attributedSegment(for segment: DiffSegment) -> AttributedString {
        var attributed = AttributedString(segment.text)

        switch segment.kind {
        case .unchanged:
            return attributed
        case .inserted:
            attributed.foregroundColor = Color(red: 0.03, green: 0.45, blue: 0.43)
            if !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                attributed.backgroundColor = Color(red: 0.83, green: 0.95, blue: 0.92)
            }
            return attributed
        case .removed:
            attributed.foregroundColor = Color.secondary.opacity(0.6)
            attributed.strikethroughStyle = .single
            return attributed
        }
    }

    private static func diffOperations(source: [Token], rewritten: [Token]) -> [DiffOperation] {
        let sourceCount = source.count
        let rewrittenCount = rewritten.count
        var lcs = Array(
            repeating: Array(repeating: 0, count: rewrittenCount + 1),
            count: sourceCount + 1
        )

        if sourceCount > 0, rewrittenCount > 0 {
            for sourceIndex in stride(from: sourceCount - 1, through: 0, by: -1) {
                for rewrittenIndex in stride(from: rewrittenCount - 1, through: 0, by: -1) {
                    if source[sourceIndex] == rewritten[rewrittenIndex] {
                        lcs[sourceIndex][rewrittenIndex] = lcs[sourceIndex + 1][rewrittenIndex + 1] + 1
                    } else {
                        lcs[sourceIndex][rewrittenIndex] = max(
                            lcs[sourceIndex + 1][rewrittenIndex],
                            lcs[sourceIndex][rewrittenIndex + 1]
                        )
                    }
                }
            }
        }

        var operations: [DiffOperation] = []
        var sourceIndex = 0
        var rewrittenIndex = 0

        while sourceIndex < sourceCount, rewrittenIndex < rewrittenCount {
            if source[sourceIndex] == rewritten[rewrittenIndex] {
                operations.append(.unchanged(source[sourceIndex]))
                sourceIndex += 1
                rewrittenIndex += 1
                continue
            }

            if lcs[sourceIndex + 1][rewrittenIndex] >= lcs[sourceIndex][rewrittenIndex + 1] {
                operations.append(.removed(source[sourceIndex]))
                sourceIndex += 1
            } else {
                operations.append(.inserted(rewritten[rewrittenIndex]))
                rewrittenIndex += 1
            }
        }

        while sourceIndex < sourceCount {
            operations.append(.removed(source[sourceIndex]))
            sourceIndex += 1
        }

        while rewrittenIndex < rewrittenCount {
            operations.append(.inserted(rewritten[rewrittenIndex]))
            rewrittenIndex += 1
        }

        return operations
    }

    private static func mergeOperations(_ operations: [DiffOperation]) -> [DiffSegment] {
        var segments: [DiffSegment] = []
        for operation in operations {
            let segment = DiffSegment(operation: operation)
            if let last = segments.last, last.kind == segment.kind {
                segments[segments.count - 1] = DiffSegment(
                    text: last.text + segment.text,
                    kind: last.kind
                )
            } else {
                segments.append(segment)
            }
        }
        return segments
    }

    private static func tokenize(_ text: String) -> [Token] {
        guard !text.isEmpty else { return [] }

        var tokens: [Token] = []
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if isWhitespace(character) {
                let start = index
                while index < text.endIndex, isWhitespace(text[index]) {
                    index = text.index(after: index)
                }
                tokens.append(Token(text: String(text[start..<index])))
                continue
            }

            if isWordCharacter(character) {
                let start = index
                while index < text.endIndex, isWordCharacter(text[index]) {
                    index = text.index(after: index)
                }
                tokens.append(Token(text: String(text[start..<index])))
                continue
            }

            tokens.append(Token(text: String(character)))
            index = text.index(after: index)
        }

        return tokens
    }

    private static func isWhitespace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            if CharacterSet.alphanumerics.contains(scalar) {
                return true
            }
            return scalar.value == 39 || scalar.value == 95
        }
    }
}

private struct Token: Equatable {
    let text: String
}

private enum DiffOperation {
    case unchanged(Token)
    case inserted(Token)
    case removed(Token)
}

private enum DiffSegmentKind {
    case unchanged
    case inserted
    case removed
}

private struct DiffSegment {
    let text: String
    let kind: DiffSegmentKind

    init(text: String, kind: DiffSegmentKind) {
        self.text = text
        self.kind = kind
    }

    init(operation: DiffOperation) {
        switch operation {
        case let .unchanged(token):
            self.init(text: token.text, kind: .unchanged)
        case let .inserted(token):
            self.init(text: token.text, kind: .inserted)
        case let .removed(token):
            self.init(text: token.text, kind: .removed)
        }
    }
}
