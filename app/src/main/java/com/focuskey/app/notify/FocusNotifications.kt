package com.focuskey.app.notify

import android.Manifest
import android.annotation.SuppressLint
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.focuskey.app.R
import com.focuskey.app.data.FocusStore
import com.focuskey.app.data.PomodoroPlan
import com.focuskey.app.data.UsageLimit
import com.focuskey.app.logic.FocusEngine
import com.focuskey.app.ui.MainActivity
import com.focuskey.app.ui.formatMinutes

/**
 * Ongoing countdown notification for timed sessions and pomodoro phases (Android equivalent of
 * the iOS Live Activity), plus the pomodoro phase-change alerts.
 */
object FocusNotifications {
    private const val CHANNEL_LIVE = "live"
    private const val CHANNEL_POMODORO = "pomodoro"
    private const val CHANNEL_LIMITS = "limits"
    private const val ID_LIMIT_BASE = 5000
    private const val ID_LIVE = 1
    private const val ID_PHASE = 2
    private const val ALARM_BASE = 1000

    fun ensureChannels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_LIVE, context.getString(R.string.channel_live), NotificationManager.IMPORTANCE_LOW)
                .apply { setShowBadge(false) }
        )
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_POMODORO, context.getString(R.string.channel_pomodoro), NotificationManager.IMPORTANCE_DEFAULT)
        )
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_LIMITS, context.getString(R.string.channel_limits), NotificationManager.IMPORTANCE_DEFAULT)
        )
    }

    private fun canNotify(context: Context): Boolean =
        Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    private fun openApp(context: Context): PendingIntent = PendingIntent.getActivity(
        context, 0,
        Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
    )

    /** Shows, updates or removes the countdown so it matches what is running now. */
    @SuppressLint("MissingPermission") // canNotify() is checked before notifying.
    fun refreshLive(context: Context, now: Long = System.currentTimeMillis()) {
        val store = FocusStore(context)
        val manager = NotificationManagerCompat.from(context)
        val content = if (store.liveNotification) liveContent(context, store, now) else null
        if (content == null || !canNotify(context)) {
            manager.cancel(ID_LIVE)
            return
        }
        ensureChannels(context)
        val (title, text, end) = content
        val notification = NotificationCompat.Builder(context, CHANNEL_LIVE)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setShowWhen(true)
            .setWhen(end)
            .setUsesChronometer(true)
            .setChronometerCountDown(true)
            // Goes away by itself at the end, even if nothing else runs then.
            .setTimeoutAfter((end - now).coerceAtLeast(1))
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setContentIntent(openApp(context))
            .build()
        runCatching { manager.notify(ID_LIVE, notification) }
    }

    private fun liveContent(context: Context, store: FocusStore, now: Long): Triple<String, String, Long>? {
        val plan = store.activePomodoro(now)
        if (plan != null) {
            val profile = store.profile(plan.profileId)?.name.orEmpty()
            return when (val phase = plan.phase(now)) {
                is PomodoroPlan.Phase.Focus -> Triple(
                    context.getString(R.string.live_focus),
                    context.getString(R.string.cycle_of, phase.cycle + 1, plan.cycles) + " · " + profile,
                    phase.end,
                )
                is PomodoroPlan.Phase.Rest -> Triple(
                    context.getString(R.string.live_break),
                    context.getString(R.string.live_next, context.getString(R.string.cycle_of, phase.cycle + 2, plan.cycles)),
                    phase.end,
                )
                PomodoroPlan.Phase.Finished -> null
            }
        }
        if (store.isLocked && store.sessionEnd > now) {
            val profile = store.profile(store.manualProfileId)?.name.orEmpty()
            return Triple(context.getString(R.string.live_session), profile, store.sessionEnd)
        }
        return null
    }

    // MARK: Pomodoro phase alarms

    /** One alarm per phase change; the receiver syncs the lock and posts the alert. */
    fun schedulePomodoro(context: Context, plan: PomodoroPlan, now: Long = System.currentTimeMillis()) {
        cancelPomodoro(context)
        val alarms = context.getSystemService(AlarmManager::class.java)
        var code = ALARM_BASE
        for (cycle in 0 until plan.cycles) {
            val boundaries = buildList {
                add(Triple(PhaseReceiver.KIND_REST, cycle, plan.blockEnd(cycle)))
                if (cycle < plan.cycles - 1) add(Triple(PhaseReceiver.KIND_FOCUS, cycle + 1, plan.blockStart(cycle + 1)))
            }
            for ((kind, phaseCycle, at) in boundaries) {
                val isLast = kind == PhaseReceiver.KIND_REST && phaseCycle == plan.cycles - 1
                if (at > now) {
                    val intent = Intent(context, PhaseReceiver::class.java)
                        .putExtra(PhaseReceiver.EXTRA_KIND, if (isLast) PhaseReceiver.KIND_DONE else kind)
                        .putExtra(PhaseReceiver.EXTRA_CYCLE, phaseCycle)
                    val pending = PendingIntent.getBroadcast(
                        context, code, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                    )
                    // Inexact but allowed while idle; blocking itself follows the clock exactly.
                    alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
                }
                code++
            }
        }
    }

    fun cancelPomodoro(context: Context) {
        val alarms = context.getSystemService(AlarmManager::class.java)
        for (code in ALARM_BASE until ALARM_BASE + PomodoroPlan.CYCLE_RANGE.last * 2) {
            val pending = PendingIntent.getBroadcast(
                context, code, Intent(context, PhaseReceiver::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_NO_CREATE
            ) ?: continue
            alarms.cancel(pending)
            pending.cancel()
        }
    }

    /** "Almost at your limit": a few minutes of a daily limit left. */
    @SuppressLint("MissingPermission") // canNotify() is checked first.
    fun limitWarning(context: Context, limit: UsageLimit, minutesLeft: Int) {
        if (!canNotify(context) || !FocusStore(context).limitWarnings) return
        ensureChannels(context)
        val name = limit.name.ifEmpty { context.getString(R.string.limit_default_name) }
        val notification = NotificationCompat.Builder(context, CHANNEL_LIMITS)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(context.getString(R.string.limit_warning_title))
            .setContentText(context.getString(R.string.limit_warning_text, formatMinutes(context, minutesLeft), name))
            .setAutoCancel(true)
            .setContentIntent(openApp(context))
            .build()
        runCatching { NotificationManagerCompat.from(context).notify(ID_LIMIT_BASE + limit.id.hashCode() % 1000, notification) }
    }

    @SuppressLint("MissingPermission") // canNotify() is checked first.
    fun postPhase(context: Context, kind: String, cycle: Int) {
        if (!canNotify(context)) return
        val store = FocusStore(context)
        val plan = store.pomodoro
        val (title, text) = when (kind) {
            PhaseReceiver.KIND_REST -> context.getString(R.string.phase_break_title) to
                context.getString(R.string.phase_break_text, formatMinutes(context, plan?.breakMinutes ?: 0))
            PhaseReceiver.KIND_FOCUS -> context.getString(R.string.phase_focus_title) to
                context.getString(R.string.cycle_of, cycle + 1, plan?.cycles ?: cycle + 1)
            else -> context.getString(R.string.phase_done_title) to
                context.getString(R.string.phase_done_text)
        }
        ensureChannels(context)
        val notification = NotificationCompat.Builder(context, CHANNEL_POMODORO)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(text)
            .setAutoCancel(true)
            .setContentIntent(openApp(context))
            .build()
        runCatching { NotificationManagerCompat.from(context).notify(ID_PHASE, notification) }
    }
}

/** Fired at each pomodoro phase change. */
class PhaseReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val store = FocusStore(context)
        FocusEngine.sync(store)
        FocusNotifications.postPhase(
            context,
            intent.getStringExtra(EXTRA_KIND) ?: KIND_DONE,
            intent.getIntExtra(EXTRA_CYCLE, 0),
        )
        FocusUpdates.refreshAll(context)
    }

    companion object {
        const val EXTRA_KIND = "kind"
        const val EXTRA_CYCLE = "cycle"
        const val KIND_REST = "rest"
        const val KIND_FOCUS = "focus"
        const val KIND_DONE = "done"
    }
}
