import AppKit
import ApplicationServices

/// What the cursor is sitting in when dictation starts, read through Accessibility.
/// Wispr Flow sends the same before/selected/after text to its server; Utter keeps it local.
struct FocusContext {
    var app: NSRunningApplication?
    var role: String?
    var beforeText: String?
    var selectedText: String?
    var isSecure = false

    static func capture() -> FocusContext {
        var ctx = FocusContext(app: NSWorkspace.shared.frontmostApplication)
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return ctx }
        let element = focused as! AXUIElement

        ctx.role = string(element, kAXRoleAttribute)
        let subrole = string(element, kAXSubroleAttribute)
        ctx.isSecure = subrole == (kAXSecureTextFieldSubrole as String)
        if ctx.isSecure { return ctx }

        guard let value = string(element, kAXValueAttribute) else { return ctx }
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() else { return ctx }
        var range = CFRange()
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &range) else { return ctx }

        let utf16 = value.utf16
        let start = max(0, min(range.location, utf16.count))
        let end = max(start, min(range.location + range.length, utf16.count))
        let startIndex = utf16.index(utf16.startIndex, offsetBy: start)
        let endIndex = utf16.index(utf16.startIndex, offsetBy: end)
        let before = String(utf16[utf16.startIndex..<startIndex]) ?? ""
        ctx.beforeText = String(before.suffix(300))
        ctx.selectedText = String(utf16[startIndex..<endIndex])
        return ctx
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }
}
