package com.purcellventures.utter

import org.junit.Assert.assertEquals
import org.junit.Test

/** Same cases as the Mac FormatterTests, so both apps format identically. */
class FormatterTest {
    @Test fun removesFillers() =
        assertEquals("So I think, we should go.", Formatter.format("Um, so I think, uh, we should go."))

    @Test fun collapsesStutteredWords() =
        assertEquals("I want the blue one.", Formatter.format("I want the the blue one."))

    @Test fun voiceCommands() {
        assertEquals("Hello there.\n\nThanks for coming.", Formatter.format("Hello there. New paragraph. Thanks for coming."))
        assertEquals("First item.\nSecond item.", Formatter.format("First item new line second item"))
        assertEquals("Ship it Friday.\n\nThanks for waiting.", Formatter.format("Ship it Friday\n\nThanks for waiting"))
    }

    @Test fun dictionaryFixesCasing() {
        val v = Vocabulary(words = listOf("Purcell Ventures", "GitHub"))
        assertEquals("I pushed it to GitHub for Purcell Ventures.",
            Formatter.format("I pushed it to github for purcell ventures.", v))
    }

    @Test fun replacementsAndSnippets() {
        val v = Vocabulary(replacements = mapOf("gonna" to "going to"), snippets = mapOf("my email" to "elijah@example.com"))
        assertEquals("I'm going to send it to elijah@example.com.", Formatter.format("I'm gonna send it to my email.", v))
    }

    @Test fun joinsMidSentence() {
        assertEquals(" The meeting moved.", Formatter.format("The meeting moved.", before = "Quick update:"))
        assertEquals(" tomorrow works.", Formatter.format("Tomorrow works.", before = "I think that"))
        assertEquals(" I agree.", Formatter.format("I agree.", before = "Honestly"))
        assertEquals("Sounds good.", Formatter.format("Sounds good.", before = "Done. "))
        assertEquals("Sounds good.", Formatter.format("Sounds good.", before = ""))
    }

    @Test fun empty() = assertEquals("", Formatter.format("  um  "))
}
