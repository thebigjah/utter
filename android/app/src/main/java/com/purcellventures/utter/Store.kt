package com.purcellventures.utter

import android.content.Context
import org.json.JSONObject
import java.io.File

/** Dictionary and history, stored in the app's private files. Nothing leaves the phone. */
class Store(context: Context) {
    data class Entry(val time: Long, val text: String, val app: String?, val words: Int)

    private val dictionaryFile = File(context.filesDir, "dictionary.txt")
    private val historyFile = File(context.filesDir, "history.jsonl")

    /**
     * The dictionary is one plain-text file so it is easy to edit on a phone:
     * a bare line is a word, `spoken -> written` is a replacement, `trigger => text` is a snippet.
     */
    var dictionaryText: String
        get() = if (dictionaryFile.exists()) dictionaryFile.readText() else STARTER
        set(value) = dictionaryFile.writeText(value)

    fun vocabulary(): Vocabulary = parse(dictionaryText)

    fun append(entry: Entry) {
        val json = JSONObject()
            .put("time", entry.time)
            .put("text", entry.text)
            .put("app", entry.app ?: JSONObject.NULL)
            .put("words", entry.words)
        historyFile.appendText(json.toString() + "\n")
    }

    fun history(): List<Entry> {
        if (!historyFile.exists()) return emptyList()
        return historyFile.readLines().mapNotNull { line ->
            runCatching {
                val o = JSONObject(line)
                Entry(o.getLong("time"), o.getString("text"), o.optString("app").ifEmpty { null }, o.getInt("words"))
            }.getOrNull()
        }
    }

    companion object {
        const val STARTER = """# Words Utter should spell right, one per line
Utter

# Replacements: spoken -> written
# gonna -> going to

# Snippets: trigger => text
# my email => you@example.com
"""

        fun parse(text: String): Vocabulary {
            val words = mutableListOf<String>()
            val replacements = mutableMapOf<String, String>()
            val snippets = mutableMapOf<String, String>()
            for (raw in text.lines()) {
                val line = raw.trim()
                if (line.isEmpty() || line.startsWith("#")) continue
                when {
                    "=>" in line -> line.split("=>", limit = 2).let { snippets[it[0].trim()] = it[1].trim() }
                    "->" in line -> line.split("->", limit = 2).let { replacements[it[0].trim()] = it[1].trim() }
                    else -> words += line
                }
            }
            return Vocabulary(words, replacements, snippets)
        }
    }
}
