package app.timeflow.timeflow

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    companion object { @Volatile internal var visible = false }
    private var documentResult: MethodChannel.Result? = null
    private var exportText: String? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.timeflow/native").setMethodCallHandler { call, result ->
            when (call.method) {
                "permission" -> try { permission(call.arguments as String); result.success(null) } catch (e: Exception) { result.error("PERMISSION", e.message, null) }
                "export", "import" -> {
                    if (documentResult != null) result.error("BUSY", "文件选择器正在使用", null)
                    else try {
                        documentResult = result
                        exportText = if (call.method == "export") call.arguments as String else null
                        val intent = if (call.method == "export") Intent(Intent.ACTION_CREATE_DOCUMENT).setType("application/json").putExtra(Intent.EXTRA_TITLE, "TimeFlow-${java.time.LocalDate.now()}.json") else Intent(Intent.ACTION_OPEN_DOCUMENT).setType("*/*")
                        startActivityForResult(intent.addCategory(Intent.CATEGORY_OPENABLE), if (call.method == "export") 201 else 202)
                    } catch (e: Exception) { documentResult = null; exportText = null; result.error("FILE", e.message, null) }
                }
                else -> NativeWorker.executor.execute {
                    try {
                        val value = Store(applicationContext).use { store ->
                            when (call.method) {
                                "snapshot" -> store.snapshot().toString()
                                "transact" -> { store.mutate(JSONArray(call.arguments as String)); Reminders(applicationContext, store).sync(); null }
                                "reminderStatus" -> Reminders(applicationContext, store).status()
                                "syncReminders" -> { Reminders(applicationContext, store).sync(true); null }
                                "restore" -> {
                                    val data = JSONObject(call.arguments as String)
                                    val reminders = Reminders(applicationContext, store)
                                    reminders.cancelAll()
                                    try { store.restore(data) } finally { reminders.sync(true) }
                                    null
                                }
                                else -> throw IllegalArgumentException("未知方法 ${call.method}")
                            }
                        }
                        runOnUiThread { result.success(value) }
                    } catch (e: Exception) { runOnUiThread { result.error("STORAGE", e.message ?: "本地操作失败", null) } }
                }
            }
        }
    }
    private fun permission(type: String) {
        if (type == "vibration") {
            val intent = Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                .putExtra(Settings.EXTRA_CHANNEL_ID, ReminderChannels.ID)
            try { startActivity(intent) }
            catch (_: android.content.ActivityNotFoundException) {
                startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
            }
        } else if (type == "strongVibration") {
            try { startActivity(Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                .putExtra(Settings.EXTRA_CHANNEL_ID, AlarmNotifications.CHANNEL)) }
            catch (_: android.content.ActivityNotFoundException) { startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)) }
        } else if (type == "fullScreen") {
            ReminderSettings.open(this, ReminderSettings.fullScreenIntents(packageName))
        } else if (type == "backgroundPopup") {
            ReminderSettings.open(this, listOf(ReminderSettings.appDetails(packageName)))
        } else if (type == "backgroundPower") {
            ReminderSettings.open(this, listOf(
                Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
                ReminderSettings.appDetails(packageName)))
        } else if (type == "exact" && Build.VERSION.SDK_INT >= 31) {
            startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:$packageName")))
        } else if (type == "notifications") {
            if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED && !getPreferences(0).getBoolean("askedNotifications", false)) {
                getPreferences(0).edit().putBoolean("askedNotifications", true).apply()
                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 203)
            } else startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
        }
    }
    override fun onResume() { super.onResume(); visible = true }
    override fun onPause() { visible = false; super.onPause() }
    @Deprecated("Android activity result bridge for FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode !in listOf(201, 202)) return
        val result = documentResult ?: return
        val text = exportText
        documentResult = null; exportText = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { result.success(null); return }
        NativeWorker.executor.execute {
            try {
                val value = if (requestCode == 201) {
                    requireNotNull(contentResolver.openOutputStream(uri, "wt")).use { it.write(requireNotNull(text).toByteArray(Charsets.UTF_8)) }
                    null
                } else {
                    requireNotNull(contentResolver.openInputStream(uri)).use { input ->
                        val bytes = java.io.ByteArrayOutputStream()
                        val buffer = ByteArray(8192)
                        while (true) { val n = input.read(buffer); if (n < 0) break; require(bytes.size() + n <= 32 * 1024 * 1024) { "备份超过 32 MB" }; bytes.write(buffer, 0, n) }
                        bytes.toString("UTF-8")
                    }
                }
                runOnUiThread { result.success(value) }
            } catch (e: Exception) { runOnUiThread { result.error("FILE", e.message, null) } }
        }
    }
    override fun onDestroy() {
        documentResult?.error("CANCELLED", "文件选择已中断，请重试", null)
        documentResult = null
        super.onDestroy()
    }
}
