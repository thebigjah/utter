package com.purcellventures.utter

import android.accessibilityservice.AccessibilityService
import android.os.Bundle
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Lets wake-phrase commands type into whatever field has focus, in any app, without
 * the Utter keyboard being open. It only acts when Utter hands it text; it reads nothing on its own.
 */
class UtterAccessibility : AccessibilityService() {
    override fun onServiceConnected() {
        instance = this
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {}

    /** Inserts at the cursor of the focused editable field. Returns false if there is none. */
    fun insert(raw: String, vocabulary: Vocabulary): Boolean {
        val node = rootInActiveWindow?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return false
        if (!node.isEditable) return false
        val current = if (node.isShowingHintText) "" else node.text?.toString().orEmpty()
        val start = node.textSelectionStart.takeIf { it in 0..current.length } ?: current.length
        val end = node.textSelectionEnd.takeIf { it in start..current.length } ?: start
        val text = Formatter.format(raw, vocabulary, current.substring(0, start))
        if (text.isBlank()) return true

        val updated = current.substring(0, start) + text + current.substring(end)
        val setText = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, updated)
        }
        if (!node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, setText)) return false
        val cursor = start + text.length
        node.performAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, Bundle().apply {
            putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, cursor)
            putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, cursor)
        })
        Store(this).append(Store.Entry(System.currentTimeMillis(), text, node.packageName?.toString(), Formatter.wordCount(text)))
        return true
    }

    companion object {
        @Volatile var instance: UtterAccessibility? = null
    }
}
