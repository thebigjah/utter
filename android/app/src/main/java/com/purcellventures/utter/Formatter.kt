package com.purcellventures.utter

import java.util.regex.Matcher

/** User-editable word list, find/replace pairs and spoken shortcuts. Same model as the Mac app. */
data class Vocabulary(
    val words: List<String> = emptyList(),
    val replacements: Map<String, String> = emptyMap(),
    val snippets: Map<String, String> = emptyMap(),
) {
    companion object {
        val starter = Vocabulary(words = listOf("Utter"))
    }
}

/** Turns a raw transcript into text ready to insert at the cursor. Port of the Mac formatter. */
object Formatter {
    private const val FILLERS = """\b(?:u+m+|u+h+|uhm|erm|e+r+|a+h+|h+m+|m{2,})\b[,.]?"""

    fun format(raw: String, vocabulary: Vocabulary = Vocabulary(), before: String? = null): String {
        var text = raw.trim()
        if (text.isEmpty()) return ""

        text = replace(FILLERS, text, "")
        text = replace("""\b(\w+)(?:[,]?\s+\1\b)+""", text, "$1")
        text = replace(""",?\s*\bnew paragraph\b[,.]?\s*""", text, "\n\n")
        text = replace(""",?\s*\bnew line\b[,.]?\s*""", text, "\n")

        for ((trigger, expansion) in vocabulary.snippets.entries.sortedByDescending { it.key.length }) {
            text = replacePhrase(trigger, text, expansion, eatTrailingPeriod = true)
        }
        for ((from, to) in vocabulary.replacements.entries.sortedByDescending { it.key.length }) {
            text = replacePhrase(from, text, to, eatTrailingPeriod = false)
        }
        for (word in vocabulary.words.sortedByDescending { it.length }) {
            text = replacePhrase(word, text, word, eatTrailingPeriod = false)
        }

        text = tidy(text)
        text = capitalizeSentences(text)
        if (text.isEmpty()) return ""
        return join(text, before, vocabulary)
    }

    internal fun join(text: String, before: String?, vocabulary: Vocabulary): String {
        if (before.isNullOrEmpty()) return text
        var out = text
        val trimmed = before.trimEnd(' ', '\t')
        val midSentence = !(trimmed.isEmpty() || trimmed.last() in ".!?:\n")
        if (midSentence && out.first().isUpperCase() && !keepsCapital(out, vocabulary)) {
            out = out.first().lowercase() + out.drop(1)
        }
        val first = out.first()
        if (!before.last().isWhitespace() && (first.isLetter() || first.isDigit())) out = " $out"
        return out
    }

    private fun keepsCapital(text: String, vocabulary: Vocabulary): Boolean {
        val firstWord = text.takeWhile { it.isLetter() || it == '\'' || it == '’' }
        if (firstWord == "I" || firstWord.startsWith("I'") || firstWord.startsWith("I’")) return true
        if (firstWord.drop(1).any { it.isUpperCase() }) return true
        return vocabulary.words.any { it.split(" ").first() == firstWord }
    }

    internal fun tidy(input: String): String {
        var t = input
        t = replace("""[ \t]+""", t, " ")
        t = replace(""" +([,.!?;:])""", t, "$1")
        t = replace("""([,.!?;:])\1+""", t, "$1")
        t = replace("""^[,.;:]\s*""", t, "")
        t = replace(""" *\n *""", t, "\n")
        // Close sentences that end at a paragraph break or at the end of the dictation.
        t = replace("""([\p{L}\p{N}])(?=\n)""", t, "$1.")
        t = t.trim(' ', '\t')
        if (t.isNotEmpty() && (t.last().isLetter() || t.last().isDigit())) t += "."
        return t
    }

    internal fun capitalizeSentences(text: String): String {
        val out = StringBuilder()
        var capNext = true
        var sawTerminator = false
        for (ch in text) {
            if (capNext && ch.isLetter()) {
                out.append(ch.uppercaseChar())
                capNext = false
                continue
            }
            out.append(ch)
            when {
                ch == '\n' -> capNext = true
                ch in ".!?" -> sawTerminator = true
                ch.isWhitespace() -> {
                    if (sawTerminator) capNext = true
                    sawTerminator = false
                }
                else -> {
                    sawTerminator = false
                    capNext = false
                }
            }
        }
        return out.toString()
    }

    private fun replacePhrase(phrase: String, text: String, replacement: String, eatTrailingPeriod: Boolean): String {
        val words = phrase.split(" ").filter { it.isNotEmpty() }.map { Regex.escape(it) }
        if (words.isEmpty()) return text
        var pattern = """(?<![\w])""" + words.joinToString("""[\s,]+""") + """(?![\w])"""
        if (eatTrailingPeriod) pattern += """\.?"""
        return replace(pattern, text, Matcher.quoteReplacement(replacement))
    }

    private fun replace(pattern: String, text: String, template: String): String =
        Regex(pattern, RegexOption.IGNORE_CASE).replace(text, template)

    fun wordCount(text: String): Int = text.split(Regex("""\s+""")).count { it.isNotEmpty() }
}
