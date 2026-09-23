package app.timeflow.timeflow

import android.app.Activity
import android.content.*
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.*
import android.view.*
import android.widget.*
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

class AlarmActivity : Activity() {
    companion object { @Volatile internal var refresh: (() -> Unit)? = null }
    private lateinit var title: TextView
    private lateinit var countdown: TextView
    private lateinit var snooze: Button
    private lateinit var dismiss: Button
    private val handler = Handler(Looper.getMainLooper())
    private var expectedId: String? = null
    private val tick = object : Runnable { override fun run() { draw(); handler.postDelayed(this, 1000) } }

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        prepareLockScreenWindow()
        expectedId = intent.getStringExtra("sessionId") ?: intent.data?.lastPathSegment
        buildView()
        if (Build.VERSION.SDK_INT >= 33) onBackInvokedDispatcher.registerOnBackInvokedCallback(0) { act("dismiss_all") }
    }

    private fun prepareLockScreenWindow() {
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
        // OriginOS devices have been observed to respect the legacy flags more
        // reliably than the API 27 methods when the display was already asleep.
        // Both paths describe the same user-visible alarm behavior.
        window.addFlags(
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_FULLSCREEN or
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
        )
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE
            )
    }

    override fun onResume() {
        super.onResume()
        // Reassert after the keyguard's transition animation. This is harmless
        // on stock Android and prevents a vendor lock screen from reclaiming the
        // top window after the activity was launched.
        prepareLockScreenWindow()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        expectedId = intent.getStringExtra("sessionId") ?: intent.data?.lastPathSegment
        prepareLockScreenWindow()
        draw()
    }

    private fun text(value: String, size: Float, bold: Boolean = false) = TextView(this).apply {
        this.text = value; textSize = size; setTextColor(Color.WHITE); gravity = Gravity.CENTER
        if (bold) setTypeface(typeface, Typeface.BOLD); setPadding(dp(12), dp(8), dp(12), dp(8))
    }
    private fun buildView() {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(24), dp(38), dp(24), dp(28))
            background = GradientDrawable(GradientDrawable.Orientation.TL_BR, intArrayOf(Color.rgb(0,51,61), Color.rgb(48,43,40)))
        }
        val now = LocalDateTime.now()
        root.addView(text(now.format(DateTimeFormatter.ofPattern("HH:mm")), 72f), LinearLayout.LayoutParams(-1, -2))
        root.addView(text(now.format(DateTimeFormatter.ofPattern("M月d日 EEEE", Locale.SIMPLIFIED_CHINESE)), 20f), LinearLayout.LayoutParams(-1, -2))
        root.addView(Space(this), LinearLayout.LayoutParams(1, 0, 1f))
        title = text("", 32f, true); title.maxLines = 4
        root.addView(title, LinearLayout.LayoutParams(-1, -2))
        countdown = text("", 16f); countdown.setTextColor(Color.rgb(220,220,220))
        root.addView(countdown, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(12) })
        snooze = Button(this).apply { setTextColor(Color.rgb(255,190,72)); textSize = 22f; setTypeface(typeface, Typeface.BOLD); background = buttonBackground(Color.TRANSPARENT, Color.rgb(255,190,72), 3) }
        root.addView(snooze, LinearLayout.LayoutParams(-1, dp(68)).apply { setMargins(dp(22), dp(22), dp(22), 0) })
        snooze.setOnClickListener { act("snooze_all") }
        root.addView(Space(this), LinearLayout.LayoutParams(1, 0, 1f))
        dismiss = Button(this).apply { setTextColor(Color.WHITE); textSize = 20f; setTypeface(typeface, Typeface.BOLD); background = buttonBackground(Color.rgb(86,84,82), Color.TRANSPARENT, 0) }
        root.addView(dismiss, LinearLayout.LayoutParams(dp(220), dp(62)).apply { bottomMargin = dp(12) })
        dismiss.setOnClickListener { act("dismiss_all") }
        val scroll = ScrollView(this).apply { isFillViewport = true; addView(root, ViewGroup.LayoutParams(-1, -1)) }
        setContentView(scroll)
    }
    private fun buttonBackground(fill: Int, stroke: Int, width: Int) = GradientDrawable().apply { setColor(fill); cornerRadius = dp(36).toFloat(); if (width > 0) setStroke(dp(width), stroke) }
    private fun dp(n: Int) = (n * resources.displayMetrics.density).toInt()
    private fun draw() {
        val batch = AlarmSession.current
        if (batch == null || batch.id != expectedId) { finishAndRemoveTask(); return }
        title.text = batch.members.joinToString("\n") { it.title }
        val many = batch.members.size > 1
        snooze.text = if (many) "全部稍后提醒" else "稍后提醒"
        dismiss.text = if (many) "全部关闭" else "关闭"
        val seconds = ((batch.deadline - SystemClock.elapsedRealtime() + 999) / 1000).coerceAtLeast(0)
        countdown.text = "剩余 ${seconds} 秒"
    }
    private fun act(action: String) {
        val id = expectedId ?: return
        NativeWorker.executor.execute { Store(applicationContext).use { AlarmSession.action(applicationContext, it, id, action.removeSuffix("_all")) } }
        finishAndRemoveTask()
    }
    override fun onStart() { super.onStart(); refresh = { draw() }; handler.post(tick) }
    override fun onStop() { handler.removeCallbacks(tick); refresh = null; super.onStop() }
    @Deprecated("Handled identically to the visible close action")
    override fun onBackPressed() { act("dismiss_all") }
}
