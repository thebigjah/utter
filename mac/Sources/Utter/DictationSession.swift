import AVFoundation
import Speech

/// One dictation: microphone (or file) audio in, on-device transcript out.
/// Audio flows while you speak, so the transcript is nearly done when you let go.
final class DictationSession {
    private let transcriber: DictationTranscriber
    private let analyzer: SpeechAnalyzer
    private let input: AsyncStream<AnalyzerInput>
    private let feed: AsyncStream<AnalyzerInput>.Continuation
    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var startTask: Task<Void, Error>?
    private var resultsTask: Task<String, Error>?
    var onLevel: ((Float) -> Void)?

    init(locale: Locale, vocabulary: [String]) {
        transcriber = DictationTranscriber(locale: locale, contentHints: [],
                                           transcriptionOptions: [.punctuation],
                                           reportingOptions: [], attributeOptions: [])
        analyzer = SpeechAnalyzer(modules: [transcriber],
                                  options: .init(priority: .userInitiated, modelRetention: .processLifetime))
        (input, feed) = AsyncStream<AnalyzerInput>.makeStream()

        let transcriber = self.transcriber
        resultsTask = Task {
            var text = ""
            for try await result in transcriber.results where result.isFinal {
                let piece = String(result.text.characters).trimmingCharacters(in: .whitespaces)
                guard !piece.isEmpty else { continue }
                text += text.isEmpty ? piece : " " + piece
            }
            return text
        }
        let analyzer = self.analyzer
        let input = self.input
        startTask = Task {
            if !vocabulary.isEmpty {
                let context = AnalysisContext()
                context.contextualStrings[.general] = vocabulary
                try await analyzer.setContext(context)
            }
            try await analyzer.start(inputSequence: input)
        }
    }

    /// Downloads the on-device model for this locale if macOS does not have it yet.
    static func prepareModel(locale: Locale) async throws -> Locale {
        let resolved = await DictationTranscriber.supportedLocale(equivalentTo: locale) ?? Locale(identifier: "en-US")
        let probe = DictationTranscriber(locale: resolved, preset: .shortDictation)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [probe]) {
            try await request.downloadAndInstall()
        }
        return resolved
    }

    private func analyzerFormat() async -> AVAudioFormat? {
        await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
    }

    // MARK: Microphone

    func startMicrophone() async throws {
        targetFormat = await analyzerFormat()
        let engine = AVAudioEngine()
        let node = engine.inputNode
        let format = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.push(buffer)
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    // MARK: File (used by `Utter --transcribe` to test without a microphone)

    func feedFile(_ url: URL) async throws {
        targetFormat = await analyzerFormat()
        let file = try AVAudioFile(forReading: url)
        while file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096) else { break }
            try file.read(into: buffer)
            if buffer.frameLength == 0 { break }
            push(buffer)
        }
    }

    private func push(_ buffer: AVAudioPCMBuffer) {
        onLevel?(Self.level(of: buffer))
        guard let target = targetFormat else { return }
        if buffer.format == target {
            feed.yield(AnalyzerInput(buffer: buffer))
            return
        }
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
        }
        guard let converter else { return }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        if error == nil, out.frameLength > 0 {
            feed.yield(AnalyzerInput(buffer: out))
        }
    }

    static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += samples[i] * samples[i] }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        return min(1, max(0, (20 * log10(max(rms, 1e-6)) + 55) / 45))
    }

    // MARK: Ending

    private func stopAudio() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        feed.finish()
    }

    /// Stops listening and returns the full transcript.
    func finish() async throws -> String {
        stopAudio()
        try await startTask?.value
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return try await resultsTask?.value ?? ""
    }

    func cancel() {
        stopAudio()
        resultsTask?.cancel()
        let analyzer = self.analyzer
        Task { await analyzer.cancelAndFinishNow() }
    }
}
