import Foundation

enum DigestExplainQuality {
    enum Verdict: Equatable {
        case ok
        case empty
        case tooShort
        case unrelated
    }

    static let minCharacters = 6
    static let retryPrompt = "这句没答好"
    static let retryButtonTitle = "再试一次"

    static func verdict(selected: String, explanation: String) -> Verdict {
        let answer = explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        if answer.isEmpty { return .empty }
        if answer.count < minCharacters { return .tooShort }
        if !isRelated(selected: selected, explanation: answer) { return .unrelated }
        return .ok
    }

    static func isRelated(selected: String, explanation: String) -> Bool {
        let needle = selected.trimmingCharacters(in: .whitespacesAndNewlines)
        if needle.isEmpty { return true }
        if explanation.localizedCaseInsensitiveContains(needle) { return true }
        let selectedParts = tokens(in: needle)
        let explanationParts = Set(tokens(in: explanation).map { $0.lowercased() })
        if selectedParts.isEmpty { return true }
        return selectedParts.contains { explanationParts.contains($0.lowercased()) }
    }

    static func tokens(in text: String) -> [String] {
        var latin: [String] = []
        var current = ""
        for character in text {
            if character.isASCII && (character.isLetter || character.isNumber) {
                current.append(character)
            } else {
                if current.count >= 2 { latin.append(current) }
                current = ""
            }
        }
        if current.count >= 2 { latin.append(current) }

        let scalars = Array(text)
        var grams: [String] = []
        if scalars.count >= 2 {
            for index in 0..<(scalars.count - 1) {
                let pair = String(scalars[index...index + 1])
                if pair.unicodeScalars.allSatisfy({ isCJK($0) }) {
                    grams.append(pair)
                }
            }
        }
        return latin + grams
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        let value = Int(scalar.value)
        return (0x4E00...0x9FFF).contains(value) || (0x3400...0x4DBF).contains(value)
    }
}
