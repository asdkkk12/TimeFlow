package app.timeflow.timeflow

import android.app.*
import android.content.*
import android.net.Uri
import android.os.Build
import org.json.JSONObject

internal object AlarmNotifications {
    // v2 fixes older installs whose first strong-reminder channel inherited a
    // muted/low-importance task channel. Android channel behavior is immutable.
    const val CHANNEL = "timeflow_event_alarms_v2"
    const val HISTORY = "timeflow_alarm_history"
    const val ID = 60001
    const val SERVICE_ID = 60002
    const val SERVICE_CHANNEL = "timeflow_alarm_service"
    fun ensure(manager: NotificationManager) {
        if (manager.getNotificationChannel(CHANNEL) == null) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL, "日程强提醒", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "日程锁屏提醒，最多振动一分钟，不播放铃声"
                setSound(null, null)
                vibrationPattern = longArrayOf(0, 800)
                enableVibration(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            })
        }
        if (manager.getNotificationChannel(SERVICE_CHANNEL) == null) manager.createNotificationChannel(
            NotificationChannel(SERVICE_CHANNEL, "提醒运行状态", NotificationManager.IMPORTANCE_LOW).apply {
                description = "日程提醒期间的后台运行状态"
                setSound(null, null); enableVibration(false)
            })
        if (manager.getNotificationChannel(HISTORY) == null) manager.createNotificationChannel(
            NotificationChannel(HISTORY, "未处理日程", NotificationManager.IMPORTANCE_LOW).apply { setSound(null, null); enableVibration(false) })
    }
    fun action(context: Context, action: String, key: String, token: String = ""): PendingIntent = PendingIntent.getBroadcast(context, 0,
        Intent(context, ReminderReceiver::class.java).apply {
            this.action = action
            data = Uri.parse("timeflow://alarm/${Uri.encode(key)}/${Uri.encode(token)}/$action")
            putExtra("key", key); putExtra("token", token)
        }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    fun active(context: Context, batch: AlarmBatch): Notification {
        val i = Intent(context, AlarmActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .setData(Uri.parse("timeflow://session/${batch.id}")).putExtra("sessionId", batch.id)
        val options = if (Build.VERSION.SDK_INT >= 35) ActivityOptions.makeBasic().apply {
            setPendingIntentCreatorBackgroundActivityStartMode(ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED)
        }.toBundle() else null
        val open = PendingIntent.getActivity(context, 0, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE, options)
        val many = batch.members.size > 1
        return Notification.Builder(context, CHANNEL).setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(batch.members.joinToString("、") { it.title }).setContentText("日程提醒 · 最多振动 60 秒")
            .setContentIntent(open).setFullScreenIntent(open, true).setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC).setOngoing(true).setOnlyAlertOnce(true)
            .setPriority(Notification.PRIORITY_MAX).setWhen(System.currentTimeMillis()).setShowWhen(true)
            .addAction(Notification.Action.Builder(null, if (many) "全部关闭" else "关闭", action(context, "dismiss_all", batch.id)).build())
            .addAction(Notification.Action.Builder(null, if (many) "全部稍后提醒" else "稍后提醒", action(context, "snooze_all", batch.id)).build())
            .apply { if (Build.VERSION.SDK_INT >= 31) setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE) }
            .build()
    }
    fun starting(context: Context): Notification = Notification.Builder(context, SERVICE_CHANNEL)
        .setSmallIcon(R.drawable.ic_notification).setContentTitle("日程提醒")
        .setContentText("正在处理日程提醒").setCategory(Notification.CATEGORY_SERVICE)
        .setVisibility(Notification.VISIBILITY_PUBLIC).setOngoing(true).setOnlyAlertOnce(true)
        .apply { if (Build.VERSION.SDK_INT >= 31) setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE) }
        .build()
    fun passive(context: Context, row: JSONObject) {
        val manager = context.getSystemService(NotificationManager::class.java)
        ensure(manager)
        val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val key = row.getString("id"); val token = row.getString("token")
        val n = Notification.Builder(context, HISTORY).setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(row.optString("title", "日程提醒")).setContentText("提醒已结束 · 尚未处理")
            .setContentIntent(open).setAutoCancel(true).setOnlyAlertOnce(true).setGroup("ended_alarms").setGroupAlertBehavior(Notification.GROUP_ALERT_SUMMARY)
            .addAction(Notification.Action.Builder(null, "关闭", action(context, "dismiss", key, token)).build())
            .addAction(Notification.Action.Builder(null, "10 分钟后", action(context, "snooze", key, token)).build()).build()
        try { manager.notify(key, 1, n) } catch (_: SecurityException) { }
    }
}
