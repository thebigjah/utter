package com.purcellventures.utter

/** Finds the wake phrase in a transcript and pulls out what was said after it. Port of the Mac WakePhrase. */
class WakePhrase(val phrase: String) {
    private val regex: Regex

    init {
        val words = phrase.lowercase().split(" ").filter { it.isNotEmpty() }.map { Regex.escape(it) }.toMutableList()
        if (words.firstOrNull() == Regex.escape("hey")) words[0] = "(?:hey|hay|hi|hey there)"
        regex = Regex("""\b""" + words.joinToString("""[\s,.!?]+""") + """\b[\s,.!?:]*""", RegexOption.IGNORE_CASE)
    }

    /** The text after the first occurrence of the phrase, or null if the phrase is absent. */
    fun remainder(text: String): String? = regex.find(text)?.let { text.substring(it.range.last + 1).trim() }

    fun contains(text: String) = remainder(text) != null

    companion object {
        fun isCancel(text: String): Boolean =
            text.lowercase().trim { !it.isLetter() } in setOf("never mind", "nevermind", "cancel", "cancel that", "stop")
    }
}
