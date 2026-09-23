package app.timeflow.timeflow

import android.app.NotificationChannel
import android.app.NotificationManager

/** Android owns channel behavior after creation, including user vibration choices. */
internal object ReminderChannels {
    const val ID = "timeflow_reminders"

    fun ensure(manager: NotificationManager, id: String = ID) {
        // Never replace a channel to override the user's mute / vibration settings.
        if (manager.getNotificationChannel(id) != null) return
        manager.createNotificationChannel(
            NotificationChannel(id, "事项提醒", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "任务到点通知，默认伴随两次短振"
                vibrationPattern = longArrayOf(0, 350, 180, 350)
                enableVibration(true)
            }
        )
    }
}
