package app.timeflow.timeflow

import android.app.*
import android.content.*
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.os.*

class AlarmService : Service() {
    companion object { @Volatile internal var instance: AlarmService? = null }
    private val handler = Handler(Looper.getMainLooper())
    private var sessionId: String? = null
    private var publishedBatch: AlarmBatch? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var screenWakeLock: PowerManager.WakeLock? = null
    private var stopping = false
    private val shutdown = Runnable {
        if (AlarmSession.current == null) stopSelf()
        else { stopping = false; render() }
    }
    private val timeout = Runnable {
        val id = sessionId ?: return@Runnable
        stopAlert()
        NativeWorker.executor.execute { Store(applicationContext).use { AlarmSession.finish(applicationContext, it, id) } }
    }

    override fun onCreate() {
        super.onCreate(); instance = this
        val manager = getSystemService(NotificationManager::class.java)
        AlarmNotifications.ensure(manager)
        // A dismiss/delete can race with service creation. Foreground immediately
        // even when the session has already gone, then perform normal cleanup.
        startInForeground(AlarmNotifications.starting(this))
    }
    override fun onBind(intent: Intent?) = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int { render(); return START_NOT_STICKY }

    internal fun render() {
        val batch = AlarmSession.current
        if (batch == null) { stopAlert(); return }
        stopping = false
        handler.removeCallbacks(shutdown)
        val manager = getSystemService(NotificationManager::class.java)
        AlarmNotifications.ensure(manager)
        try {
            startInForeground(AlarmNotifications.starting(this))
            if (publishedBatch != batch) {
                // Publish a fresh full-screen notification for each new session,
                // independently of the foreground service's status notification.
                // Updates within a batch must not launch or alert again.
                if (publishedBatch?.id != batch.id) manager.cancel(AlarmNotifications.ID)
                manager.notify(AlarmNotifications.ID, AlarmNotifications.active(this, batch))
                publishedBatch = batch
            }
        } catch (e: RuntimeException) {
            NativeWorker.executor.execute { Store(applicationContext).use { AlarmSession.fail(applicationContext, it, batch.id, e.javaClass.simpleName) } }
            stopSelf(); return
        }
        if (sessionId == batch.id) return
        sessionId = batch.id
        val remaining = batch.deadline - SystemClock.elapsedRealtime()
        if (remaining <= 0) { timeout.run(); return }
        acquireWakeLock(remaining)
        startVibration(remaining)
        handler.removeCallbacks(timeout); handler.postDelayed(timeout, remaining)
        // The notification full-screen PendingIntent is not consistently honored
        // by OEM lock screens (notably vivo/OriginOS). Once this short foreground
        // service is running, launch the alarm page directly as well. The activity
        // declares showWhenLocked/turnScreenOn, while the notification remains the
        // system fallback and the entry point for a user who dismisses the page.
        launchAlarmPage(batch.id)
    }

    private fun launchAlarmPage(id: String) {
        wakeScreenBriefly()
        val intent = Intent(this, AlarmActivity::class.java).addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
        ).putExtra("sessionId", id)
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                val options = ActivityOptions.makeBasic().apply {
                    setPendingIntentBackgroundActivityStartMode(
                        ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
                    )
                }.toBundle()
                startActivity(intent, options)
            } else {
                startActivity(intent)
            }
        } catch (_: RuntimeException) {
            // System notification full-screen delivery remains available when an
            // OEM rejects a direct background activity launch.
        }
    }

    @Suppress("DEPRECATION")
    private fun wakeScreenBriefly() {
        screenWakeLock?.let { if (it.isHeld) it.release() }
        screenWakeLock = getSystemService(PowerManager::class.java).newWakeLock(
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
            "$packageName:alarm-screen"
        ).apply {
            setReferenceCounted(false)
            acquire(10_000L)
        }
    }

    private fun startInForeground(notification: Notification) {
        if (Build.VERSION.SDK_INT >= 34) startForeground(AlarmNotifications.SERVICE_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE)
        else startForeground(AlarmNotifications.SERVICE_ID, notification)
    }

    private fun acquireWakeLock(remaining: Long) {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$packageName:calendar-alarm").apply {
            setReferenceCounted(false); acquire(remaining + 3000)
        }
    }

    @Suppress("DEPRECATION")
    private fun startVibration(remaining: Long) {
        val manager = getSystemService(NotificationManager::class.java)
        val channel = manager.getNotificationChannel(AlarmNotifications.CHANNEL) ?: return
        if (!manager.areNotificationsEnabled() || channel.importance < NotificationManager.IMPORTANCE_DEFAULT || !channel.shouldVibrate()) return
        val vibrator = if (Build.VERSION.SDK_INT >= 31) getSystemService(VibratorManager::class.java).defaultVibrator else getSystemService(Vibrator::class.java)
        if (!vibrator.hasVibrator()) return
        val cycles = ((remaining + 999) / 1000).coerceIn(1, 60).toInt()
        val timings = ArrayList<Long>(cycles * 2)
        timings.add(0)
        repeat(cycles) { timings.add(minOf(800, remaining - it * 1000).coerceAtLeast(1)); if (it < cycles - 1) timings.add(200) }
        val values = timings.toLongArray()
        val effect = if (vibrator.hasAmplitudeControl()) {
            VibrationEffect.createWaveform(values, IntArray(values.size) { if (it == 0 || it % 2 == 0) 0 else 255 }, -1)
        } else VibrationEffect.createWaveform(values, -1)
        vibrator.vibrate(effect, AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build())
    }

    @Suppress("DEPRECATION")
    private fun stopAlert() {
        if (stopping) return
        stopping = true
        handler.removeCallbacks(timeout)
        val vibrator = if (Build.VERSION.SDK_INT >= 31) getSystemService(VibratorManager::class.java).defaultVibrator else getSystemService(Vibrator::class.java)
        vibrator.cancel()
        wakeLock?.let { if (it.isHeld) it.release() }; wakeLock = null
        screenWakeLock?.let { if (it.isHeld) it.release() }; screenWakeLock = null
        getSystemService(NotificationManager::class.java).cancel(AlarmNotifications.ID)
        publishedBatch = null
        sessionId = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        // A second event can arrive while Android is tearing this service down.
        // Keep a short cancellable window so that startForegroundService always
        // has a live instance able to publish its notification immediately.
        handler.removeCallbacks(shutdown); handler.postDelayed(shutdown, 150)
    }

    override fun onTimeout(startId: Int) { timeout.run() }
    override fun onTimeout(startId: Int, fgsType: Int) { timeout.run() }
    override fun onDestroy() {
        handler.removeCallbacks(timeout); handler.removeCallbacks(shutdown)
        @Suppress("DEPRECATION")
        val vibrator = if (Build.VERSION.SDK_INT >= 31) getSystemService(VibratorManager::class.java).defaultVibrator else getSystemService(Vibrator::class.java)
        vibrator.cancel(); wakeLock?.let { if (it.isHeld) it.release() }
        screenWakeLock?.let { if (it.isHeld) it.release() }
        getSystemService(NotificationManager::class.java).cancel(AlarmNotifications.ID)
        if (instance === this) instance = null
        super.onDestroy()
    }
}
