import AppKit
import AVFoundation
import UtterCore
import os

let log = Logger(subsystem: "com.purcellventures.utter", category: "dictation")

/// The dictation state machine. Every trigger (hotkey today, wake word later)
/// goes through begin / finish / cancel.
final class Controller {
    enum State { case idle, recording, processing }
    enum ModelState: Equatable { case preparing, ready, failed(String) }

    let store = Store()
    let overlay = Overlay()
    let inserter = Inserter()
    let hotkey: HotkeyMonitor

    private(set) var state: State = .idle
    private(set) var modelState: ModelState = .preparing {
        didSet { onChange() }
    }
    private var locale = Locale(identifier: "en-US")
    private var session: DictationSession?
    private var context = FocusContext()
    private var startedAt = Date()
    private var locked = false
    private var ignoreNextUp = false
    private var maxDurationWork: DispatchWorkItem?

    var onChange: () -> Void = {}

    static let maxDuration: TimeInterval = 6 * 60
    static let minHold: TimeInterval = 0.25

    init() {
        let saved = UserDefaults.standard.string(forKey: Settings.triggerKey).flatMap(HotkeyMonitor.Trigger.init)
        hotkey = HotkeyMonitor(trigger: saved ?? .fn)
        overlay.showWhenIdle = Settings.showIdleBar

        hotkey.isRecording = { [weak self] in self?.state == .recording }
        hotkey.onDown = { [weak self] in self?.triggerDown() }
        hotkey.onUp = { [weak self] in self?.triggerUp() }
        hotkey.onLock = { [weak self] in self?.lock() }
        hotkey.onCancel = { [weak self] in self?.cancel(silent: false) }
        hotkey.onChord = { [weak self] in
            guard let self, self.state == .recording, !self.locked else { return }
            self.cancel(silent: true)
        }
    }

    func prepare() {
        overlay.show(.idle)
        Task { @MainActor in
            do {
                locale = try await DictationSession.prepareModel(locale: Locale.current)
                modelState = .ready
                log.info("model ready locale=\(self.locale.identifier, privacy: .public)")
            } catch {
                modelState = .failed(error.localizedDescription)
                log.error("model failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: Hotkey mapping

    private func triggerDown() {
        log.info("trigger down, state=\(String(describing: self.state), privacy: .public)")
        switch state {
        case .idle:
            begin()
        case .recording where locked:
            ignoreNextUp = true
            finish()
        default:
            break
        }
    }

    private func triggerUp() {
        log.info("trigger up")
        if ignoreNextUp {
            ignoreNextUp = false
            return
        }
        guard state == .recording, !locked else { return }
        if Date().timeIntervalSince(startedAt) < Self.minHold {
            cancel(silent: true)
        } else {
            finish()
        }
    }

    private func lock() {
        guard state == .recording, !locked else { return }
        locked = true
        overlay.show(.listening(locked: true))
    }

    // MARK: Dictation

    func begin(locked startLocked: Bool = false) {
        guard state == .idle else { return }
        guard modelState == .ready else {
            overlay.show(.message(modelState == .preparing ? "Speech model is still downloading" : "Speech model unavailable"))
            return
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            overlay.show(.message("Utter needs microphone access"))
            NSApp.sendAction(#selector(AppDelegate.showWelcome), to: nil, from: nil)
            return
        }

        context = FocusContext.capture()
        log.info("begin: app=\(self.context.app?.localizedName ?? "?", privacy: .public) role=\(self.context.role ?? "none", privacy: .public) before=\(self.context.beforeText?.count ?? -1)")
        if context.isSecure {
            overlay.show(.message("Can't dictate into a password field"))
            return
        }

        let session = DictationSession(locale: locale, vocabulary: store.vocabulary().words)
        session.onLevel = { [weak self] level in
            DispatchQueue.main.async { self?.overlay.pushLevel(level) }
        }
        self.session = session
        state = .recording
        locked = startLocked
        startedAt = Date()
        Sounds.play(.start)
        overlay.show(.listening(locked: startLocked))

        Task { @MainActor in
            do {
                try await session.startMicrophone()
            } catch {
                self.fail("Microphone error: \(error.localizedDescription)")
            }
        }

        let work = DispatchWorkItem { [weak self] in self?.finish() }
        maxDurationWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.maxDuration, execute: work)
        onChange()
    }

    func finish() {
        guard state == .recording, let session else { return }
        maxDurationWork?.cancel()
        state = .processing
        locked = false
        Sounds.play(.stop)
        overlay.show(.processing)
        onChange()

        let context = self.context
        Task { @MainActor in
            do {
                let raw = try await session.finish()
                log.info("transcript chars=\(raw.count)")
                self.deliver(raw: raw, context: context)
            } catch {
                self.fail("Transcription failed: \(error.localizedDescription)")
            }
        }
    }

    func cancel(silent: Bool) {
        guard state == .recording else { return }
        maxDurationWork?.cancel()
        session?.cancel()
        session = nil
        locked = false
        state = .idle
        if !silent { Sounds.play(.cancel) }
        overlay.show(.idle)
        onChange()
    }

    private func deliver(raw: String, context: FocusContext) {
        session = nil
        let text = Formatter.format(raw, vocabulary: store.vocabulary(), before: context.beforeText)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .idle
            overlay.show(.idle)
            onChange()
            return
        }
        store.append(.init(date: Date(), text: text, raw: raw, app: context.app?.localizedName,
                           words: Formatter.wordCount(text)))
        inserter.insert(text) { [weak self] pasted in
            guard let self else { return }
            log.info("insert pasted=\(pasted)")
            self.state = .idle
            self.overlay.show(pasted ? .idle : .message("No text field took it. Copied to clipboard."))
            self.onChange()
        }
    }

    private func fail(_ message: String) {
        log.error("fail: \(message, privacy: .public)")
        session?.cancel()
        session = nil
        state = .idle
        locked = false
        overlay.show(.message(message))
        onChange()
    }

    func setTrigger(_ trigger: HotkeyMonitor.Trigger) {
        hotkey.trigger = trigger
        UserDefaults.standard.set(trigger.rawValue, forKey: Settings.triggerKey)
        onChange()
    }

    /// Feeds an audio file through the same pipeline and prints the result. Used for testing.
    static func transcribeFile(_ path: String) async {
        do {
            let locale = try await DictationSession.prepareModel(locale: Locale.current)
            let session = DictationSession(locale: locale, vocabulary: Store().vocabulary().words)
            try await session.feedFile(URL(fileURLWithPath: path))
            let raw = try await session.finish()
            print("RAW:       \(raw)")
            print("FORMATTED: \(Formatter.format(raw, vocabulary: Store().vocabulary()))")
        } catch {
            print("ERROR: \(error)")
            exit(1)
        }
    }
}

enum Settings {
    static let triggerKey = "trigger"
    static let idleBarKey = "showIdleBar"
    static let soundsKey = "playSounds"

    static var showIdleBar: Bool {
        get { UserDefaults.standard.object(forKey: idleBarKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: idleBarKey) }
    }

    static var playSounds: Bool {
        get { UserDefaults.standard.object(forKey: soundsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: soundsKey) }
    }
}

enum Sounds {
    enum Cue { case start, stop, cancel }

    static func play(_ cue: Cue) {
        guard Settings.playSounds else { return }
        let name: String
        switch cue {
        case .start: name = "Tink"
        case .stop: name = "Pop"
        case .cancel: name = "Funk"
        }
        let sound = NSSound(named: name)
        sound?.volume = 0.35
        sound?.play()
    }
}
