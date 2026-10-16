import AppKit

/// Puts text into whatever app has focus, the way Wispr Flow's helper does:
/// a lazy pasteboard item plus a synthetic Cmd+V. The paste counts as successful
/// only when the target app actually asks the pasteboard for the data.
/// Afterwards the user's own clipboard comes back.
final class Inserter: NSObject, NSPasteboardItemDataProvider {
    private typealias SavedItem = [(NSPasteboard.PasteboardType, Data)]

    private var pendingText: String?
    private var requested = false
    private var saved: [SavedItem] = []
    private var timeout: DispatchWorkItem?
    private var completion: ((Bool) -> Void)?

    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    static let vKeyCode: CGKeyCode = 9

    func insert(_ text: String, completion: @escaping (Bool) -> Void) {
        finishPending(success: false)
        let pasteboard = NSPasteboard.general
        saved = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }

        pendingText = text
        requested = false
        self.completion = completion

        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setDataProvider(self, forTypes: [.string])
        // Clipboard managers skip transient items, so they will not fake a successful paste.
        item.setData(Data(), forType: Self.transientType)
        item.setData(Data(), forType: Self.concealedType)
        pasteboard.writeObjects([item])

        Self.postCommandV()

        let work = DispatchWorkItem { [weak self] in self?.timeoutFired() }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    // NSPasteboardItemDataProvider: the target app is reading the paste.
    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        guard let text = pendingText else { return }
        item.setString(text, forType: type)
        guard !requested else { return }
        requested = true
        timeout?.cancel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.restoreClipboard()
            self?.finishPending(success: true)
        }
    }

    private func timeoutFired() {
        guard pendingText != nil, !requested else { return }
        // Nothing took the paste. Leave the text on the clipboard so it is one Cmd+V away.
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(pendingText ?? "", forType: .string)
        finishPending(success: false)
    }

    private func restoreClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let items: [NSPasteboardItem] = saved.map { entries in
            let item = NSPasteboardItem()
            for (type, data) in entries { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
        saved = []
    }

    private func finishPending(success: Bool) {
        guard let completion else { return }
        timeout?.cancel()
        timeout = nil
        pendingText = nil
        self.completion = nil
        completion(success)
    }

    static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
