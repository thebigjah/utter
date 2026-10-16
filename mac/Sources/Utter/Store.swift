import Foundation
import UtterCore

/// Local history and dictionary under ~/Library/Application Support/Utter.
/// Nothing leaves the Mac.
final class Store {
    struct Entry: Codable {
        var date: Date
        var text: String
        var raw: String
        var app: String?
        var words: Int
    }

    let directory: URL
    private(set) var history: [Entry] = []

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("Utter", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        loadHistory()
        if !FileManager.default.fileExists(atPath: dictionaryURL.path) {
            saveVocabulary(.starter)
        }
    }

    var dictionaryURL: URL { directory.appendingPathComponent("dictionary.json") }
    private var historyURL: URL { directory.appendingPathComponent("history.jsonl") }

    /// Read on every dictation so edits to the file apply immediately.
    func vocabulary() -> Vocabulary {
        guard let data = try? Data(contentsOf: dictionaryURL),
              let vocab = try? JSONDecoder().decode(Vocabulary.self, from: data) else { return .starter }
        return vocab
    }

    func saveVocabulary(_ vocab: Vocabulary) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(vocab).write(to: dictionaryURL)
    }

    var totalWords: Int { history.reduce(0) { $0 + $1.words } }

    func append(_ entry: Entry) {
        history.append(entry)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var line = try? encoder.encode(entry) else { return }
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: historyURL) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: historyURL)
        }
    }

    private func loadHistory() {
        guard let text = try? String(contentsOf: historyURL, encoding: .utf8) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        history = text.split(separator: "\n").compactMap { try? decoder.decode(Entry.self, from: Data($0.utf8)) }
    }
}
