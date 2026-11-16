package com.focuskey.app.logic

import com.focuskey.app.data.BlockRecord
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters

/**
 * Minutes blocked on any day: from the archive for days before [archivedUntil], otherwise from
 * the records with overlapping blocks merged. Same as FocusStats.DayCounter on iOS.
 */
class DayCounter(
    records: List<BlockRecord>,
    private val archive: Map<String, Int> = emptyMap(),
    private val archivedUntil: LocalDate? = null,
    now: Long = System.currentTimeMillis(),
    private val zone: ZoneId = ZoneId.systemDefault(),
) {
    private val intervals: List<Pair<Long, Long>> = merged(records.map { it.start to minOf(it.end ?: now, now) })

    fun minutes(day: LocalDate): Int {
        if (archivedUntil != null && day < archivedUntil) return archive[day.toString()] ?: 0
        val start = day.atStartOfDay(zone).toInstant().toEpochMilli()
        val end = day.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
        val millis = intervals.sumOf { (from, to) -> (minOf(to, end) - maxOf(from, start)).coerceAtLeast(0) }
        return (millis / 60_000).toInt()
    }

    /** Years with any recorded focus, plus the current one. */
    fun years(today: LocalDate): List<Int> =
        (archive.keys.mapNotNull { it.take(4).toIntOrNull() } +
            intervals.map { Instant.ofEpochMilli(it.first).atZone(zone).year } +
            today.year).distinct().sorted()

    companion object {
        /** Overlapping blocks (a schedule during a manual lock) count once. */
        fun merged(intervals: List<Pair<Long, Long>>): List<Pair<Long, Long>> {
            val result = mutableListOf<Pair<Long, Long>>()
            for (interval in intervals.filter { it.second > it.first }.sortedBy { it.first }) {
                val last = result.lastOrNull()
                if (last != null && interval.first <= last.second) {
                    result[result.lastIndex] = last.first to maxOf(last.second, interval.second)
                } else {
                    result += interval
                }
            }
            return result
        }
    }
}

data class DayMinutes(val date: LocalDate, val minutes: Int)

/** Today, last 7 days, streak and the 5-week calendar (Monday first). */
class WeekStats(counter: DayCounter, today: LocalDate) {
    val week: List<DayMinutes> = (6 downTo 0).map { today.minusDays(it.toLong()) }.map { DayMinutes(it, counter.minutes(it)) }
    val today: Int = counter.minutes(today)
    val weekTotal: Int = week.sumOf { it.minutes }
    val calendar: List<DayMinutes>
    val streak: Int

    init {
        val first = today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY)).minusWeeks(4)
        calendar = (0L until 35L).map { first.plusDays(it) }.map { DayMinutes(it, if (it > today) 0 else counter.minutes(it)) }
        // Consecutive days with at least one minute; today counts only once it has some.
        var day = if (this.today > 0) today else today.minusDays(1)
        var count = 0
        while (counter.minutes(day) > 0 && count < 365) {
            count++
            day = day.minusDays(1)
        }
        streak = count
    }
}

/** Focus time over one calendar year. */
class YearStats(val year: Int, counter: DayCounter, today: LocalDate) {
    val days: List<DayMinutes>
    val months: List<Int>
    val total: Int
    val activeDays: Int
    val bestDay: DayMinutes?
    val dailyAverage: Int

    init {
        val start = LocalDate.of(year, 1, 1)
        days = (0 until start.lengthOfYear()).map { start.plusDays(it.toLong()) }
            .map { DayMinutes(it, if (it > today) 0 else counter.minutes(it)) }
        months = (1..12).map { month -> days.filter { it.date.monthValue == month }.sumOf { it.minutes } }
        total = days.sumOf { it.minutes }
        activeDays = days.count { it.minutes > 0 }
        bestDay = days.maxByOrNull { it.minutes }?.takeIf { it.minutes > 0 }
        val elapsed = when {
            today.year > year -> days.size
            today.year < year -> 0
            else -> today.dayOfYear
        }
        dailyAverage = if (elapsed == 0) 0 else total / elapsed
    }
}
