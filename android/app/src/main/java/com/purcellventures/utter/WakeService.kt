package com.purcellventures.utter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer

/**
 * Listens for the wake phrase ("Hey Cosmic") in a foreground service, on-device.
 * After the phrase it keeps what you say until Android hears a pause, then types it
 * into the focused field (through the Utter keyboard or the accessibility helper),
 * or copies it if neither can reach the field.
 */
class WakeService : Service(), RecognitionListener {
    private enum class Mode { WAITING, CAPTURING }

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var store: Store
    private lateinit var wake: WakePhrase
    private var recognizer: SpeechRecognizer? = null
    private var onDevice = true
    private var mode = Mode.WAITING
    private var captured = mutableListOf<String>()
    private var pending = ""
    private var paused = false
    private val giveUp = Runnable { if (mode == Mode.CAPTURING) complete() }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        store = Store(this)
        wake = WakePhrase(Prefs.wakePhrase(this))
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            Prefs.setWakeEnabled(this, false)
            stopSelf()
            return START_NOT_STICKY
        }
        startForeground(NOTIFICATION_ID, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        listen()
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        recognizer?.destroy()
        recognizer = null
        if (instance === this) instance = null
        super.onDestroy()
    }

    /** The Utter keyboard is dictating; give it the microphone. */
    fun pause() {
        paused = true
        handler.removeCallbacksAndMessages(null)
        recognizer?.cancel()
    }

    fun resume() {
        if (!paused) return
        paused = false
        mode = Mode.WAITING
        handler.postDelayed({ listen() }, 400)
    }

    // MARK: Recognition loop

    private fun listen() {
        if (paused) return
        if (recognizer == null) {
            val useOnDevice = onDevice && SpeechRecognizer.isOnDeviceRecognitionAvailable(this)
            recognizer = (if (useOnDevice) SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
                          else SpeechRecognizer.createSpeechRecognizer(this)).also { it.setRecognitionListener(this) }
        }
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-US")
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, onDevice)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 1800L)
            putExtra(RecognizerIntent.EXTRA_ENABLE_FORMATTING, RecognizerIntent.FORMATTING_OPTIMIZE_QUALITY)
            putStringArrayListExtra(RecognizerIntent.EXTRA_BIASING_STRINGS,
                ArrayList(store.vocabulary().words + wake.phrase))
        }
        runCatching { recognizer?.startListening(intent) }.onFailure { restart(1000) }
    }

    private fun restart(delayMs: Long = 150) {
        handler.postDelayed({ listen() }, delayMs)
    }

    override fun onPartialResults(partialResults: Bundle?) {
        val text = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull().orEmpty()
        when (mode) {
            Mode.WAITING -> if (wake.contains(text)) {
                woke()
                pending = wake.remainder(text).orEmpty()
            }
            Mode.CAPTURING -> pending = wake.remainder(text) ?: text
        }
    }

    override fun onResults(results: Bundle?) {
        val text = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull().orEmpty()
        if (mode == Mode.WAITING && wake.contains(text)) woke()
        if (mode == Mode.CAPTURING) {
            pending = ""
            val piece = (wake.remainder(text) ?: text).trim()
            if (piece.isNotEmpty()) captured += piece
            // Android finalizes at a pause. A pause after real words ends the command;
            // "Hey Cosmic" on its own waits a few seconds for the rest.
            if (captured.isNotEmpty()) complete()
        }
        restart()
    }

    override fun onError(error: Int) {
        when (error) {
            SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED, SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> {
                onDevice = false
                recognizer?.destroy()
                recognizer = null
                restart(500)
            }
            SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> {
                if (mode == Mode.CAPTURING && (captured.isNotEmpty() || pending.isNotBlank())) complete()
                restart()
            }
            SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> restart(800)
            SpeechRecognizer.ERROR_CLIENT -> if (!paused) restart(500)
            else -> {
                recognizer?.destroy()
                recognizer = null
                restart(1500)
            }
        }
    }

    // MARK: Wake and deliver

    private fun woke() {
        mode = Mode.CAPTURING
        captured = mutableListOf()
        pending = ""
        getSystemService(Vibrator::class.java)?.vibrate(VibrationEffect.createPredefined(VibrationEffect.EFFECT_TICK))
        runCatching { ToneGenerator(AudioManager.STREAM_NOTIFICATION, 60).startTone(ToneGenerator.TONE_PROP_BEEP, 120) }
        handler.removeCallbacks(giveUp)
        handler.postDelayed(giveUp, 6000)
    }

    private fun complete() {
        handler.removeCallbacks(giveUp)
        if (pending.isNotBlank()) captured += pending.trim()
        val raw = captured.joinToString(" ")
        mode = Mode.WAITING
        captured = mutableListOf()
        pending = ""
        if (raw.isBlank() || WakePhrase.isCancel(raw)) return
        deliver(raw)
    }

    private fun deliver(raw: String) {
        val vocab = store.vocabulary()
        val inserted = UtterKeyboard.instance?.insertFromWake(raw) == true ||
            UtterAccessibility.instance?.insert(raw, vocab) == true
        if (!inserted) {
            val text = Formatter.format(raw, vocab)
            getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("Utter", text))
            store.append(Store.Entry(System.currentTimeMillis(), text, null, Formatter.wordCount(text)))
            getSystemService(NotificationManager::class.java)
                .notify(NOTIFICATION_ID, notification("Copied: $text"))
        }
    }

    // MARK: Notification

    private fun notification(detail: String? = null): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL, "Wake phrase", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1, Intent(this, WakeService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle("Listening for “${wake.phrase}”")
            .setContentText(detail ?: "Say it, then your message. Runs on this phone.")
            .setContentIntent(open)
            .addAction(Notification.Action.Builder(null, "Stop", stop).build())
            .setOngoing(true)
            .build()
    }

    override fun onReadyForSpeech(params: Bundle?) {}
    override fun onBeginningOfSpeech() {}
    override fun onRmsChanged(rmsdB: Float) {}
    override fun onBufferReceived(buffer: ByteArray?) {}
    override fun onEndOfSpeech() {}
    override fun onEvent(eventType: Int, params: Bundle?) {}

    companion object {
        const val CHANNEL = "wake"
        const val NOTIFICATION_ID = 7
        const val ACTION_STOP = "com.purcellventures.utter.STOP_WAKE"

        @Volatile var instance: WakeService? = null

        fun start(context: Context) {
            Prefs.setWakeEnabled(context, true)
            context.startForegroundService(Intent(context, WakeService::class.java))
        }

        fun stop(context: Context) {
            Prefs.setWakeEnabled(context, false)
            context.stopService(Intent(context, WakeService::class.java))
        }
    }
}

object Prefs {
    private fun prefs(c: Context) = c.getSharedPreferences("settings", Context.MODE_PRIVATE)
    fun wakeEnabled(c: Context) = prefs(c).getBoolean("wakeEnabled", false)
    fun setWakeEnabled(c: Context, value: Boolean) = prefs(c).edit().putBoolean("wakeEnabled", value).apply()
    fun wakePhrase(c: Context): String = prefs(c).getString("wakePhrase", "Hey Cosmic") ?: "Hey Cosmic"
    fun setWakePhrase(c: Context, value: String) = prefs(c).edit().putString("wakePhrase", value).apply()
}
