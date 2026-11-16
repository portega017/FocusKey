package com.focuskey.app.data

import java.time.DayOfWeek
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

/** Day of the week used by schedules, Monday first as shown in the UI. Labels come from resources. */
enum class Weekday(val dayOfWeek: DayOfWeek) {
    MONDAY(DayOfWeek.MONDAY),
    TUESDAY(DayOfWeek.TUESDAY),
    WEDNESDAY(DayOfWeek.WEDNESDAY),
    THURSDAY(DayOfWeek.THURSDAY),
    FRIDAY(DayOfWeek.FRIDAY),
    SATURDAY(DayOfWeek.SATURDAY),
    SUNDAY(DayOfWeek.SUNDAY);

    companion object {
        val WORKDAYS = setOf(MONDAY, TUESDAY, WEDNESDAY, THURSDAY, FRIDAY)
        val WEEKEND = setOf(SATURDAY, SUNDAY)

        fun of(date: LocalDate): Weekday = entries.first { it.dayOfWeek == date.dayOfWeek }
    }
}

/**
 * A weekly interval during which a profile is blocked. Times are minutes since midnight;
 * an interval whose end is before its start ends the next day.
 */
data class Schedule(
    val id: String = UUID.randomUUID().toString(),
    val name: String = "",
    val startMinutes: Int,
    val endMinutes: Int,
    val repeats: Set<Weekday>,
    val isEnabled: Boolean = true,
    /** Profile to block. Null (schedules from older versions) means the first profile. */
    val profileId: String? = null,
    /** Days whose interval is skipped: the day the interval *starts* on. */
    val pausedDays: Set<LocalDate> = emptySet(),
) {
    val startTime: LocalTime get() = LocalTime.of(startMinutes / 60, startMinutes % 60)
    val endTime: LocalTime get() = LocalTime.of(endMinutes / 60, endMinutes % 60)

    val crossesMidnight: Boolean get() = startMinutes > endMinutes

    /** Whether an interval starts on [day]: a repeat day that isn't paused. */
    fun runs(day: LocalDate): Boolean = Weekday.of(day) in repeats && day !in pausedDays

    /** True while the interval is running at [now] (ignores NFC skips, honours pauses). */
    fun isActive(now: LocalDateTime = LocalDateTime.now()): Boolean {
        if (!isEnabled || startMinutes == endMinutes) return false
        val current = now.hour * 60 + now.minute
        val today = now.toLocalDate()

        if (startMinutes < endMinutes) {
            return runs(today) && current >= startMinutes && current < endMinutes
        }
        if (current >= startMinutes) return runs(today)
        // After midnight: the interval belongs to the previous day.
        return current < endMinutes && runs(today.minusDays(1))
    }

    /** Next occurrence of the end time after [now] (the end of the running interval). */
    fun currentIntervalEnd(now: LocalDateTime = LocalDateTime.now()): LocalDateTime {
        val todayEnd = now.toLocalDate().atTime(endTime)
        return if (todayEnd.isAfter(now)) todayEnd else todayEnd.plusDays(1)
    }

    fun intervalStart(day: LocalDate): LocalDateTime = day.atTime(startTime)

    fun intervalEnd(day: LocalDate): LocalDateTime =
        if (crossesMidnight || startMinutes == endMinutes) day.plusDays(1).atTime(endTime) else day.atTime(endTime)

    /** Next days (up to [limit]) whose interval hasn't started yet and could be paused. */
    fun upcomingDays(now: LocalDateTime = LocalDateTime.now(), limit: Int = 14): List<LocalDate> =
        (0L until 60L).asSequence()
            .map { now.toLocalDate().plusDays(it) }
            .filter { Weekday.of(it) in repeats && intervalStart(it).isAfter(now) }
            .take(limit)
            .toList()

    /** Pauses whose interval hasn't ended yet, oldest first. */
    fun activePauses(now: LocalDateTime = LocalDateTime.now()): List<LocalDate> =
        pausedDays.filter { intervalEnd(it).isAfter(now) }.sorted()

    /**
     * Whether replacing this schedule with [new] could block less. A disabled schedule blocks
     * nothing, so editing it is free.
     */
    fun isWeakenedBy(new: Schedule): Boolean {
        if (!isEnabled) return false
        if (!new.isEnabled) return true
        if (new.profileId != profileId) return true
        if (!new.repeats.containsAll(repeats)) return true
        if (!pausedDays.containsAll(new.pausedDays)) return true
        return !new.covers(this)
    }

    /** Whether this interval contains [other]'s (both measured from the same start day). */
    private fun covers(other: Schedule): Boolean {
        fun span(s: Schedule): Pair<Int, Int> {
            val end = if (s.endMinutes <= s.startMinutes) s.endMinutes + 24 * 60 else s.endMinutes
            return s.startMinutes to end
        }
        val (start, end) = span(this)
        val (otherStart, otherEnd) = span(other)
        return start <= otherStart && end >= otherEnd
    }

    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("name", name)
        .put("startMinutes", startMinutes)
        .put("endMinutes", endMinutes)
        .put("repeats", JSONArray(repeats.map { it.name }))
        .put("isEnabled", isEnabled)
        .apply {
            profileId?.let { put("profileId", it) }
            if (pausedDays.isNotEmpty()) put("pausedDays", JSONArray(pausedDays.map { it.toString() }))
        }

    companion object {
        fun fromJson(json: JSONObject): Schedule {
            val repeats = json.getJSONArray("repeats").strings()
                .mapNotNull { runCatching { Weekday.valueOf(it) }.getOrNull() }
                .toSet()
            return Schedule(
                id = json.getString("id"),
                name = json.optString("name", ""),
                startMinutes = json.getInt("startMinutes"),
                endMinutes = json.getInt("endMinutes"),
                repeats = repeats,
                isEnabled = json.optBoolean("isEnabled", true),
                profileId = json.optString("profileId", "").ifEmpty { null },
                pausedDays = json.optJSONArray("pausedDays").strings()
                    .mapNotNull { runCatching { LocalDate.parse(it) }.getOrNull() }
                    .toSet(),
            )
        }
    }
}
