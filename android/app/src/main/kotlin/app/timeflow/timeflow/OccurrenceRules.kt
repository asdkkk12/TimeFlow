package app.timeflow.timeflow

import org.json.JSONObject
import java.time.LocalDate
import java.time.LocalDateTime

/** Pure calendar rules: local wall-clock values intentionally have no UTC offset. */
object OccurrenceRules {
    fun occurs(e: JSONObject, date: LocalDate): Boolean {
        if (e.isNull("date")) return false
        val first = LocalDate.parse(e.getString("date"))
        if (date < first || (!e.isNull("until") && date > LocalDate.parse(e.getString("until")))) return false
        return when (e.getString("repeat")) {
            "none" -> date == first
            "daily" -> true
            "weekdays" -> date.dayOfWeek.value <= 5
            "weekly" -> (0 until e.getJSONArray("weekdays").length()).any { e.getJSONArray("weekdays").getInt(it) == date.dayOfWeek.value }
            else -> false
        }
    }
    fun key(e: JSONObject, date: LocalDate) = e.getString("id") + if (e.getString("repeat") == "none") "" else "@$date"
    fun time(e: JSONObject, date: LocalDate): LocalDateTime? {
        if (e.isNull("minute") || e.isNull("reminder")) return null
        return date.atStartOfDay().plusMinutes(e.getLong("minute") - e.getLong("reminder"))
    }
    fun fingerprint(e: JSONObject, date: LocalDate): String = listOf(e.optString("title"), e.optString("notes"), date.toString(), e.opt("minute"), e.opt("reminder"), e.optString("kind")).joinToString("\u001f")
}
