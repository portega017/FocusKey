package com.focuskey.app.logic

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Process
import com.focuskey.app.data.Selection
import java.time.LocalDate
import java.time.ZoneId

/**
 * Real app usage from UsageStatsManager (needs the "Usage access" special permission).
 * Websites can't be measured per domain, so limits and reports count apps and categories only.
 */
object UsageTracker {

    fun hasAccess(context: Context): Boolean {
        val ops = context.getSystemService(AppOpsManager::class.java)
        @Suppress("DEPRECATION")
        val mode = ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /** Foreground milliseconds per package between [from] and [to]. */
    fun usageByPackage(context: Context, from: Long, to: Long): Map<String, Long> {
        if (!hasAccess(context)) return emptyMap()
        val manager = context.getSystemService(UsageStatsManager::class.java)
        val events = manager.queryEvents(from, to)
        val event = UsageEvents.Event()
        val resumed = mutableMapOf<String, Long>()
        val totals = mutableMapOf<String, Long>()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val pkg = event.packageName ?: continue
            when (event.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED -> resumed.putIfAbsent(pkg, event.timeStamp)
                UsageEvents.Event.ACTIVITY_PAUSED, UsageEvents.Event.ACTIVITY_STOPPED -> {
                    val start = resumed.remove(pkg) ?: continue
                    totals[pkg] = (totals[pkg] ?: 0) + (event.timeStamp - start)
                }
            }
        }
        // Still in the foreground.
        resumed.forEach { (pkg, start) -> totals[pkg] = (totals[pkg] ?: 0) + (to - start) }
        return totals
    }

    /** Whether [pkg] is covered by [selection] (directly or through its category). */
    fun matches(context: Context, selection: Selection, pkg: String): Boolean {
        if (pkg in selection.apps) return true
        if (selection.categories.isEmpty()) return false
        val category = try {
            context.packageManager.getApplicationInfo(pkg, 0).category
        } catch (e: PackageManager.NameNotFoundException) {
            ApplicationInfo.CATEGORY_UNDEFINED
        }
        return category in selection.categories
    }

    /** Minutes the selection's apps have been used today. */
    fun minutesToday(context: Context, selection: Selection, now: Long = System.currentTimeMillis()): Int {
        val start = LocalDate.now().atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
        val millis = usageByPackage(context, start, now).filterKeys { matches(context, selection, it) }.values.sum()
        return (millis / 60_000).toInt()
    }

    data class AppUsage(val packageName: String, val label: String, val millis: Long)
    data class Report(val days: List<Pair<LocalDate, Long>>, val apps: List<AppUsage>)

    /** Last 7 days of usage of the selection's apps, oldest first, plus the most used apps. */
    fun weekReport(context: Context, selection: Selection, now: Long = System.currentTimeMillis()): Report {
        val zone = ZoneId.systemDefault()
        val today = LocalDate.now()
        val perApp = mutableMapOf<String, Long>()
        val days = (6 downTo 0).map { offset ->
            val day = today.minusDays(offset.toLong())
            val from = day.atStartOfDay(zone).toInstant().toEpochMilli()
            val to = minOf(day.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli(), now)
            val usage = usageByPackage(context, from, to).filterKeys { matches(context, selection, it) }
            usage.forEach { (pkg, ms) -> perApp[pkg] = (perApp[pkg] ?: 0) + ms }
            day to usage.values.sum()
        }
        val apps = perApp.filterValues { it >= 60_000 }.entries.sortedByDescending { it.value }.take(10).map { (pkg, ms) ->
            val label = try {
                context.packageManager.getApplicationLabel(context.packageManager.getApplicationInfo(pkg, 0)).toString()
            } catch (e: PackageManager.NameNotFoundException) {
                pkg
            }
            AppUsage(pkg, label, ms)
        }
        return Report(days, apps)
    }
}
