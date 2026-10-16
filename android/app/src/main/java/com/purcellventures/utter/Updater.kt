package com.purcellventures.utter

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Handler
import android.os.Looper
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Self-updates outside the Play Store. Reads a small JSON manifest
 * ({"versionCode", "versionName", "apkUrl", "notes"}), downloads the APK, and hands it to
 * PackageInstaller. Android only accepts it if it is signed with the same key as this install.
 */
object Updater {
    data class Release(val versionCode: Int, val versionName: String, val apkUrl: String, val notes: String)

    private val main = Handler(Looper.getMainLooper())
    private const val PREFS = "updater"
    private const val DAY_MS = 24 * 60 * 60 * 1000L

    /** Checks at most once a day. Calls back on the main thread with a newer release or null. */
    fun checkIfDue(context: Context, callback: (Release?) -> Unit) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val cached = prefs.getString("pending", null)?.let(::parse)?.takeIf { it.versionCode > BuildConfig.VERSION_CODE }
        if (System.currentTimeMillis() - prefs.getLong("lastCheck", 0) < DAY_MS) {
            callback(cached)
            return
        }
        check(context, callback)
    }

    fun check(context: Context, callback: (Release?) -> Unit) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        Thread {
            val release = runCatching { parse(get(BuildConfig.UPDATE_URL)) }.getOrNull()
                ?.takeIf { it.versionCode > BuildConfig.VERSION_CODE }
            prefs.edit()
                .putLong("lastCheck", System.currentTimeMillis())
                .putString("pending", release?.let { toJson(it) })
                .apply()
            main.post { callback(release) }
        }.start()
    }

    /** Downloads and starts the install. Android shows its own confirmation screen. */
    fun install(context: Context, release: Release, onProgress: (String) -> Unit) {
        Thread {
            runCatching {
                main.post { onProgress("Downloading ${release.versionName}…") }
                val apk = File(context.cacheDir, "update.apk")
                open(release.apkUrl).inputStream.use { input -> apk.outputStream().use { input.copyTo(it) } }

                val installer = context.packageManager.packageInstaller
                val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
                    .apply { setAppPackageName(context.packageName) }
                val sessionId = installer.createSession(params)
                installer.openSession(sessionId).use { session ->
                    session.openWrite("utter.apk", 0, apk.length()).use { out ->
                        apk.inputStream().use { it.copyTo(out) }
                        session.fsync(out)
                    }
                    val intent = Intent(context, InstallReceiver::class.java)
                    val pending = PendingIntent.getBroadcast(context, sessionId, intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE)
                    session.commit(pending.intentSender)
                }
                main.post { onProgress("Installing…") }
            }.onFailure { error ->
                main.post { onProgress("Update failed: ${error.message}") }
            }
        }.start()
    }

    private fun open(url: String): HttpURLConnection =
        (URL(url).openConnection() as HttpURLConnection).apply {
            instanceFollowRedirects = true
            connectTimeout = 10_000
            readTimeout = 30_000
        }

    private fun get(url: String): String = open(url).inputStream.bufferedReader().use { it.readText() }

    private fun parse(json: String): Release = JSONObject(json).let {
        Release(it.getInt("versionCode"), it.getString("versionName"), it.getString("apkUrl"), it.optString("notes"))
    }

    private fun toJson(r: Release) = JSONObject()
        .put("versionCode", r.versionCode).put("versionName", r.versionName)
        .put("apkUrl", r.apkUrl).put("notes", r.notes).toString()
}
