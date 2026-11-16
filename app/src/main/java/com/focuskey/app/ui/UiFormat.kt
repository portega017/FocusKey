package com.focuskey.app.ui

import android.content.Context
import android.text.format.DateFormat
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsRun
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material.icons.filled.Work
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import com.focuskey.app.R
import com.focuskey.app.data.Profile
import com.focuskey.app.data.SessionPreset
import com.focuskey.app.data.Weekday
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** "45 min", "1 h", "1 h 30 min" (same units in English and Spanish). */
fun formatMinutes(@Suppress("UNUSED_PARAMETER") context: Context, minutes: Int): String {
    val hours = minutes / 60
    val rest = minutes % 60
    return when {
        hours == 0 -> "$rest min"
        rest == 0 -> "$hours h"
        else -> "$hours h $rest min"
    }
}

/** Clock time of an epoch-millis moment, following the phone's 12/24 h setting. */
fun formatClock(context: Context, millis: Long): String =
    formatTime(context, Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()).toLocalTime())

fun formatTime(context: Context, time: LocalTime): String {
    val is24 = DateFormat.is24HourFormat(context)
    return time.format(DateTimeFormatter.ofPattern(if (is24) "HH:mm" else "h:mm a", Locale.getDefault()))
}

/** "Friday 20 November" in the phone's language. */
fun formatDay(day: LocalDate): String =
    day.format(DateTimeFormatter.ofPattern("EEEE d MMMM", Locale.getDefault()))
        .replaceFirstChar { it.titlecase(Locale.getDefault()) }

/** "1 h" for a session, "4×25" for a pomodoro. */
fun presetDuration(context: Context, preset: SessionPreset): String =
    preset.pomodoroText ?: formatMinutes(context, preset.minutes)

fun presetName(preset: SessionPreset, profile: Profile?): String =
    preset.name.ifEmpty { profile?.name.orEmpty() }

fun weekdayShort(context: Context, day: Weekday): String =
    context.resources.getStringArray(R.array.weekdays_short)[day.ordinal]

fun weekdayInitial(context: Context, day: Weekday): String =
    context.resources.getStringArray(R.array.weekdays_initial)[day.ordinal]

/** "Monday to Friday", "Every day", "Weekends" or "Mon, Wed, Fri". */
fun daysSummary(context: Context, repeats: Set<Weekday>): String = when (repeats) {
    Weekday.entries.toSet() -> context.getString(R.string.days_every)
    Weekday.WORKDAYS -> context.getString(R.string.days_workdays)
    Weekday.WEEKEND -> context.getString(R.string.days_weekend)
    emptySet<Weekday>() -> context.getString(R.string.days_none)
    else -> Weekday.entries.filter { it in repeats }.joinToString(", ") { weekdayShort(context, it) }
}

/** Same palette as iOS (system colors). */
fun profileColor(name: String): Color = when (name) {
    "blue" -> Color(0xFF007AFF)
    "teal" -> Color(0xFF30B0C7)
    "green" -> Color(0xFF34C759)
    "orange" -> Color(0xFFFF9500)
    "red" -> Color(0xFFFF3B30)
    "pink" -> Color(0xFFFF2D55)
    "purple" -> Color(0xFFAF52DE)
    "brown" -> Color(0xFFA2845E)
    "gray" -> Color(0xFF8E8E93)
    else -> Color(0xFF5856D6)
}

fun profileIcon(name: String): ImageVector = when (name) {
    "work" -> Icons.Filled.Work
    "book" -> Icons.AutoMirrored.Filled.MenuBook
    "bedtime" -> Icons.Filled.Bedtime
    "games" -> Icons.Filled.SportsEsports
    "chat" -> Icons.AutoMirrored.Filled.Chat
    "tv" -> Icons.Filled.Tv
    "cart" -> Icons.Filled.ShoppingCart
    "run" -> Icons.AutoMirrored.Filled.DirectionsRun
    "restaurant" -> Icons.Filled.Restaurant
    "school" -> Icons.Filled.School
    "home" -> Icons.Filled.Home
    else -> Icons.Filled.Shield
}

/** "3 apps · 1 category · 2 sites" or "Nothing selected". */
fun selectionSummary(context: Context, profile: Profile?): String {
    val selection = profile?.selection ?: return ""
    val res = context.resources
    val parts = buildList {
        if (selection.apps.isNotEmpty()) add(res.getQuantityString(R.plurals.apps, selection.apps.size, selection.apps.size))
        if (selection.categories.isNotEmpty()) add(res.getQuantityString(R.plurals.categories, selection.categories.size, selection.categories.size))
        if (selection.domains.isNotEmpty()) add(res.getQuantityString(R.plurals.sites, selection.domains.size, selection.domains.size))
    }
    return if (parts.isEmpty()) context.getString(R.string.nothing_selected) else parts.joinToString(" · ")
}
