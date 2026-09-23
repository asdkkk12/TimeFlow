package app.timeflow.timeflow

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.json.JSONObject
import org.json.JSONArray
import java.time.LocalDate
import java.time.LocalDateTime
import android.content.Intent
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class NativeTests {
    private lateinit var store: Store
    private lateinit var reminders: Reminders
    private lateinit var original: JSONObject
    private fun shell(command: String): String = InstrumentationRegistry.getInstrumentation().uiAutomation
        .executeShellCommand(command).use { descriptor ->
            java.io.FileInputStream(descriptor.fileDescriptor).use { String(it.readBytes()) }
        }
    private fun drainNativeWork() {
        val latch = CountDownLatch(1)
        NativeWorker.executor.execute { latch.countDown() }
        assertTrue(latch.await(5, TimeUnit.SECONDS))
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
    }
    @Before fun setup() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        if (android.os.Build.VERSION.SDK_INT >= 33) {
            InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand("pm grant ${context.packageName} android.permission.POST_NOTIFICATIONS").use { descriptor ->
                java.io.FileInputStream(descriptor.fileDescriptor).use { it.readBytes() }
            }
        }
        store = Store(context)
        reminders = Reminders(context, store)
        original = store.snapshot()
        reminders.cancelAll()
        store.restore(empty())
        drainNativeWork()
    }
    @After fun cleanup() {
        reminders.cancelAll(); store.restore(original); reminders.sync(true)
        drainNativeWork()
        store.close()
    }
    private fun empty() = JSONObject().put("version", 1).put("entries", JSONArray()).put("exceptions", JSONArray()).put("completions", JSONArray()).put("settings", JSONArray())
    private fun entry(id: String = "native-test"): JSONObject {
        val start = LocalDateTime.now().plusMinutes(5)
        return JSONObject().put("id", id).put("title", "原生提醒测试").put("notes", "").put("category", "个人").put("kind", "task").put("date", start.toLocalDate().toString()).put("minute", start.hour * 60 + start.minute).put("endMinute", JSONObject.NULL).put("endDays", 0).put("priority", 1).put("repeat", "none").put("weekdays", JSONArray()).put("until", JSONObject.NULL).put("reminder", 0)
    }
    private fun fire(): JSONObject {
        store.put("entries", entry())
        reminders.sync()
        val row = store.rows("reminders").single()
        row.put("at", LocalDateTime.now().minusSeconds(1).toString())
        store.put("reminders", row)
        reminders.receive("fire", row.getString("id"), row.getString("token"))
        return store.get("reminders", row.getString("id"))!!
    }
    @Test fun fullScreenSettingsExistBeforeAndAfterAndroid14() {
        val pkg = InstrumentationRegistry.getInstrumentation().targetContext.packageName
        for (sdk in listOf(26, 30, 31, 33, 34, 36)) {
            val routes = ReminderSettings.fullScreenIntents(pkg, sdk)
            assertEquals(if (sdk >= 34) android.provider.Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT
                else android.provider.Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS, routes.first().action)
            val channel = routes.single { it.action == android.provider.Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS }
            assertEquals(pkg, channel.getStringExtra(android.provider.Settings.EXTRA_APP_PACKAGE))
            assertEquals(AlarmNotifications.CHANNEL, channel.getStringExtra(android.provider.Settings.EXTRA_CHANNEL_ID))
            assertEquals("package:$pkg", routes.last().data.toString())
        }
    }
    @Test fun fullScreenStatusTracksRevokedSpecialAccess() {
        if (android.os.Build.VERSION.SDK_INT < 34) return
        val pkg = InstrumentationRegistry.getInstrumentation().targetContext.packageName
        try {
            shell("appops set $pkg USE_FULL_SCREEN_INTENT deny")
            assertEquals(false, reminders.status()["fullScreen"])
            shell("appops set $pkg USE_FULL_SCREEN_INTENT allow")
            assertEquals(true, reminders.status()["fullScreen"])
        } finally { shell("appops set $pkg USE_FULL_SCREEN_INTENT default") }
    }
    @Test fun sqliteRollbackAndRestoreAreAtomic() {
        store.put("entries", entry())
        try { store.transaction { store.delete("entries", "native-test"); error("模拟写入失败") } } catch (_: IllegalStateException) {}
        assertNotNull(store.get("entries", "native-test"))
        val bad = empty().put("version", 2)
        try { store.restore(bad); fail("must reject version") } catch (_: IllegalArgumentException) {}
        assertNotNull(store.get("entries", "native-test"))
    }
    @Test fun modifyingAndDeletingCancelOldGeneration() {
        val e = entry()
        store.put("entries", e); reminders.sync()
        val previous = store.rows("reminders").single().getString("token")
        e.put("title", "更新标题"); store.put("entries", e); reminders.sync()
        assertNotEquals(previous, store.rows("reminders").single().getString("token"))
        reminders.receive("complete", e.getString("id"), previous)
        assertNull(store.get("completions", e.getString("id")))
        store.delete("entries", e.getString("id")); reminders.sync()
        assertTrue(store.rows("reminders").isEmpty())
    }
    @Test fun snoozeAndCompletionActionsAreIdempotent() {
        val fired = fire()
        // Grant POST_NOTIFICATIONS with adb before running this suite.
        assertEquals("fired", fired.getString("status"))
        val oldToken = fired.getString("token")
        reminders.receive("snooze", "native-test", oldToken)
        val snoozed = store.get("reminders", "native-test")!!
        assertEquals("snoozed", snoozed.getString("status"))
        assertNotEquals(oldToken, snoozed.getString("token"))
        reminders.receive("snooze", "native-test", oldToken)
        assertEquals(snoozed.toString(), store.get("reminders", "native-test").toString())
        reminders.sync(true)
        assertEquals("snoozed", store.get("reminders", "native-test")!!.getString("status"))
        snoozed.put("at", LocalDateTime.now().minusSeconds(1).toString()); store.put("reminders", snoozed)
        reminders.receive("fire", "native-test", snoozed.getString("token"))
        reminders.receive("complete", "native-test", snoozed.getString("token"))
        reminders.receive("complete", "native-test", snoozed.getString("token"))
        assertTrue(store.get("completions", "native-test")!!.getBoolean("done"))
        assertTrue(store.rows("reminders").isEmpty())
    }
    @Test fun recurringAlarmChainsAndMissedAlarmIsNotReplayed() {
        val e = entry().put("repeat", "daily")
        store.put("entries", e); reminders.sync()
        val first = store.rows("reminders").single()
        first.put("at", LocalDateTime.now().minusMinutes(3).toString()); store.put("reminders", first)
        reminders.sync(true)
        val rows = store.rows("reminders")
        assertEquals(1, rows.count { it.getString("status") == "missed" })
        assertEquals(1, rows.count { it.getString("status") == "scheduled" })
        assertNotEquals(first.getString("id"), rows.first { it.getString("status") == "scheduled" }.getString("id"))
    }

    @Test fun realAlarmManagerDeliversAfterRescheduling() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        if (android.os.Build.VERSION.SDK_INT >= 31) {
            InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand("appops set ${context.packageName} SCHEDULE_EXACT_ALARM allow").use { p -> java.io.FileInputStream(p.fileDescriptor).use { it.readBytes() } }
        }
        store.put("entries", entry()); reminders.sync()
        val row = store.rows("reminders").single()
        row.put("at", LocalDateTime.now().plusSeconds(3).toString())
        store.put("reminders", row)
        reminders.sync(true)
        val deadline = System.currentTimeMillis() + 30000
        while (store.get("reminders", "native-test")?.optString("status") == "scheduled" && System.currentTimeMillis() < deadline) Thread.sleep(100)
        assertEquals("fired", store.get("reminders", "native-test")?.optString("status"))
    }
    @Test fun freshChannelUsesTwoShortVibrations() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val manager = context.getSystemService(android.app.NotificationManager::class.java)
        val id = "test-vibration-${java.util.UUID.randomUUID()}"
        try {
            ReminderChannels.ensure(manager, id)
            val channel = manager.getNotificationChannel(id)
            assertTrue(channel.shouldVibrate())
            assertArrayEquals(longArrayOf(0, 350, 180, 350), channel.vibrationPattern)
            assertEquals(android.app.NotificationManager.IMPORTANCE_HIGH, channel.importance)
        } finally { manager.deleteNotificationChannel(id) }
    }
    @Test fun existingMutedChannelIsNeverOverridden() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val manager = context.getSystemService(android.app.NotificationManager::class.java)
        val id = "test-muted-${java.util.UUID.randomUUID()}"
        try {
            manager.createNotificationChannel(android.app.NotificationChannel(id, "保留设置", android.app.NotificationManager.IMPORTANCE_LOW).apply { enableVibration(false) })
            ReminderChannels.ensure(manager, id)
            val channel = manager.getNotificationChannel(id)
            assertFalse(channel.shouldVibrate())
            assertEquals(android.app.NotificationManager.IMPORTANCE_LOW, channel.importance)
        } finally { manager.deleteNotificationChannel(id) }
    }
    @Test fun dueEventStartsOneStrongAlarmSession() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val manager = context.getSystemService(android.app.NotificationManager::class.java)
        val event = entry().put("kind", "event").put("endDays", 1).put("endMinute", 60)
        store.put("entries", event); reminders.sync()
        val row = store.rows("reminders").single()
        row.put("at", LocalDateTime.now().minusSeconds(1).toString()); store.put("reminders", row)
        reminders.receive("fire", row.getString("id"), row.getString("token"))
        val deadline = System.currentTimeMillis() + 5000
        while (manager.activeNotifications.none { it.id == AlarmNotifications.ID } && System.currentTimeMillis() < deadline) Thread.sleep(50)
        val notification = manager.activeNotifications.single { it.id == AlarmNotifications.ID }
        assertEquals("active", store.get("reminders", "native-test")!!.getString("status"))
        assertEquals(AlarmNotifications.CHANNEL, notification.notification.channelId)
        assertNotNull(notification.notification.fullScreenIntent)
        assertEquals(0, notification.notification.flags and android.app.Notification.FLAG_FOREGROUND_SERVICE)
        val serviceNotification = manager.activeNotifications.single { it.id == AlarmNotifications.SERVICE_ID }.notification
        assertNull(serviceNotification.fullScreenIntent)
        assertEquals(AlarmNotifications.SERVICE_CHANNEL, serviceNotification.channelId)
        assertTrue(manager.getNotificationChannel(notification.notification.channelId).shouldVibrate())
        val batch = AlarmSession.current!!
        reminders.receive("fire", row.getString("id"), row.getString("token"))
        drainNativeWork()
        // Service creation may update the notification independently of a duplicate
        // broadcast. Verify the actual idempotency contract, not its wall-clock post time.
        assertEquals(batch, AlarmSession.current)
        assertEquals(1, manager.activeNotifications.count { it.id == AlarmNotifications.ID })
        assertEquals(notification.postTime, manager.activeNotifications.single { it.id == AlarmNotifications.ID }.postTime)
    }
    @Test fun eventDismissAndSnoozeNeverCompleteTheEvent() {
        val event = entry().put("kind", "event")
        store.put("entries", event); reminders.sync()
        var row = store.rows("reminders").single()
        row.put("at", LocalDateTime.now().minusSeconds(1).toString()); store.put("reminders", row)
        reminders.receive("fire", row.getString("id"), row.getString("token"))
        val firstToken = row.getString("token")
        reminders.receive("snooze", row.getString("id"), firstToken)
        row = store.get("reminders", row.getString("id"))!!
        assertEquals("snoozed", row.getString("status"))
        assertNotEquals(firstToken, row.getString("token"))
        assertNull(store.get("completions", row.getString("id")))
        row.put("at", LocalDateTime.now().minusSeconds(1).toString()); store.put("reminders", row)
        reminders.receive("fire", row.getString("id"), row.getString("token"))
        reminders.receive("dismiss", row.getString("id"), row.getString("token"))
        assertEquals("dismissed", store.get("reminders", row.getString("id"))!!.getString("status"))
        assertNull(store.get("completions", row.getString("id")))
    }
    @Test fun mergedEventsKeepTheOriginalDeadline() {
        fun due(id: String) {
            store.put("entries", entry(id).put("kind", "event")); reminders.sync()
            val row = store.get("reminders", id)!!
            row.put("at", LocalDateTime.now().minusSeconds(1).toString()); store.put("reminders", row)
            reminders.receive("fire", id, row.getString("token"))
        }
        due("event-one")
        val first = AlarmSession.current!!
        due("event-two")
        val merged = AlarmSession.current!!
        assertEquals(first.id, merged.id)
        assertEquals(first.deadline, merged.deadline)
        assertEquals(2, merged.members.size)
        assertTrue(merged.deadline - android.os.SystemClock.elapsedRealtime() <= 60000)
    }
    @Test fun alarmPageShowsLongTitleCountdownAndBackDismisses() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val longTitle = "这是一个用于验证锁屏提醒页面长标题换行和大字体布局的日程"
        store.put("entries", entry().put("kind", "event").put("title", longTitle)); reminders.sync()
        val row = store.rows("reminders").single()
        row.put("at", LocalDateTime.now().minusSeconds(1).toString()); store.put("reminders", row)
        reminders.receive("fire", row.getString("id"), row.getString("token"))
        val session = AlarmSession.current!!
        val activity = InstrumentationRegistry.getInstrumentation().startActivitySync(
            Intent(context, AlarmActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK).putExtra("sessionId", session.id)
        ) as AlarmActivity
        fun allText(view: View): List<String> = when (view) {
            is TextView -> listOf(view.text.toString())
            is ViewGroup -> (0 until view.childCount).flatMap { allText(view.getChildAt(it)) }
            else -> emptyList()
        }
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        val labels = allText(activity.window.decorView)
        assertTrue(labels.contains(longTitle))
        assertTrue(labels.any { it.startsWith("剩余 ") })
        assertTrue(labels.contains("稍后提醒"))
        InstrumentationRegistry.getInstrumentation().runOnMainSync { activity.onBackPressed() }
        val deadline = System.currentTimeMillis() + 3000
        while (store.get("reminders", "native-test")?.optString("status") != "dismissed" && System.currentTimeMillis() < deadline) Thread.sleep(20)
        assertEquals("dismissed", store.get("reminders", "native-test")?.optString("status"))
    }
    @Test fun timeoutStopsTheSessionAndLeavesPassiveNotification() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val manager = context.getSystemService(android.app.NotificationManager::class.java)
        store.put("entries", entry().put("kind", "event")); reminders.sync()
        val row = store.rows("reminders").single()
        row.put("at", LocalDateTime.now().minusSeconds(1).toString()); store.put("reminders", row)
        reminders.receive("fire", row.getString("id"), row.getString("token"))
        val session = AlarmSession.current!!
        AlarmSession.finish(context, store, session.id)
        assertNull(AlarmSession.current)
        assertEquals("timed_out", store.get("reminders", row.getString("id"))!!.getString("status"))
        val deadline = System.currentTimeMillis() + 3000
        while (manager.activeNotifications.none { it.tag == row.getString("id") } && System.currentTimeMillis() < deadline) Thread.sleep(20)
        assertEquals(AlarmNotifications.HISTORY, manager.activeNotifications.single { it.tag == row.getString("id") }.notification.channelId)
    }
    @Test fun exactEventAlarmWakesTheLockedScreen() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val power = context.getSystemService(android.os.PowerManager::class.java)
        if (android.os.Build.VERSION.SDK_INT >= 31) shell("appops set ${context.packageName} SCHEDULE_EXACT_ALARM allow")
        if (android.os.Build.VERSION.SDK_INT >= 34) shell("appops set ${context.packageName} USE_FULL_SCREEN_INTENT allow")
        try {
            // Check the display and focused page, not just an Activity record.
            // The second independent alarm must wake again after dismissing the first.
            repeat(2) { index ->
                val event = entry("screen-$index").put("kind", "event").put("endMinute", 60).put("endDays", 1)
                store.put("entries", event); reminders.sync()
                val row = store.get("reminders", "screen-$index")!!
                shell("input keyevent 223")
                val sleepDeadline = System.currentTimeMillis() + 3000
                while (power.isInteractive && System.currentTimeMillis() < sleepDeadline) Thread.sleep(50)
                assertFalse("Display must be asleep before the alarm", power.isInteractive)
                row.put("at", LocalDateTime.now().plusSeconds(3).toString()); store.put("reminders", row)
                reminders.sync(true)
                val deadline = System.currentTimeMillis() + 20000
                var resumed = false
                while (System.currentTimeMillis() < deadline) {
                    val windows = shell("dumpsys window windows")
                    resumed = windows.contains("mCurrentFocus") && windows.contains("AlarmActivity")
                    if (power.isInteractive && resumed) break
                    Thread.sleep(100)
                }
                assertEquals("active", store.get("reminders", row.getString("id"))?.optString("status"))
                assertTrue("Alarm must turn the display on", power.isInteractive)
                assertTrue("Alarm $index must be resumed and focused: " + shell("dumpsys activity activities") + shell("dumpsys window windows"), resumed)
                AlarmSession.current?.let { AlarmSession.action(context, store, it.id, "dismiss") }
                drainNativeWork()
                val manager = context.getSystemService(android.app.NotificationManager::class.java)
                assertFalse(manager.activeNotifications.any { it.id == AlarmNotifications.ID })
                shell("input keyevent 224"); shell("wm dismiss-keyguard")
            }
        } finally {
            shell("input keyevent 224"); shell("wm dismiss-keyguard")
            AlarmSession.current?.let { AlarmSession.action(context, store, it.id, "dismiss") }
            instrumentation.waitForIdleSync()
        }
    }
    @Test fun nativeCalendarRulesMatchDomainFixtures() {
        val e = entry().put("date", "2026-09-21").put("repeat", "weekdays").put("until", "2026-09-28")
        assertTrue(OccurrenceRules.occurs(e, LocalDate.parse("2026-09-25")))
        assertFalse(OccurrenceRules.occurs(e, LocalDate.parse("2026-09-26")))
        assertTrue(OccurrenceRules.occurs(e, LocalDate.parse("2026-09-28")))
        assertFalse(OccurrenceRules.occurs(e, LocalDate.parse("2026-09-29")))
        e.put("repeat", "weekly").put("weekdays", JSONArray(listOf(2, 7)))
        assertTrue(OccurrenceRules.occurs(e, LocalDate.parse("2026-09-27")))
        assertFalse(OccurrenceRules.occurs(e, LocalDate.parse("2026-09-28")))
    }
}
