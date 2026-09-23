package app.timeflow.timeflow

import android.content.Context
import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors

object NativeWorker { val executor = Executors.newSingleThreadExecutor() }

class Store(context: Context) : SQLiteOpenHelper(context, "timeflow.db", null, 1) {
    companion object { val tables = setOf("entries", "exceptions", "completions", "settings", "reminders") }
    override fun onCreate(db: SQLiteDatabase) {
        tables.forEach { db.execSQL("CREATE TABLE $it (id TEXT PRIMARY KEY NOT NULL, json TEXT NOT NULL)") }
    }
    override fun onUpgrade(db: SQLiteDatabase, old: Int, new: Int) {
        // Every future schema version must add an explicit, non-destructive migration here.
        require(old == new) { "Unsupported database migration $old → $new" }
    }
    fun rows(table: String): List<JSONObject> {
        require(table in tables)
        return readableDatabase.rawQuery("SELECT json FROM $table", null).use { c -> buildList { while (c.moveToNext()) add(JSONObject(c.getString(0))) } }
    }
    fun get(table: String, id: String): JSONObject? {
        require(table in tables)
        return readableDatabase.rawQuery("SELECT json FROM $table WHERE id = ?", arrayOf(id)).use { if (it.moveToFirst()) JSONObject(it.getString(0)) else null }
    }
    fun put(table: String, value: JSONObject) {
        require(table in tables)
        writableDatabase.insertWithOnConflict(table, null, ContentValues().apply { put("id", value.getString("id")); put("json", value.toString()) }, SQLiteDatabase.CONFLICT_REPLACE).also { check(it != -1L) }
    }
    fun delete(table: String, id: String) { require(table in tables); writableDatabase.delete(table, "id = ?", arrayOf(id)) }
    fun transaction(block: () -> Unit) {
        val db = writableDatabase
        db.beginTransaction()
        try { block(); db.setTransactionSuccessful() } finally { db.endTransaction() }
    }
    fun snapshot(): JSONObject = JSONObject().put("version", 1).apply { (tables - "reminders").forEach { put(it, JSONArray(rows(it))) } }
    fun mutate(ops: JSONArray) = transaction {
        for (i in 0 until ops.length()) {
            val op = ops.getJSONObject(i)
            val table = op.getString("table")
            require(table in tables - "reminders")
            if (op.has("delete")) delete(table, op.getString("delete")) else put(table, op.getJSONObject("row"))
        }
    }
    fun restore(data: JSONObject) {
        require(data.getInt("version") == 1)
        // The Dart importer performs domain validation before user confirmation.
        // Recheck structure before the transaction to reject malformed native calls too.
        (tables - "reminders").forEach { name ->
            val array = data.getJSONArray(name)
            require(array.length() <= 100000)
            val ids = mutableSetOf<String>()
            for (i in 0 until array.length()) require(ids.add(array.getJSONObject(i).getString("id")))
        }
        transaction {
            tables.forEach { writableDatabase.delete(it, null, null) }
            (tables - "reminders").forEach { name ->
                val array = data.getJSONArray(name)
                for (i in 0 until array.length()) put(name, array.getJSONObject(i))
            }
        }
    }
}
