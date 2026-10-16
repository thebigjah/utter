import Foundation
import UtterCore

/// Always-on, on-device listener for the wake phrase ("Hey Cosmic").
/// After the phrase it keeps everything said in the same breath, ends on a pause,
/// and hands the text over. Nothing is kept while it is only waiting.
final class WakeListener {
    enum Mode { case off, waiting, capturing }

    var wake: WakePhrase
    var onWake: () -> Void = {}
    var onLevel: (Float) -> Void = { _ in }
    var onFinished: (String) -> Void = { _ in }
    var onCancelled: () -> Void = {}
    /// True while a hotkey dictation is running, so speech meant for it never wakes Cosmic.
    var isBusy: () -> Bool = { false }

    private(set) var mode: Mode = .off
    private var session: DictationSession?
    private var locale = Locale(identifier: "en-US")
    private var vocabulary: [String] = []
    private var captured: [String] = []
    private var pending = ""
    private var endWork: DispatchWorkItem?
    private var generation = 0
    /// Set when a command ended on a partial result: the matching final still carries
    /// "Hey Cosmic" and must not wake it a second time.
    private var ignoreUntilFinal = false

    /// Pause after the last word that ends the command.
    static let endSilence: TimeInterval = 1.8
    /// How long to wait for a command when "Hey Cosmic" was said on its own.
    static let firstWordWait: TimeInterval = 5
    static let maxCapture: TimeInterval = 120

    init(phrase: String) {
        wake = WakePhrase(phrase)
    }

    func start(locale: Locale, vocabulary: [String]) {
        self.locale = locale
        self.vocabulary = vocabulary + [wake.phrase, wake.phrase.split(separator: " ").last.map(String.init) ?? ""]
        guard mode == .off else { return }
        mode = .waiting
        spawn()
    }

    func stop() {
        mode = .off
        generation += 1
        endWork?.cancel()
        session?.cancel()
        session = nil
    }

    /// Fn pressed during a wake command: finish now with what has been heard.
    func finishNow() {
        guard mode == .capturing else { return }
        complete()
    }

    /// Esc during a wake command.
    func cancelCapture() {
        guard mode == .capturing else { return }
        endWork?.cancel()
        ignoreUntilFinal = !pending.isEmpty
        captured = []
        pending = ""
        mode = .waiting
    }

    private func spawn() {
        generation += 1
        let current = generation
        let session = DictationSession(locale: locale, vocabulary: vocabulary) { [weak self] text, isFinal in
            guard let self, self.generation == current else { return }
            self.handle(text, isFinal: isFinal)
        }
        session.onLevel = { [weak self] level in
            DispatchQueue.main.async {
                guard let self, self.mode == .capturing else { return }
                self.onLevel(level)
            }
        }
        self.session = session
        Task { @MainActor in
            do {
                try await session.startMicrophone()
                log.notice("wake listener on")
            } catch {
                log.error("wake mic failed: \(error.localizedDescription, privacy: .public)")
            }
            await session.waitUntilEnded()
            // The engine stopped on its own (device change, sleep). Restart if still wanted.
            guard self.generation == current, self.mode != .off else { return }
            try? await Task.sleep(for: .seconds(1))
            guard self.generation == current, self.mode != .off else { return }
            log.notice("wake listener restarting")
            self.mode = .waiting
            self.spawn()
        }
    }

    private func handle(_ text: String, isFinal: Bool) {
        switch mode {
        case .off:
            return
        case .waiting:
            if ignoreUntilFinal {
                if isFinal { ignoreUntilFinal = false }
                return
            }
            guard !isBusy(), wake.contains(text) else { return }
            mode = .capturing
            captured = []
            pending = ""
            log.notice("wake phrase heard")
            onWake()
            if isFinal { appendFinal(text) } else { pending = wake.remainder(in: text) ?? "" }
            scheduleEnd(after: pending.isEmpty && captured.isEmpty ? Self.firstWordWait : Self.endSilence)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.maxCapture) { [weak self] in
                if self?.mode == .capturing { self?.complete() }
            }
        case .capturing:
            if isFinal {
                appendFinal(text)
            } else {
                pending = wake.remainder(in: text) ?? text
            }
            let empty = captured.isEmpty && pending.trimmingCharacters(in: .whitespaces).isEmpty
            scheduleEnd(after: empty ? Self.firstWordWait : Self.endSilence)
        }
    }

    /// Finals arrive per phrase; the first one still contains "Hey Cosmic", so strip it.
    private func appendFinal(_ text: String) {
        pending = ""
        let piece = (wake.remainder(in: text) ?? text).trimmingCharacters(in: .whitespaces)
        if !piece.isEmpty { captured.append(piece) }
    }

    private func scheduleEnd(after delay: TimeInterval) {
        endWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.complete() }
        endWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func complete() {
        endWork?.cancel()
        guard mode == .capturing else { return }
        if !pending.isEmpty {
            captured.append(pending)
            ignoreUntilFinal = true
        }
        let text = captured.joined(separator: " ")
        captured = []
        pending = ""
        mode = .waiting
        if text.isEmpty || WakePhrase.isCancel(text) {
            onCancelled()
        } else {
            onFinished(text)
        }
    }
}
