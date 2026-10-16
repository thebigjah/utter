import AppKit
import AVFoundation
import ServiceManagement
import Sparkle
import SwiftUI

@main
enum Main {
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-icon"), args.count > i + 2,
           let pixels = Int(args[i + 2]), let data = Brand.renderIcon(pixels: pixels) {
            try? data.write(to: URL(fileURLWithPath: args[i + 1]))
            return
        }
        if let i = args.firstIndex(of: "--transcribe"), args.count > i + 1 {
            let path = args[i + 1]
            let done = DispatchSemaphore(value: 0)
            Task.detached {
                await Controller.transcribeFile(path)
                done.signal()
            }
            done.wait()
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let controller = Controller()
    let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    private var statusItem: NSStatusItem!
    private var permissionTimer: Timer?
    private var welcomeWindow: NSWindow?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Brand.menuBarImage()
        statusItem.button?.setAccessibilityLabel("Utter")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        controller.onChange = { [weak self] in self?.refreshStatusIcon() }
        controller.prepare()
        log.notice("launch: mic=\(Permissions.microphone) ax=\(Permissions.accessibility)")

        if !controller.hotkey.start() || !Permissions.allGranted {
            showWelcome()
        }
        // The event tap needs Accessibility and the wake listener needs the mic.
        // Keep checking until both are granted.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            guard let self else { return }
            let tapRunning = self.controller.hotkey.start()
            if Permissions.microphone && self.controller.wake.mode == .off && Settings.wakeEnabled {
                self.controller.updateWakeListener()
            }
            if tapRunning && Permissions.microphone { timer.invalidate() }
        }
    }

    private func refreshStatusIcon() {
        statusItem.button?.image = Brand.menuBarImage(active: controller.state == .recording)
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let key = controller.hotkey.trigger.title

        let header: String
        switch controller.modelState {
        case .preparing: header = "Downloading speech model…"
        case .failed(let msg): header = "Speech model error: \(msg)"
        case .ready:
            header = !Permissions.allGranted || !controller.hotkey.isRunning
                ? "Setup needed"
                : "Hold \(key) to talk, add Space for hands-free"
        }
        menu.addItem(disabled(header))
        menu.addItem(disabled("\(controller.store.totalWords.formatted()) words dictated"))
        menu.addItem(.separator())
        let wakeItem = item("Listen for “\(Settings.wakePhrase)”", #selector(toggleWake), "")
        wakeItem.state = Settings.wakeEnabled ? .on : .off
        menu.addItem(wakeItem)
        menu.addItem(.separator())

        let recentItem = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
        let recent = NSMenu()
        let entries = controller.store.history.suffix(10).reversed()
        if entries.isEmpty { recent.addItem(disabled("Nothing yet")) }
        for entry in entries {
            let title = entry.text.count > 60 ? String(entry.text.prefix(60)) + "…" : entry.text
            let item = NSMenuItem(title: title.replacingOccurrences(of: "\n", with: " "),
                                  action: #selector(copyEntry(_:)), keyEquivalent: "")
            item.representedObject = entry.text
            item.toolTip = "Click to copy"
            item.target = self
            recent.addItem(item)
        }
        recentItem.submenu = recent
        menu.addItem(recentItem)
        menu.addItem(item("Copy Last Transcript", #selector(copyLast), "c"))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettings), ","))
        menu.addItem(item("Edit Dictionary…", #selector(editDictionary), ""))
        menu.addItem(item("Setup & Permissions…", #selector(showWelcome), ""))
        let update = NSMenuItem(title: "Check for Updates…",
                                action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        update.target = updater
        menu.addItem(update)
        menu.addItem(item("About Utter", #selector(showAbout), ""))
        menu.addItem(.separator())
        menu.addItem(item("Quit Utter", #selector(quit), "q"))
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggleWake() {
        Settings.wakeEnabled.toggle()
        controller.updateWakeListener()
    }

    @objc private func copyEntry(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func copyLast() {
        guard let text = controller.store.history.last?.text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func editDictionary() {
        NSWorkspace.shared.open(controller.store.dictionaryURL)
    }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "Private, on-device dictation for every app.",
                                         attributes: [.font: NSFont.systemFont(ofSize: 11)]),
        ])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: Windows

    @objc func showWelcome() {
        if welcomeWindow == nil {
            welcomeWindow = makeWindow(title: "Set Up Utter",
                                       view: WelcomeView(controller: controller, trigger: controller.hotkey.trigger))
        }
        present(welcomeWindow)
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "Utter Settings",
                                        view: SettingsView(controller: controller, updater: updater.updater))
        }
        present(settingsWindow)
    }

    private func makeWindow<V: View>(title: String, view: V) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = title
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func present(_ window: NSWindow?) {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: Permissions

enum Permissions {
    static var microphone: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }
    static var accessibility: Bool { AXIsProcessTrusted() }
    static var allGranted: Bool { microphone && accessibility }

    static func requestMicrophone() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        } else {
            open("Privacy_Microphone")
        }
    }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) { open("Privacy_Accessibility") }
    }

    static func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: SwiftUI windows

private struct BrandMark: View {
    var body: some View {
        Image(nsImage: NSImage(data: Brand.renderIcon(pixels: 256) ?? Data()) ?? NSImage())
            .resizable()
            .frame(width: 72, height: 72)
    }
}

struct WelcomeView: View {
    let controller: Controller
    let trigger: HotkeyMonitor.Trigger
    @State private var mic = Permissions.microphone
    @State private var ax = Permissions.accessibility
    @State private var model = "Checking…"
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                BrandMark()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Utter").font(.system(size: 26, weight: .semibold))
                    Text("Hold a key, talk, let go. Your words land wherever the cursor is.")
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            row("Microphone", "So Utter can hear you.", granted: mic, action: Permissions.requestMicrophone)
            row("Accessibility", "For the hold-to-talk key and to type into other apps.",
                granted: ax, action: Permissions.requestAccessibility)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Speech model").fontWeight(.medium)
                    Text("Runs on this Mac. Audio never leaves it.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Text(model).foregroundStyle(model == "Ready" ? .green : .secondary)
            }
            if trigger == .fn {
                Text("Tip: in System Settings › Keyboard, set “Press 🌐 key to” to “Do Nothing” so Fn only starts Utter.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Done") { NSApp.keyWindow?.close() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!(mic && ax))
            }
        }
        .padding(24)
        .frame(width: 480)
        .onReceive(tick) { _ in refresh() }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        mic = Permissions.microphone
        ax = Permissions.accessibility
        switch controller.modelState {
        case .preparing: model = "Downloading…"
        case .ready: model = "Ready"
        case .failed(let msg): model = msg
        }
    }

    private func row(_ title: String, _ detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Grant", action: action)
            }
        }
    }
}

struct SettingsView: View {
    let controller: Controller
    let updater: SPUUpdater
    @State private var trigger: HotkeyMonitor.Trigger
    @State private var idleBar = Settings.showIdleBar
    @State private var sounds = Settings.playSounds
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var autoUpdate: Bool
    @State private var wakeEnabled = Settings.wakeEnabled
    @State private var wakePhrase = Settings.wakePhrase

    init(controller: Controller, updater: SPUUpdater) {
        self.controller = controller
        self.updater = updater
        _trigger = State(initialValue: controller.hotkey.trigger)
        _autoUpdate = State(initialValue: updater.automaticallyChecksForUpdates)
    }

    var body: some View {
        Form {
            Picker("Hold-to-talk key", selection: $trigger) {
                ForEach(HotkeyMonitor.Trigger.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .onChange(of: trigger) { _, value in controller.setTrigger(value) }

            Toggle("Listen for a wake phrase", isOn: $wakeEnabled)
                .onChange(of: wakeEnabled) { _, value in
                    Settings.wakeEnabled = value
                    controller.updateWakeListener()
                }
            TextField("Wake phrase", text: $wakePhrase)
                .onSubmit {
                    let phrase = wakePhrase.trimmingCharacters(in: .whitespaces)
                    guard phrase.split(separator: " ").count >= 2 else { wakePhrase = Settings.wakePhrase; return }
                    controller.setWakePhrase(phrase)
                }
            Text("Say the phrase, then your message. A pause ends it. “Never mind” cancels.")
                .font(.caption).foregroundStyle(.secondary)

            Toggle("Show the bar when idle", isOn: $idleBar)
                .onChange(of: idleBar) { _, value in
                    Settings.showIdleBar = value
                    controller.overlay.showWhenIdle = value
                    controller.overlay.show(.idle)
                }
            Toggle("Play sounds", isOn: $sounds)
                .onChange(of: sounds) { _, value in Settings.playSounds = value }
            Toggle("Open at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, value in
                    do {
                        if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            Toggle("Check for updates automatically", isOn: $autoUpdate)
                .onChange(of: autoUpdate) { _, value in updater.automaticallyChecksForUpdates = value }

            LabeledContent("Dictionary") {
                Button("Edit…") { NSWorkspace.shared.open(controller.store.dictionaryURL) }
            }
            LabeledContent("Version") {
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
    }
}
