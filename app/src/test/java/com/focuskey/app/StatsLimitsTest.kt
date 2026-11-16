package com.focuskey.app

import com.focuskey.app.data.BlockRecord
import com.focuskey.app.data.LimitDay
import com.focuskey.app.data.UsageLimit
import com.focuskey.app.logic.DayCounter
import com.focuskey.app.logic.FocusEngine
import com.focuskey.app.logic.WeekStats
import com.focuskey.app.logic.YearStats
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Daily limits and statistics, same cases as the iOS tests. */
class StatsLimitsTest {
    private val zone = ZoneId.systemDefault()
    private fun millis(day: Int, hour: Int, minute: Int = 0) =
        LocalDateTime.of(2026, 11, day, hour, minute).atZone(zone).toInstant().toEpochMilli()
    private fun day(day: Int) = LocalDate.of(2026, 11, day)
    private fun record(start: Long, end: Long?) = BlockRecord(kind = BlockRecord.Kind.MANUAL, title = "", sourceId = "s$start", start = start, end = end)

    @Test fun overlappingBlocksCountOnceAndSplitAtMidnight() {
        val counter = DayCounter(
            listOf(record(millis(4, 10), millis(4, 12)), record(millis(4, 11), millis(4, 13)), record(millis(5, 23), millis(6, 1))),
            now = millis(8, 12),
        )
        assertEquals(180, counter.minutes(day(4)))
        assertEquals(60, counter.minutes(day(5)))
        assertEquals(60, counter.minutes(day(6)))
    }

    @Test fun runningBlockCountsUntilNowAndArchiveWinsBeforeBoundary() {
        val counter = DayCounter(
            listOf(record(millis(1, 10), millis(1, 11)), record(millis(8, 10), null)),
            archive = mapOf("2026-11-01" to 30),
            archivedUntil = day(3),
            now = millis(8, 10, 45),
        )
        assertEquals(30, counter.minutes(day(1)))
        assertEquals(45, counter.minutes(day(8)))
        assertEquals(listOf(2026), counter.years(day(8)))
    }

    @Test fun streakAndYearSummary() {
        val counter = DayCounter(
            listOf(record(millis(6, 10), millis(6, 11)), record(millis(7, 10), millis(7, 12)), record(millis(8, 10), millis(8, 10, 30))),
            archive = mapOf("2026-01-15" to 60),
            archivedUntil = day(1),
            now = millis(8, 12),
        )
        val week = WeekStats(counter, day(8))
        assertEquals(3, week.streak)
        assertEquals(30, week.today)
        assertEquals(35, week.calendar.size)

        val year = YearStats(2026, counter, day(8))
        assertEquals(365, year.days.size)
        assertEquals(60 + 60 + 120 + 30, year.total)
        assertEquals(4, year.activeDays)
        assertEquals(60, year.months[0])
        assertEquals(120, year.bestDay?.minutes)
        assertEquals(270 / 312, year.dailyAverage)
    }

    @Test fun limitBlocksWhenReachedUntilExtraTimeIsUsed() {
        val today = day(8)
        assertFalse(FocusEngine.isLimitBlocking(null, 100, today))
        assertTrue(FocusEngine.isLimitBlocking(LimitDay(today, reached = true), 60, today))
        assertFalse("Yesterday doesn't count", FocusEngine.isLimitBlocking(LimitDay(day(7), reached = true), 60, today))
        val extended = LimitDay(today, reached = true, extendedUntil = 75)
        assertFalse(FocusEngine.isLimitBlocking(extended, 70, today))
        assertTrue(FocusEngine.isLimitBlocking(extended, 75, today))
    }

    @Test fun limitWarningLeadAndWeakeningRules() {
        assertNull(UsageLimit(profileId = "p", minutes = 2).warningLeadMinutes)
        assertEquals(1, UsageLimit(profileId = "p", minutes = 10).warningLeadMinutes)
        assertEquals(5, UsageLimit(profileId = "p", minutes = 30).warningLeadMinutes)

        val limit = UsageLimit(profileId = "p", minutes = 30)
        assertTrue(limit.isWeakenedBy(limit.copy(minutes = 45)))
        assertTrue(limit.isWeakenedBy(limit.copy(isEnabled = false)))
        assertTrue(limit.isWeakenedBy(limit.copy(profileId = "q")))
        assertFalse(limit.isWeakenedBy(limit.copy(minutes = 15, name = "Menos")))
    }

    @Test fun limitsAndRecordsRoundTrip() {
        val limit = UsageLimit(name = "Social", profileId = "p", minutes = 45)
        assertEquals(limit, UsageLimit.fromJson(limit.toJson()))
        val dayState = LimitDay(day(8), reached = true, extendedUntil = 50, warned = true)
        assertEquals(dayState, LimitDay.fromJson(dayState.toJson()))
        val rec = record(millis(8, 9), millis(8, 10))
        assertEquals(rec, BlockRecord.fromJson(rec.toJson()))
        assertEquals(BlockRecord.Kind.MANUAL, BlockRecord.fromJson(JSONObject("""{"id":"a","kind":"FUTURE","sourceId":"s","start":1}""")).kind)
    }
}
