package com.purcellventures.utter

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer

/**
 * Wraps Android's SpeechRecognizer. Prefers the on-device engine and falls back to the
 * system default if the on-device language pack is missing. Android ends a session at each
 * pause, so while the user is still talking this restarts and stitches the segments together.
 */
class Recognizer(private val context: Context, private val listener: Listener) : RecognitionListener {
    interface Listener {
        fun onPartial(text: String)
        fun onLevel(level: Float)
        fun onFinished(text: String)
        fun onFailed(message: String)
    }

    private val handler = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null
    private var preferOnDevice = true
    private val segments = mutableListOf<String>()
    private var vocabulary: List<String> = emptyList()
    private var active = false
    private var stopping = false
    private val stopTimeout = Runnable { finish() }

    val isActive get() = active

    fun start(vocabulary: List<String>) {
        this.vocabulary = vocabulary
        segments.clear()
        active = true
        stopping = false
        listen()
    }

    /** User let go: take whatever the engine has and finish. */
    fun stop() {
        if (!active || stopping) return
        stopping = true
        recognizer?.stopListening()
        handler.postDelayed(stopTimeout, 2500)
    }

    fun cancel() {
        handler.removeCallbacks(stopTimeout)
        active = false
        stopping = false
        recognizer?.cancel()
        release()
    }

    private fun listen() {
        release()
        val onDevice = preferOnDevice && SpeechRecognizer.isOnDeviceRecognitionAvailable(context)
        val engine = if (onDevice) SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
                     else SpeechRecognizer.createSpeechRecognizer(context)
        engine.setRecognitionListener(this)
        engine.startListening(intent(onDevice))
        recognizer = engine
    }

    private fun intent(onDevice: Boolean) = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
        putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-US")
        putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
        putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, onDevice)
        putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 4000L)
        putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 3000L)
        if (Build.VERSION.SDK_INT >= 33) {
            putExtra(RecognizerIntent.EXTRA_ENABLE_FORMATTING, RecognizerIntent.FORMATTING_OPTIMIZE_QUALITY)
            if (vocabulary.isNotEmpty()) putStringArrayListExtra(RecognizerIntent.EXTRA_BIASING_STRINGS, ArrayList(vocabulary))
        }
    }

    private fun release() {
        recognizer?.destroy()
        recognizer = null
    }

    private fun finish() {
        handler.removeCallbacks(stopTimeout)
        if (!active) return
        active = false
        stopping = false
        release()
        listener.onFinished(segments.joinToString(" "))
    }

    override fun onResults(results: Bundle?) {
        results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
            ?.takeIf { it.isNotBlank() }?.let { segments += it.trim() }
        if (active && !stopping) listen() else finish()
    }

    override fun onPartialResults(partialResults: Bundle?) {
        val partial = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull().orEmpty()
        listener.onPartial((segments + partial).joinToString(" ").trim())
    }

    override fun onError(error: Int) {
        if (!active) return
        when (error) {
            SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED,
            SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> if (preferOnDevice) {
                preferOnDevice = false
                listen()
                return
            }
            SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> {
                if (!stopping) listen() else finish()
                return
            }
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> {
                cancel()
                listener.onFailed("Open Utter to allow the microphone")
                return
            }
        }
        if (stopping) {
            finish()
        } else {
            cancel()
            listener.onFailed("Speech error ($error)")
        }
    }

    override fun onRmsChanged(rmsdB: Float) = listener.onLevel(((rmsdB + 2f) / 12f).coerceIn(0f, 1f))
    override fun onReadyForSpeech(params: Bundle?) {}
    override fun onBeginningOfSpeech() {}
    override fun onBufferReceived(buffer: ByteArray?) {}
    override fun onEndOfSpeech() {}
    override fun onEvent(eventType: Int, params: Bundle?) {}
}
