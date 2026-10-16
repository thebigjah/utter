import AppKit

/// Global push-to-talk key, read with a CGEventTap like Wispr Flow's helper.
/// Hold the key to talk. Press Space while holding to lock hands-free. Esc cancels.
final class HotkeyMonitor {
    enum Trigger: String, CaseIterable {
        case fn
        case rightOption

        var title: String {
            switch self {
            case .fn: return "Fn (Globe)"
            case .rightOption: return "Right Option"
            }
        }
    }

    var trigger: Trigger
    var onDown: () -> Void = {}
    var onUp: () -> Void = {}
    var onLock: () -> Void = {}
    var onCancel: () -> Void = {}
    /// Another key was pressed with the trigger, so the user meant a shortcut, not dictation.
    var onChord: () -> Void = {}
    var isRecording: () -> Bool = { false }

    private var tap: CFMachPort?
    private var held = false

    private static let fnKeyCodes: Set<Int64> = [63, 179]
    private static let rightOptionKeyCode: Int64 = 61
    private static let spaceKeyCode: Int64 = 49
    private static let escapeKeyCode: Int64 = 53

    init(trigger: Trigger) {
        self.trigger = trigger
    }

    var isRunning: Bool { tap != nil }

    /// Returns false until the app has Accessibility permission.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: CGEventMask(mask),
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let down: Bool?
            switch trigger {
            case .fn:
                down = Self.fnKeyCodes.contains(code) ? event.flags.contains(.maskSecondaryFn) : nil
            case .rightOption:
                down = code == Self.rightOptionKeyCode ? event.flags.contains(.maskAlternate) : nil
            }
            if let down, down != held {
                held = down
                down ? onDown() : onUp()
            }
        case .keyDown:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            if isRecording() && code == Self.escapeKeyCode {
                onCancel()
                return nil
            }
            if held {
                if code == Self.spaceKeyCode && isRecording() {
                    onLock()
                    return nil
                }
                // Fn+arrow, Option+letter and similar are shortcuts, not dictation.
                onChord()
            }
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }
}
