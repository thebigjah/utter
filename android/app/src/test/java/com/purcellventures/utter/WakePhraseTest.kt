package com.purcellventures.utter

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Same cases as the Mac WakePhraseTests. */
class WakePhraseTest {
    private val wake = WakePhrase("Hey Cosmic")

    @Test fun findsPhraseAndRemainder() {
        assertEquals("tell Mom I'll be late.", wake.remainder("Hey Cosmic, tell Mom I'll be late."))
        assertEquals("", wake.remainder("hey cosmic"))
        assertEquals("Send it.", wake.remainder("Okay. Hey, Cosmic. Send it."))
        assertEquals("what time is it", wake.remainder("Hay cosmic what time is it"))
    }

    @Test fun ignoresOtherSpeech() {
        assertNull(wake.remainder("The cosmic background radiation"))
        assertNull(wake.remainder("Hey Cosimo, come here"))
    }

    @Test fun cancelWords() {
        assertTrue(WakePhrase.isCancel("Never mind."))
        assertTrue(WakePhrase.isCancel("cancel"))
        assertFalse(WakePhrase.isCancel("Cancel the meeting tomorrow."))
    }
}
