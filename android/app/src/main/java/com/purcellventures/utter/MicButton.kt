package com.purcellventures.utter

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View

/** The big round talk button. Draws the brand's five bars, which follow your voice while listening. */
class MicButton(context: Context) : View(context) {
    enum class Mode { IDLE, LISTENING, LOCKED, PROCESSING }

    var mode = Mode.IDLE
        set(value) {
            field = value
            invalidate()
        }
    var onPress: () -> Unit = {}
    var onRelease: (heldMs: Long) -> Unit = {}

    private val ink = context.getColor(R.color.ink)
    private val cream = context.getColor(R.color.cream)
    private val coral = context.getColor(R.color.coral)
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val levels = FloatArray(5)
    private val shape = floatArrayOf(0.38f, 0.72f, 1f, 0.72f, 0.38f)
    private var pressedAt = 0L

    fun pushLevel(level: Float) {
        for (i in 0 until levels.size - 1) levels[i] = levels[i + 1]
        levels[levels.size - 1] = level
        invalidate()
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                pressedAt = SystemClock.uptimeMillis()
                performHapticFeedback(HAPTIC_FEEDBACK_ENABLED)
                onPress()
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                onRelease(SystemClock.uptimeMillis() - pressedAt)
                if (event.actionMasked == MotionEvent.ACTION_UP) performClick()
            }
        }
        return true
    }

    override fun performClick(): Boolean = super.performClick()

    override fun onDraw(canvas: Canvas) {
        val r = minOf(width, height) / 2f
        val cx = width / 2f
        val cy = height / 2f
        val listening = mode == Mode.LISTENING || mode == Mode.LOCKED

        paint.color = if (listening) coral else cream
        canvas.drawCircle(cx, cy, r, paint)

        val markW = r * 0.95f
        val barW = markW / 9f
        val left = cx - markW / 2f
        for (i in shape.indices) {
            val scale = when (mode) {
                Mode.LISTENING, Mode.LOCKED -> 0.25f + 0.75f * levels[(i + 2) % levels.size].coerceAtLeast(shape[i] * 0.3f)
                Mode.PROCESSING -> shape[i] * (0.6f + 0.4f * kotlin.math.abs(kotlin.math.sin((SystemClock.uptimeMillis() / 180.0) + i)).toFloat())
                Mode.IDLE -> shape[i]
            }
            val h = r * 0.9f * scale
            val x = left + i * barW * 2f
            paint.color = if (!listening && i == 2) coral else ink
            canvas.drawRoundRect(RectF(x, cy - h / 2f, x + barW, cy + h / 2f), barW / 2f, barW / 2f, paint)
        }
        if (mode == Mode.PROCESSING) postInvalidateOnAnimation()
    }
}
