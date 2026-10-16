package com.purcellventures.utter

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.inputmethodservice.InputMethodService
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.inputmethod.EditorInfo
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Utter's phone surface: a voice keyboard. Hold the button to talk, let go to insert.
 * A quick tap locks hands-free; tap again to finish. Text goes in through the field's own
 * InputConnection, so Android needs no clipboard trick.
 */
class UtterKeyboard : InputMethodService(), Recognizer.Listener {
    private enum class State { IDLE, LISTENING, PROCESSING }

    private lateinit var store: Store
    private lateinit var recognizer: Recognizer
    private lateinit var mic: MicButton
    private lateinit var status: TextView
    private lateinit var updateChip: TextView
    private val handler = Handler(Looper.getMainLooper())

    private var state = State.IDLE
    private var locked = false
    private var ignoreRelease = false

    override fun onCreate() {
        super.onCreate()
        store = Store(this)
        recognizer = Recognizer(this, this)
    }

    override fun onCreateInputView(): View {
        val dp = resources.displayMetrics.density
        val ink = getColor(R.color.ink)
        val cream = getColor(R.color.cream)
        val muted = getColor(R.color.muted)

        status = TextView(this).apply {
            setTextColor(muted)
            textSize = 14f
            gravity = Gravity.CENTER
            maxLines = 2
            ellipsize = TextUtils.TruncateAt.START
        }
        updateChip = TextView(this).apply {
            text = "Update ready, tap to install"
            setTextColor(getColor(R.color.coral))
            textSize = 13f
            gravity = Gravity.CENTER
            visibility = View.GONE
            setOnClickListener { openApp(installUpdate = true) }
        }
        mic = MicButton(this).apply {
            contentDescription = "Hold to talk"
            onPress = ::micPressed
            onRelease = ::micReleased
        }

        fun key(label: String, desc: String, action: () -> Unit) = TextView(this).apply {
            text = label
            contentDescription = desc
            setTextColor(cream)
            textSize = 20f
            gravity = Gravity.CENTER
            setOnClickListener { action() }
        }
        val globe = key("🌐", "Switch keyboard") {
            if (!switchToPreviousInputMethod()) {
                (getSystemService(INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager).showInputMethodPicker()
            }
        }
        val space = key("space", "Space") { currentInputConnection?.commitText(" ", 1) }.apply { textSize = 14f }
        val backspace = key("⌫", "Delete") { deleteOne() }.apply { setOnTouchListener(RepeatTouch { deleteOne() }) }
        val enter = key("⏎", "Enter") { pressEnter() }

        val micFrame = FrameLayout(this).apply {
            addView(mic, FrameLayout.LayoutParams((92 * dp).toInt(), (92 * dp).toInt(), Gravity.CENTER))
        }
        val bottom = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            val h = (48 * dp).toInt()
            addView(globe, LinearLayout.LayoutParams(0, h, 1f))
            addView(space, LinearLayout.LayoutParams(0, h, 2f))
            addView(backspace, LinearLayout.LayoutParams(0, h, 1f))
            addView(enter, LinearLayout.LayoutParams(0, h, 1f))
        }
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(ink)
            setPadding((12 * dp).toInt(), (10 * dp).toInt(), (12 * dp).toInt(), (6 * dp).toInt())
            addView(updateChip, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
            addView(status, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, (40 * dp).toInt()))
            addView(micFrame, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, (120 * dp).toInt()))
            addView(bottom)
        }
    }

    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        showIdle()
        Updater.checkIfDue(this) { release -> updateChip.visibility = if (release != null) View.VISIBLE else View.GONE }
    }

    override fun onFinishInputView(finishingInput: Boolean) {
        super.onFinishInputView(finishingInput)
        if (state == State.LISTENING) {
            recognizer.cancel()
            state = State.IDLE
        }
    }

    // MARK: Talk button

    private fun micPressed() {
        when {
            state == State.IDLE -> begin()
            state == State.LISTENING && locked -> {
                ignoreRelease = true
                end()
            }
        }
    }

    private fun micReleased(heldMs: Long) {
        if (ignoreRelease) {
            ignoreRelease = false
            return
        }
        if (state != State.LISTENING || locked) return
        if (heldMs < TAP_MS) {
            locked = true
            mic.mode = MicButton.Mode.LOCKED
            status.text = "Listening hands-free. Tap to finish."
        } else {
            end()
        }
    }

    private fun begin() {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            status.text = "Open Utter to allow the microphone"
            openApp()
            return
        }
        state = State.LISTENING
        locked = false
        mic.mode = MicButton.Mode.LISTENING
        status.text = "Listening…"
        recognizer.start(store.vocabulary().words)
    }

    private fun end() {
        state = State.PROCESSING
        mic.mode = MicButton.Mode.PROCESSING
        recognizer.stop()
    }

    private fun showIdle() {
        state = State.IDLE
        locked = false
        mic.mode = MicButton.Mode.IDLE
        status.text = "Hold to talk. Tap for hands-free."
    }

    // MARK: Recognizer.Listener

    override fun onPartial(text: String) {
        if (text.isNotEmpty()) status.text = text
    }

    override fun onLevel(level: Float) = mic.pushLevel(level)

    override fun onFinished(text: String) {
        val ic = currentInputConnection
        val before = ic?.getTextBeforeCursor(300, 0)?.toString()
        val formatted = Formatter.format(text, store.vocabulary(), before)
        if (formatted.isNotBlank() && ic != null) {
            ic.commitText(formatted, 1)
            store.append(Store.Entry(System.currentTimeMillis(), formatted, currentInputEditorInfo?.packageName, Formatter.wordCount(formatted)))
        }
        showIdle()
    }

    override fun onFailed(message: String) {
        showIdle()
        status.text = message
    }

    // MARK: Keys

    private fun deleteOne() {
        val ic = currentInputConnection ?: return
        if (!ic.getSelectedText(0).isNullOrEmpty()) ic.commitText("", 1) else ic.deleteSurroundingText(1, 0)
    }

    private fun pressEnter() {
        val ic = currentInputConnection ?: return
        val options = currentInputEditorInfo?.imeOptions ?: 0
        val action = options and EditorInfo.IME_MASK_ACTION
        if (action != EditorInfo.IME_ACTION_NONE && action != EditorInfo.IME_ACTION_UNSPECIFIED &&
            options and EditorInfo.IME_FLAG_NO_ENTER_ACTION == 0) {
            ic.performEditorAction(action)
        } else {
            ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER))
            ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER))
        }
    }

    private fun openApp(installUpdate: Boolean = false) {
        startActivity(Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            .putExtra(MainActivity.EXTRA_INSTALL_UPDATE, installUpdate))
    }

    /** Repeats an action while a key is held, like a normal backspace. */
    private inner class RepeatTouch(private val action: () -> Unit) : View.OnTouchListener {
        private val repeat = object : Runnable {
            override fun run() {
                action()
                handler.postDelayed(this, 60)
            }
        }

        override fun onTouch(v: View, event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    action()
                    handler.postDelayed(repeat, 400)
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> handler.removeCallbacks(repeat)
            }
            return true
        }
    }

    companion object {
        const val TAP_MS = 300L
    }
}
