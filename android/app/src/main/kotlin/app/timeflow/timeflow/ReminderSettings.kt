package app.timeflow.timeflow

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings

/** Public settings routes only: OEM private activities vary across OS releases. */
internal object ReminderSettings {
    val isVivo: Boolean get() = listOf(Build.MANUFACTURER, Build.BRAND).any {
        it.equals("vivo", ignoreCase = true) || it.equals("iqoo", ignoreCase = true)
    }

    fun fullScreenIntents(packageName: String, sdk: Int = Build.VERSION.SDK_INT): List<Intent> = buildList {
        if (sdk >= 34) add(Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, Uri.parse("package:$packageName")))
        add(Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            .putExtra(Settings.EXTRA_CHANNEL_ID, AlarmNotifications.CHANNEL))
        add(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
        add(appDetails(packageName))
    }

    fun appDetails(packageName: String) = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))

    fun open(activity: Activity, intents: List<Intent>) {
        for (intent in intents) {
            try { activity.startActivity(intent); return }
            catch (_: ActivityNotFoundException) { }
            catch (_: SecurityException) { }
        }
        throw IllegalStateException("无法打开系统设置，请在手机设置中搜索 TimeFlow 并检查通知与权限")
    }
}
