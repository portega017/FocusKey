package com.focuskey.app.data

import java.time.DayOfWeek
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

/** Day of the week used by schedules. Ordered Monday first, as shown in the UI. */
enum class Weekday(val dayOfWeek: DayOfWeek, val shortName: String, val initial: String) {
    MONDAY(DayOfWeek.MONDAY, "Lun", "L"),
    TUESDAY(DayOfWeek.TUESDAY, "Mar", "M"),
    WEDNESDAY(DayOfWeek.WEDNESDAY, "Mié", "X"),
    THURSDAY(DayOfWeek.THURSDAY, "Jue", "J"),
    FRIDAY(DayOfWeek.FRIDAY, "Vie", "V"),
    SATURDAY(DayOfWeek.SATURDAY, "Sáb", "S"),
    SUNDAY(DayOfWeek.SUNDAY, "Dom", "D");

    companion object {
        val WORKDAYS = setOf(MONDAY, TUESDAY, WEDNESDAY, THURSDAY, FRIDAY)

        fun of(date: LocalDate): Weekday = entries.first { it.dayOfWeek == date.dayOfWeek }
    }
}

/** A weekly interval during which the selected content is blocked. Times are minutes since midnight. */
data class Schedule(
    val id: String = UUID.randomUUID().toString(),
    val name: String = "",
    val startMinutes: Int,
    val endMinutes: Int,
    val repeats: Set<Weekday>,
    val isEnabled: Boolean = true,
) {
    val startTime: LocalTime get() = LocalTime.of(startMinutes / 60, startMinutes % 60)
    val endTime: LocalTime get() = LocalTime.of(endMinutes / 60, endMinutes % 60)

    /** e.g. 23:00–07:00 ends the next day. */
    val crossesMidnight: Boolean get() = startMinutes > endMinutes

    val displayName: String get() = name.ifEmpty { "Horario de concentración" }

    /** True while the schedule's interval is running at [now]. */
    fun isActive(now: LocalDateTime = LocalDateTime.now()): Boolean {
        if (!isEnabled || startMinutes == endMinutes) return false
        val current = now.hour * 60 + now.minute
        val today = Weekday.of(now.toLocalDate())

        if (startMinutes < endMinutes) {
            return today in repeats && current >= startMinutes && current < endMinutes
        }
        if (current >= startMinutes) return today in repeats
        // After midnight: the interval belongs to the previous day.
        return current < endMinutes && Weekday.of(now.toLocalDate().minusDays(1)) in repeats
    }

    /** Next occurrence of the end time after [now] (the end of the running interval). */
    fun currentIntervalEnd(now: LocalDateTime = LocalDateTime.now()): LocalDateTime {
        val todayEnd = now.toLocalDate().atTime(endTime)
        return if (todayEnd.isAfter(now)) todayEnd else todayEnd.plusDays(1)
    }

    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("name", name)
        .put("startMinutes", startMinutes)
        .put("endMinutes", endMinutes)
        .put("repeats", JSONArray(repeats.map { it.name }))
        .put("isEnabled", isEnabled)

    companion object {
        fun fromJson(json: JSONObject): Schedule {
            val repeatsJson = json.getJSONArray("repeats")
            val repeats = (0 until repeatsJson.length())
                .mapNotNull { runCatching { Weekday.valueOf(repeatsJson.getString(it)) }.getOrNull() }
                .toSet()
            return Schedule(
                id = json.getString("id"),
                name = json.optString("name", ""),
                startMinutes = json.getInt("startMinutes"),
                endMinutes = json.getInt("endMinutes"),
                repeats = repeats,
                isEnabled = json.optBoolean("isEnabled", true),
            )
        }
    }
}
