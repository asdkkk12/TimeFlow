package app.timeflow.timeflow

import android.app.*
import android.content.*
import android.net.Uri
import android.os.Build
import android.os.Vibrator
import android.os.VibratorManager
import org.json.JSONObject
import java.time.*
import java.util.UUID

class Reminders(private val context: Context, private val store: Store) {
    private val alarms = context.getSystemService(AlarmManager::class.java)
    private val notifications = context.getSystemService(NotificationManager::class.java)
    private val channel = ReminderChannels.ID
    init { ReminderChannels.ensure(notifications); AlarmNotifications.ensure(notifications) }
    @Suppress("DEPRECATION")
    fun status(): Map<String, Any> {
        val settings = notifications.getNotificationChannel(channel)
        val appEnabled = notifications.areNotificationsEnabled()
        val enabled = appEnabled && settings.importance != NotificationManager.IMPORTANCE_NONE
        val vibrator = if (Build.VERSION.SDK_INT >= 31) {
            context.getSystemService(VibratorManager::class.java).defaultVibrator
        } else context.getSystemService(Vibrator::class.java)
        val strong = notifications.getNotificationChannel(AlarmNotifications.CHANNEL)
        return mapOf(
            "notifications" to appEnabled,
            "exact" to (Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms()),
            "vibratorAvailable" to vibrator.hasVibrator(),
            "vibrationEnabled" to (enabled && settings.shouldVibrate() && settings.importance >= NotificationManager.IMPORTANCE_DEFAULT),
            "fullScreen" to (Build.VERSION.SDK_INT < 34 || notifications.canUseFullScreenIntent()),
            "fullScreenSpecialAccess" to (Build.VERSION.SDK_INT >= 34),
            "vivoDevice" to ReminderSettings.isVivo,
            "strongHeadsUp" to (appEnabled && strong.importance >= NotificationManager.IMPORTANCE_HIGH),
            "strongLockscreen" to (appEnabled && strong.lockscreenVisibility != Notification.VISIBILITY_SECRET),
            "strongNotifications" to (notifications.areNotificationsEnabled() && strong.importance != NotificationManager.IMPORTANCE_NONE),
            "strongVibrationEnabled" to (notifications.areNotificationsEnabled() && strong.shouldVibrate() && strong.importance >= NotificationManager.IMPORTANCE_DEFAULT),
            "missed" to store.rows("reminders").count { it.optString("status") == "missed" }
        )
    }
    private fun intent(key: String, action: String, token: String = ""): PendingIntent {
        val i = Intent(context, ReminderReceiver::class.java).apply { this.action = action; data = Uri.parse("timeflow://reminder/${Uri.encode(key)}/$action"); putExtra("key", key); putExtra("token", token) }
        return PendingIntent.getBroadcast(context, 0, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
    private fun alarmClockInfo(at: Long, key: String): AlarmManager.AlarmClockInfo {
        val show = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).apply {
                data = Uri.parse("timeflow://upcoming/${Uri.encode(key)}")
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return AlarmManager.AlarmClockInfo(at, show)
    }
    private fun cancel(key: String) { alarms.cancel(intent(key, "fire")); notifications.cancel(key, 1); AlarmSession.remove(key) }
    fun cancelAll() {
        store.rows("reminders").forEach { cancel(it.getString("id")) }
        notifications.cancel(AlarmNotifications.ID)
    }
    private data class Candidate(val key: String, val entry: JSONObject, val date: LocalDate, val time: LocalDateTime) {
        val fingerprint get() = OccurrenceRules.fingerprint(entry, date)
    }
    private fun candidate(e: JSONObject, date: LocalDate, key: String): Candidate? {
        val time = OccurrenceRules.time(e, date) ?: return null
        if (store.get("completions", key)?.optBoolean("done") == true) return null
        return Candidate(key, e, date, time)
    }
    private fun resolve(key: String, entries: Map<String, JSONObject>, exceptions: Map<String, JSONObject>): Candidate? {
        val x = exceptions[key]
        if (x != null) {
            if (x.optBoolean("deleted") || !entries.containsKey(x.getString("seriesId"))) return null
            val e = x.getJSONObject("entry")
            if (e.isNull("date")) return null
            return candidate(e, LocalDate.parse(e.getString("date")), key)
        }
        val series = key.substringBefore('@')
        val e = entries[series] ?: return null
        if (e.isNull("date")) return null
        val d = if (key.contains('@')) LocalDate.parse(key.substringAfter('@')) else LocalDate.parse(e.getString("date"))
        if (!OccurrenceRules.occurs(e, d)) return null
        return candidate(e, d, key)
    }
    private fun epoch(local: LocalDateTime) = local.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
    private fun schedule(row: JSONObject, force: Boolean = false) {
        val at = epoch(LocalDateTime.parse(row.getString("at")))
        if (at <= System.currentTimeMillis()) return
        val exact = Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms()
        // Recreate on reboot/time-zone/permission changes even if the stored generation is unchanged.
        if (!force && row.optLong("epoch") == at && row.optBoolean("exact") == exact) return
        val pi = intent(row.getString("id"), "fire", row.getString("token"))
        try {
            // Calendar reminders are explicitly user-visible and time-critical.
            // Alarm-clock alarms are never shifted by Doze once exact-alarm
            // permission is granted, and may start the foreground alert service.
            if (exact) alarms.setAlarmClock(alarmClockInfo(at, row.getString("id")), pi)
            else alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        } catch (_: SecurityException) { alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi) }
        row.put("epoch", at).put("exact", exact)
        store.put("reminders", row)
    }
    fun sync(force: Boolean = false) {
        AlarmSession.recover(context, store)
        val now = LocalDateTime.now()
        val skippedCount = store.rows("exceptions").size + store.rows("completions").size + store.rows("reminders").size
        val entries = store.rows("entries").associateBy { it.getString("id") }
        val exceptions = store.rows("exceptions").associateBy { it.getString("id") }
        for (row in store.rows("reminders")) {
            val key = row.getString("id")
            val current = resolve(key, entries, exceptions)
            if (current == null || row.getString("fingerprint") != current.fingerprint) {
                cancel(key); store.delete("reminders", key); continue
            }
            if (row.getString("status") in listOf("scheduled", "snoozed")) {
                if (!LocalDateTime.parse(row.getString("at")).isAfter(now)) {
                    // Avoid racing a due alarm during a foreground refresh. Old alarms are summarized.
                    if (epoch(LocalDateTime.parse(row.getString("at"))) < System.currentTimeMillis() - 60000) {
                        cancel(key); row.put("status", "missed"); store.put("reminders", row)
                    }
                } else schedule(row, force)
            }
        }
        fun register(c: Candidate) {
            if (!c.time.isAfter(now) || store.get("reminders", c.key) != null) return
            val row = JSONObject().put("id", c.key).put("at", c.time.toString()).put("fingerprint", c.fingerprint).put("status", "scheduled").put("token", UUID.randomUUID().toString())
            store.put("reminders", row)
            schedule(row, true)
        }
        for (e in entries.values) {
            if (e.isNull("date") || e.isNull("reminder")) continue
            val first = LocalDate.parse(e.getString("date"))
            if (e.getString("repeat") == "none") {
                if (!exceptions.containsKey(e.getString("id"))) candidate(e, first, e.getString("id"))?.let { register(it) }
                continue
            }
            var d = maxOf(first, now.toLocalDate().minusDays(1))
            // At least one weekly slot every seven days; skipped instances are finite stored records.
            val maxSearch = 14L + 7L * skippedCount
            val limit = if (e.isNull("until")) d.plusDays(maxSearch) else minOf(d.plusDays(maxSearch), LocalDate.parse(e.getString("until")))
            while (d <= limit) {
                val key = OccurrenceRules.key(e, d)
                if (OccurrenceRules.occurs(e, d) && !exceptions.containsKey(key)) {
                    val c = candidate(e, d, key)
                    val status = store.get("reminders", key)?.optString("status")
                    if (c != null && c.time.isAfter(now) && status !in listOf("fired", "missed", "snoozed", "active", "dismissed", "timed_out")) { register(c); break }
                }
                d = d.plusDays(1)
            }
        }
        for ((key, x) in exceptions) {
            if (x.optBoolean("deleted") || !entries.containsKey(x.getString("seriesId"))) continue
            val e = x.getJSONObject("entry")
            if (!e.isNull("date")) candidate(e, LocalDate.parse(e.getString("date")), key)?.let { register(it) }
        }
    }
    fun receive(action: String, key: String, token: String) {
        val row = store.get("reminders", key) ?: return
        if (row.optString("token") != token) return
        val current = resolve(key, store.rows("entries").associateBy { it.getString("id") }, store.rows("exceptions").associateBy { it.getString("id") })
        if (current == null || current.fingerprint != row.getString("fingerprint")) { cancel(key); store.delete("reminders", key); sync(); return }
        when (action) {
            "fire" -> {
                if (row.getString("status") !in listOf("scheduled", "snoozed")) return
                val at = epoch(LocalDateTime.parse(row.getString("at")))
                if (at > System.currentTimeMillis() + 1000) { schedule(row, true); return }
                val isEvent = current.entry.optString("kind") == "event"
                val selectedChannel = notifications.getNotificationChannel(if (isEvent) AlarmNotifications.CHANNEL else channel)
                val enabled = notifications.areNotificationsEnabled() && selectedChannel.importance != NotificationManager.IMPORTANCE_NONE
                if (enabled && isEvent) {
                    AlarmSession.begin(context, store, row, current.entry.getString("title"))
                } else {
                    row.put("status", if (enabled) "fired" else "missed")
                    store.put("reminders", row)
                }
                if (row.getString("status") == "fired") {
                    val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                    val notification = Notification.Builder(context, channel).setSmallIcon(R.drawable.ic_notification).setContentTitle(current.entry.getString("title")).setContentText("${current.date} · ${current.entry.optString("category")} · 点击查看安排").setContentIntent(open).setAutoCancel(true).setCategory(Notification.CATEGORY_REMINDER).setVisibility(Notification.VISIBILITY_PRIVATE)
                        .addAction(Notification.Action.Builder(null, "完成", intent(key, "complete", token)).build())
                        .addAction(Notification.Action.Builder(null, "10 分钟后", intent(key, "snooze", token)).build()).build()
                    try { notifications.notify(key, 1, notification) } catch (_: SecurityException) { row.put("status", "missed"); store.put("reminders", row) }
                }
            }
            "complete" -> {
                if (row.getString("status") != "fired") return
                store.put("completions", JSONObject().put("id", key).put("done", true)); cancel(key)
            }
            "dismiss" -> {
                if (row.getString("status") !in listOf("active", "fired", "timed_out")) return
                cancel(key); row.put("status", "dismissed"); store.put("reminders", row)
            }
            "snooze" -> {
                if (row.getString("status") !in listOf("active", "fired", "timed_out")) return
                cancel(key)
                row.put("status", "snoozed").put("at", LocalDateTime.now().plusMinutes(10).toString()).put("token", UUID.randomUUID().toString())
                store.put("reminders", row); schedule(row, true)
            }
        }
        sync()
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        NativeWorker.executor.execute {
            try { Store(context).use { store ->
                val action = intent.action ?: ""
                if (action == "dismiss_all" || action == "snooze_all") AlarmSession.action(context, store, intent.getStringExtra("key") ?: "", action.removeSuffix("_all"))
                else Reminders(context, store).receive(action, intent.getStringExtra("key") ?: "", intent.getStringExtra("token") ?: "")
            } }
            finally { pending.finish() }
        }
    }
}
class RecoveryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        NativeWorker.executor.execute {
            try { Store(context).use { store -> Reminders(context, store).sync(true) } }
            finally { pending.finish() }
        }
    }
}
