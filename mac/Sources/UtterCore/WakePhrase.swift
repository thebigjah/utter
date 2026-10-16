import Foundation

/// Finds the wake phrase in a transcript and pulls out what was said after it.
/// The recognizer hears "Hey Cosmic" a few ways ("Hey, Cosmic", "Hay cosmic"), so matching is loose.
public struct WakePhrase {
    public let phrase: String
    private let regex: NSRegularExpression?

    public init(_ phrase: String) {
        self.phrase = phrase
        var words = phrase.lowercased().split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }
        if words.first == "hey" { words[0] = "(?:hey|hay|hi|hey there)" }
        let pattern = #"\b"# + words.joined(separator: #"[\s,.!?]+"#) + #"\b[\s,.!?:]*"#
        regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    /// The text after the first occurrence of the phrase, or nil if the phrase is absent.
    public func remainder(in text: String) -> String? {
        guard let regex,
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
    }

    public func contains(_ text: String) -> Bool { remainder(in: text) != nil }

    /// "Never mind" or "cancel" as the whole command throws the dictation away.
    public static func isCancel(_ text: String) -> Bool {
        let cleaned = text.lowercased().trimmingCharacters(in: CharacterSet.letters.inverted)
        return ["never mind", "nevermind", "cancel", "cancel that", "stop"].contains(cleaned)
    }
}
