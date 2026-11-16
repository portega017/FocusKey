package com.focuskey.app

import com.focuskey.app.data.PomodoroPlan
import com.focuskey.app.data.Profile
import com.focuskey.app.data.Schedule
import com.focuskey.app.data.Selection
import com.focuskey.app.data.SessionPreset
import com.focuskey.app.data.Weekday
import java.time.LocalDate
import java.time.LocalDateTime
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Same cases as the iOS tests: schedules, pauses, pomodoro and strict-mode rules. */
class RulesTest {
    // November 2026: the 6th is a Friday, the 7th a Saturday.
    private fun at(day: Int, hour: Int, minute: Int = 0) = LocalDateTime.of(2026, 11, day, hour, minute)
    private fun day(day: Int) = LocalDate.of(2026, 11, day)

    private val workday = Schedule(startMinutes = 9 * 60, endMinutes = 17 * 60, repeats = Weekday.WORKDAYS, profileId = "p")

    @Test fun sameDayInterval() {
        assertTrue(workday.isActive(at(6, 9)))
        assertFalse(workday.isActive(at(6, 17)))
        assertFalse(workday.isActive(at(7, 12)))
    }

    @Test fun overnightBelongsToStartDayAndPausesCoverIt() {
        val night = Schedule(startMinutes = 23 * 60, endMinutes = 7 * 60, repeats = setOf(Weekday.FRIDAY, Weekday.SATURDAY))
        assertTrue(night.isActive(at(7, 6)))
        val paused = night.copy(pausedDays = setOf(day(6)))
        assertFalse(paused.isActive(at(6, 23, 30)))
        assertFalse(paused.isActive(at(7, 6)))
        assertTrue(paused.isActive(at(7, 23, 30)))
    }

    @Test fun upcomingDaysSkipStartedIntervals() {
        assertEquals(listOf(day(6), day(9)), workday.upcomingDays(at(5, 10), limit = 2))
        assertEquals(listOf(day(5)), workday.upcomingDays(at(5, 8), limit = 1))
    }

    @Test fun scheduleWeakeningRules() {
        assertTrue(workday.isWeakenedBy(workday.copy(isEnabled = false)))
        assertTrue(workday.isWeakenedBy(workday.copy(repeats = Weekday.WORKDAYS - Weekday.FRIDAY)))
        assertTrue(workday.isWeakenedBy(workday.copy(startMinutes = 10 * 60)))
        assertTrue(workday.isWeakenedBy(workday.copy(profileId = "other")))
        assertTrue(workday.isWeakenedBy(workday.copy(pausedDays = setOf(day(9)))))
        assertFalse(workday.isWeakenedBy(workday.copy(startMinutes = 8 * 60, endMinutes = 1 * 60, name = "x")))
        val disabled = workday.copy(isEnabled = false)
        assertFalse(disabled.isWeakenedBy(disabled.copy(repeats = setOf(Weekday.MONDAY))))
    }

    @Test fun profileWeakeningRules() {
        val profile = Profile(name = "Social", selection = Selection(apps = setOf("a", "b")))
        assertTrue(profile.isWeakenedBy(profile.copy(selection = Selection(apps = setOf("a")))))
        assertFalse(profile.isWeakenedBy(profile.copy(name = "Redes", selection = Selection(apps = setOf("a", "b", "c")))))
    }

    @Test fun pomodoroPhasesAndSkippingBreaks() {
        val start = 1_000_000_000L
        val m = PomodoroPlan.MINUTE
        val plan = PomodoroPlan("p", start, 25, 5, 3)
        assertEquals(PomodoroPlan.Phase.Focus(0, start, start + 25 * m), plan.phase(start))
        assertEquals(PomodoroPlan.Phase.Rest(0, start + 25 * m, start + 30 * m), plan.phase(start + 25 * m))
        assertEquals(PomodoroPlan.Phase.Finished, plan.phase(plan.end))
        assertEquals(start + 85 * m, plan.end)

        val shifted = plan.skippingBreak(start + 27 * m)!!
        assertEquals(PomodoroPlan.Phase.Focus(1, start + 27 * m, start + 52 * m), shifted.phase(start + 27 * m))
        assertNull(plan.skippingBreak(start + 10 * m))
    }

    @Test fun jsonRoundTripsAndOldData() {
        val schedule = workday.copy(pausedDays = setOf(day(9)))
        assertEquals(schedule, Schedule.fromJson(schedule.toJson()))
        val legacy = JSONObject("""{"id":"x","startMinutes":540,"endMinutes":600,"repeats":["MONDAY"],"isEnabled":true}""")
        val old = Schedule.fromJson(legacy)
        assertNull(old.profileId)
        assertTrue(old.pausedDays.isEmpty())

        val preset = SessionPreset(profileId = "p", pomodoro = SessionPreset.PomodoroSettings(50, 10, 3))
        assertEquals(preset, SessionPreset.fromJson(preset.toJson()))
        assertEquals("3×50", preset.pomodoroText)

        val profile = Profile(name = "Social", selection = Selection(setOf("a"), setOf(1), setOf("x.com")))
        assertEquals(profile, Profile.fromJson(profile.toJson()))
    }
}
