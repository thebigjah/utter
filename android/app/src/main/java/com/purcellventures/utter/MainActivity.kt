package com.purcellventures.utter

import android.Manifest
import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import java.text.DateFormat
import java.util.Date

/** Setup, dictionary, history and updates. The keyboard itself lives in UtterKeyboard. */
class MainActivity : Activity() {
    private lateinit var store: Store
    private lateinit var root: LinearLayout
    private var dp = 1f
    private var pendingRelease: Updater.Release? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        store = Store(this)
        dp = resources.displayMetrics.density
        root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(px(20), px(28), px(20), px(32))
        }
        setContentView(ScrollView(this).apply { addView(root) })
    }

    override fun onResume() {
        super.onResume()
        render()
        if (intent.getBooleanExtra(EXTRA_INSTALL_UPDATE, false)) {
            intent.removeExtra(EXTRA_INSTALL_UPDATE)
            Updater.check(this) { release -> release?.let(::startInstall) }
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        // Returning from the keyboard picker or Settings: refresh the step checklist.
        if (hasFocus) render()
    }

    private fun render() {
        root.removeAllViews()

        root.addView(LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(ImageView(context).apply { setImageResource(R.mipmap.ic_launcher) }, LinearLayout.LayoutParams(px(56), px(56)))
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(px(14), 0, 0, 0)
                addView(text("Utter", 26f, bold = true))
                addView(text("Hold the button, talk, let go.", 14f, muted = true))
            })
        })

        val micOk = checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        val imm = getSystemService(InputMethodManager::class.java)
        val enabled = imm.enabledInputMethodList.any { it.packageName == packageName }
        val selected = Settings.Secure.getString(contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD)
            ?.startsWith(packageName) == true

        section("Set up")
        step("1. Allow the microphone", micOk, "Allow") {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 1)
        }
        step("2. Turn on the Utter keyboard", enabled, "Open settings") {
            startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS))
        }
        step("3. Switch to Utter", selected, "Switch") { imm.showInputMethodPicker() }
        root.addView(text("Tip: the 🌐 key on Utter jumps back to your normal keyboard.", 13f, muted = true).padTop(6))

        section("Try it")
        root.addView(EditText(this).apply {
            hint = "Tap here, then hold the Utter button"
            minLines = 3
            setTextColor(getColor(R.color.cream))
            setHintTextColor(getColor(R.color.muted))
            background = card()
            setPadding(px(14), px(12), px(14), px(12))
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
        })

        section("Dictionary")
        root.addView(text("Names and terms Utter should spell right. Use spoken -> written for replacements and trigger => text for snippets.", 13f, muted = true))
        val dictionary = EditText(this).apply {
            setText(store.dictionaryText)
            typeface = Typeface.MONOSPACE
            textSize = 13f
            setTextColor(getColor(R.color.cream))
            background = card()
            setPadding(px(14), px(12), px(14), px(12))
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
        }
        root.addView(dictionary.padTop(8))
        root.addView(button("Save dictionary") {
            store.dictionaryText = dictionary.text.toString()
            Toast.makeText(this, "Saved", Toast.LENGTH_SHORT).show()
        })

        val history = store.history()
        section("History · ${history.sumOf { it.words }} words")
        if (history.isEmpty()) root.addView(text("Nothing yet.", 14f, muted = true))
        val clipboard = getSystemService(ClipboardManager::class.java)
        for (entry in history.takeLast(20).reversed()) {
            root.addView(LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                background = card()
                setPadding(px(14), px(10), px(14), px(10))
                addView(text(entry.text, 15f))
                addView(text(DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(entry.time)), 12f, muted = true))
                setOnClickListener {
                    clipboard.setPrimaryClip(ClipData.newPlainText("Utter", entry.text))
                    Toast.makeText(context, "Copied", Toast.LENGTH_SHORT).show()
                }
            }.padTop(8))
        }

        section("Updates")
        val updateStatus = text("Version ${BuildConfig.VERSION_NAME}", 14f, muted = true)
        root.addView(updateStatus)
        root.addView(button(if (pendingRelease != null) "Install ${pendingRelease!!.versionName}" else "Check for updates") {
            val ready = pendingRelease
            if (ready != null) {
                startInstall(ready)
                return@button
            }
            updateStatus.text = "Checking…"
            Updater.check(this) { release ->
                pendingRelease = release
                if (release == null) updateStatus.text = "Version ${BuildConfig.VERSION_NAME} is the latest."
                else render()
            }
        })
    }

    private fun startInstall(release: Updater.Release) {
        if (!packageManager.canRequestPackageInstalls()) {
            Toast.makeText(this, "Allow Utter to install updates, then come back", Toast.LENGTH_LONG).show()
            startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
            return
        }
        Updater.install(this, release) { message -> Toast.makeText(this, message, Toast.LENGTH_SHORT).show() }
    }

    // MARK: Small view helpers

    private fun px(value: Int) = (value * dp).toInt()

    private fun text(value: String, size: Float, bold: Boolean = false, muted: Boolean = false) = TextView(this).apply {
        text = value
        textSize = size
        setTextColor(getColor(if (muted) R.color.muted else R.color.cream))
        if (bold) typeface = Typeface.DEFAULT_BOLD
    }

    private fun section(title: String) {
        root.addView(text(title.uppercase(), 12f, bold = true, muted = true).padTop(28))
    }

    private fun step(title: String, done: Boolean, action: String, onClick: () -> Unit) {
        root.addView(LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = card()
            setPadding(px(14), px(12), px(10), px(12))
            addView(text(title, 15f), LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            if (done) addView(text("Done ✓", 14f).apply { setTextColor(getColor(R.color.coral)) })
            else addView(button(action, onClick))
        }.padTop(8))
    }

    private fun button(label: String, onClick: () -> Unit) = Button(this).apply {
        text = label
        isAllCaps = false
        setTextColor(getColor(R.color.ink))
        background = GradientDrawable().apply {
            cornerRadius = 22 * dp
            setColor(getColor(R.color.cream))
        }
        setPadding(px(16), 0, px(16), 0)
        setOnClickListener { onClick() }
    }

    private fun card() = GradientDrawable().apply {
        cornerRadius = 14 * dp
        setColor(getColor(R.color.ink_light))
    }

    private fun <T : View> T.padTop(value: Int): T = apply {
        layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            .apply { topMargin = px(value) }
    }

    companion object {
        const val EXTRA_INSTALL_UPDATE = "install_update"
    }
}
