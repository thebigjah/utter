import Foundation

/// User-editable word list, find/replace pairs and spoken shortcuts.
/// Mirrors Wispr Flow's dictionary, replacements and snippets.
public struct Vocabulary: Codable, Equatable {
    public var words: [String]
    public var replacements: [String: String]
    public var snippets: [String: String]

    public init(words: [String] = [], replacements: [String: String] = [:], snippets: [String: String] = [:]) {
        self.words = words
        self.replacements = replacements
        self.snippets = snippets
    }

    public static let starter = Vocabulary(
        words: ["Utter"],
        replacements: [:],
        snippets: [:]
    )
}

/// Turns a raw transcript into text ready to insert at the cursor.
public enum Formatter {
    static let fillers = #"\b(?:u+m+|u+h+|uhm|erm|e+r+|a+h+|h+m+|m{2,})\b[,.]?"#

    public static func format(_ raw: String, vocabulary: Vocabulary = .init(), before: String? = nil) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        text = replace(fillers, in: text, with: "")
        text = replace(#"\b(\w+)(?:[,]?\s+\1\b)+"#, in: text, with: "$1")
        text = replace(#",?\s*\bnew paragraph\b[,.]?\s*"#, in: text, with: "\n\n")
        text = replace(#",?\s*\bnew line\b[,.]?\s*"#, in: text, with: "\n")

        for (trigger, expansion) in vocabulary.snippets.sorted(by: { $0.key.count > $1.key.count }) {
            text = replacePhrase(trigger, in: text, with: expansion, eatTrailingPeriod: true)
        }
        for (from, to) in vocabulary.replacements.sorted(by: { $0.key.count > $1.key.count }) {
            text = replacePhrase(from, in: text, with: to, eatTrailingPeriod: false)
        }
        for word in vocabulary.words.sorted(by: { $0.count > $1.count }) {
            text = replacePhrase(word, in: text, with: word, eatTrailingPeriod: false)
        }

        text = tidy(text)
        text = capitalizeSentences(text)
        guard !text.isEmpty else { return "" }
        return join(text, after: before, vocabulary: vocabulary)
    }

    /// Fixes spacing and capitalization where the new text meets what is already in the field.
    static func join(_ text: String, after before: String?, vocabulary: Vocabulary) -> String {
        guard let before, let last = before.last else { return text }
        var out = text

        let trimmed = before.trimmingCharacters(in: .whitespaces)
        let midSentence = !(trimmed.isEmpty || ".!?:\n".contains(trimmed.last!))
        if midSentence, let first = out.first, first.isUppercase, !keepsCapital(out, vocabulary: vocabulary) {
            out = first.lowercased() + out.dropFirst()
        }
        if !last.isWhitespace, let first = out.first, first.isLetter || first.isNumber {
            out = " " + out
        }
        return out
    }

    static func keepsCapital(_ text: String, vocabulary: Vocabulary) -> Bool {
        let firstWord = text.prefix { $0.isLetter || $0 == "'" || $0 == "’" }
        if firstWord == "I" || firstWord.hasPrefix("I'") || firstWord.hasPrefix("I’") { return true }
        if firstWord.dropFirst().contains(where: \.isUppercase) { return true }
        return vocabulary.words.contains { $0.split(separator: " ").first.map(String.init) == String(firstWord) }
    }

    static func tidy(_ text: String) -> String {
        var t = text
        t = replace(#"[ \t]+"#, in: t, with: " ")
        t = replace(#" +([,.!?;:])"#, in: t, with: "$1")
        t = replace(#"([,.!?;:])\1+"#, in: t, with: "$1")
        t = replace(#"^[,.;:]\s*"#, in: t, with: "")
        t = replace(#" *\n *"#, in: t, with: "\n")
        // Close sentences that end at a paragraph break or at the end of the dictation.
        t = replace(#"([\p{L}\p{N}])(?=\n)"#, in: t, with: "$1.")
        t = t.trimmingCharacters(in: .whitespaces)
        if let last = t.last, last.isLetter || last.isNumber { t += "." }
        return t
    }

    static func capitalizeSentences(_ text: String) -> String {
        var out = ""
        var capNext = true
        var sawTerminator = false
        for ch in text {
            if capNext, ch.isLetter {
                out.append(contentsOf: ch.uppercased())
                capNext = false
                continue
            }
            out.append(ch)
            if ch == "\n" {
                capNext = true
            } else if ".!?".contains(ch) {
                sawTerminator = true
            } else if ch.isWhitespace {
                if sawTerminator { capNext = true }
                sawTerminator = false
            } else {
                sawTerminator = false
                capNext = false
            }
        }
        return out
    }

    static func replacePhrase(_ phrase: String, in text: String, with replacement: String, eatTrailingPeriod: Bool) -> String {
        let words = phrase.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }
        guard !words.isEmpty else { return text }
        var pattern = #"(?<![\w])"# + words.joined(separator: #"[\s,]+"#) + #"(?![\w])"#
        if eatTrailingPeriod { pattern += #"\.?"# }
        let template = NSRegularExpression.escapedTemplate(for: replacement)
        return replace(pattern, in: text, with: template)
    }

    static func replace(_ pattern: String, in text: String, with template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        return re.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    public static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace }.count
    }
}
