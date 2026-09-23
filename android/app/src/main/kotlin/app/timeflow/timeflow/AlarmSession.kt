package app.timeflow.timeflow

import android.app.*
import android.content.*
import android.os.*
import org.json.JSONObject
import java.util.UUID

internal data class AlarmMember(val key: String, val token: String, val title: String)
internal data class AlarmBatch(val id: String, val deadline: Long, val members: List<AlarmMember>)

/** Mutations run on NativeWorker; immutable snapshots are read by the Android UI. */
internal object AlarmSession {
    @Volatile var current: AlarmBatch? = null
        private set
    private val main = Handler(Looper.getMainLooper())
    fun publish() { main.post { AlarmService.instance?.render(); AlarmActivity.refresh?.invoke() } }
    @Synchronized fun begin(context: Context, store: Store, row: JSONObject, title: String) {
        recover(context, store)
        val old = current
        val batch = AlarmBatch(old?.id ?: UUID.randomUUID().toString(), old?.deadline ?: (SystemClock.elapsedRealtime() + 60000),
            (old?.members ?: emptyList()).filterNot { it.key == row.getString("id") } + AlarmMember(row.getString("id"), row.getString("token"), title))
        row.put("status", "active").put("sessionId", batch.id).put("deadlineElapsed", batch.deadline).put("title", title)
        store.put("reminders", row)
        current = batch
        try { context.startForegroundService(Intent(context, AlarmService::class.java)) }
        catch (e: RuntimeException) { fail(context, store, batch.id, e.javaClass.simpleName) }
        publish()
    }
    @Synchronized fun remove(key: String) {
        val batch = current ?: return
        val remaining = batch.members.filterNot { it.key == key }
        current = if (remaining.isEmpty()) null else batch.copy(members = remaining)
        publish()
    }
    @Synchronized fun action(context: Context, store: Store, id: String, action: String) {
        val batch = current?.takeIf { it.id == id } ?: return
        for (member in batch.members) Reminders(context, store).receive(action, member.key, member.token)
        if (current?.id == id) current = null
        publish()
    }
    @Synchronized fun finish(context: Context, store: Store, id: String, reason: String = "timed_out") {
        val batch = current?.takeIf { it.id == id } ?: return
        current = null
        publish()
        for (member in batch.members) {
            val row = store.get("reminders", member.key) ?: continue
            if (row.optString("token") != member.token || row.optString("status") != "active") continue
            row.put("status", "timed_out").put("stopReason", reason)
            store.put("reminders", row)
            AlarmNotifications.passive(context, row)
        }
        Reminders(context, store).sync()
    }
    fun fail(context: Context, store: Store, id: String, reason: String) = finish(context, store, id, "service_unavailable:$reason")
    @Synchronized fun recover(context: Context, store: Store) {
        current?.takeIf { it.deadline <= SystemClock.elapsedRealtime() }?.let { finish(context, store, it.id) }
        for (row in store.rows("reminders")) {
            if (row.optString("status") != "active") continue
            val live = current?.members?.any { it.key == row.getString("id") && it.token == row.getString("token") } == true
            if (!live) {
                row.put("status", "timed_out").put("stopReason", "process_recovered")
                store.put("reminders", row)
                AlarmNotifications.passive(context, row)
            }
        }
    }
}
