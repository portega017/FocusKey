package com.focuskey.app.ui

import android.content.Intent
import android.provider.Settings
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.focuskey.app.R
import com.focuskey.app.data.BlockRecord
import com.focuskey.app.logic.DayCounter
import com.focuskey.app.logic.DayMinutes
import com.focuskey.app.logic.UsageTracker
import com.focuskey.app.logic.WeekStats
import com.focuskey.app.logic.YearStats
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Android version of StatsView.swift: Week, Year and Usage. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StatsScreen(viewModel: FocusViewModel, modifier: Modifier = Modifier) {
    val state by viewModel.state.collectAsState()
    var section by rememberSaveable { mutableIntStateOf(0) }
    val today = LocalDate.now()
    val counter = remember(state.records, state.dailyArchive, state.archivedUntil, state.now / 60_000) {
        DayCounter(state.records, state.dailyArchive, state.archivedUntil, state.now)
    }

    Scaffold(
        modifier = modifier,
        contentWindowInsets = WindowInsets(0),
        containerColor = MaterialTheme.colorScheme.background,
        topBar = { TopAppBar(title = { Text(stringResource(R.string.tab_stats), fontWeight = FontWeight.Bold) }) },
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(Design.cardSpacing),
        ) {
            val labels = listOf(R.string.week, R.string.year, R.string.usage)
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                labels.forEachIndexed { index, label ->
                    SegmentedButton(selected = section == index, onClick = { section = index }, shape = SegmentedButtonDefaults.itemShape(index, labels.size)) {
                        Text(stringResource(label))
                    }
                }
            }
            when (section) {
                0 -> WeekSection(WeekStats(counter, today), state)
                1 -> YearSection(counter, today)
                else -> UsageSection(state)
            }
        }
    }
}

// MARK: - Week

@Composable
private fun WeekSection(stats: WeekStats, state: UiState) {
    val context = LocalContext.current
    FocusCard {
        Row(Modifier.fillMaxWidth().height(56.dp), verticalAlignment = Alignment.CenterVertically) {
            Metric(stringResource(R.string.today), formatMinutes(context, stats.today), Modifier.weight(1f))
            VerticalDivider(Modifier.fillMaxHeight().padding(vertical = 8.dp))
            Metric(stringResource(R.string.seven_days), formatMinutes(context, stats.weekTotal), Modifier.weight(1f).padding(start = 12.dp))
            VerticalDivider(Modifier.fillMaxHeight().padding(vertical = 8.dp))
            Metric(stringResource(R.string.streak), context.resources.getQuantityString(R.plurals.days_count, stats.streak, stats.streak), Modifier.weight(1f).padding(start = 12.dp))
        }
    }

    if (state.revocations.isNotEmpty()) {
        FocusCard {
            CardHeader(stringResource(R.string.revoked_stats_title))
            Text(
                context.resources.getQuantityString(R.plurals.revocations, state.revocations.size, state.revocations.size),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
            )
        }
    }

    FocusCard {
        CardHeader(stringResource(R.string.time_blocked))
        BarChart(
            values = stats.week.map { it.minutes / 60f },
            labels = stats.week.map { it.date.dayOfWeek.getDisplayName(TextStyle.NARROW, Locale.getDefault()) },
            unit = "h",
        )
    }

    FocusCard {
        CardHeader(stringResource(R.string.last_five_weeks))
        Heatmap(stats.calendar, LocalDate.now())
    }

    FocusCard {
        CardHeader(stringResource(R.string.recent_blocks))
        val recent = state.records.sortedByDescending { it.start }.take(15)
        if (recent.isEmpty()) {
            Text(stringResource(R.string.no_blocks_yet), color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        recent.forEach { RecordRow(it, state.now) }
    }
}

@Composable
private fun Metric(title: String, value: String, modifier: Modifier = Modifier) {
    Column(modifier) {
        Text(title, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
        Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, maxLines = 1)
    }
}

@Composable
private fun RecordRow(record: BlockRecord, now: Long) {
    val context = LocalContext.current
    val kind = stringResource(
        when (record.kind) {
            BlockRecord.Kind.MANUAL -> R.string.kind_manual
            BlockRecord.Kind.SESSION -> R.string.kind_session
            BlockRecord.Kind.SCHEDULE -> R.string.kind_schedule
            BlockRecord.Kind.LIMIT -> R.string.kind_limit
            BlockRecord.Kind.POMODORO -> R.string.pomodoro
        }
    )
    val start = Instant.ofEpochMilli(record.start).atZone(ZoneId.systemDefault())
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(record.title.ifEmpty { kind }, fontWeight = FontWeight.Medium, maxLines = 1)
            Text(
                "$kind · ${start.format(DateTimeFormatter.ofPattern("EEE d", Locale.getDefault()))}, ${formatClock(context, record.start)}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Text(
            record.end?.let { formatMinutes(context, ((it - record.start) / 60_000).toInt()) } ?: stringResource(R.string.running),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/** Simple bar chart: one bar per value, labels underneath, max on top. */
@Composable
private fun BarChart(values: List<Float>, labels: List<String>, unit: String, color: Color = MaterialTheme.colorScheme.primary) {
    val max = (values.maxOrNull() ?: 0f).coerceAtLeast(1f)
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("%.0f %s".format(max, unit), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Row(Modifier.fillMaxWidth().height(140.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            values.forEach { value ->
                Box(
                    Modifier
                        .weight(1f)
                        .fillMaxHeight((value / max).coerceIn(0.02f, 1f))
                        .background(color, RoundedCornerShape(topStart = 4.dp, topEnd = 4.dp)),
                )
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            labels.forEach {
                Text(it, modifier = Modifier.weight(1f), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center, maxLines = 1)
            }
        }
    }
}

private val LEVELS = listOf(0, 30, 60, 120, 240)

@Composable
private fun shade(minutes: Int): Color {
    if (minutes <= 0) return MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f)
    val level = (1 until LEVELS.size).firstOrNull { minutes <= LEVELS[it] } ?: (LEVELS.size - 1)
    return MaterialTheme.colorScheme.primary.copy(alpha = listOf(0f, 0.3f, 0.5f, 0.72f, 1f)[level])
}

/** Five Monday-first weeks, one cell per day. Tap a day for its minutes. */
@Composable
private fun Heatmap(days: List<DayMinutes>, today: LocalDate) {
    val context = LocalContext.current
    var selected by remember { mutableStateOf<DayMinutes?>(null) }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            selected?.let { "${formatDay(it.date)}: ${formatMinutes(context, it.minutes)}" } ?: stringResource(R.string.tap_a_day),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            DayOfWeek.entries.forEach {
                Text(it.getDisplayName(TextStyle.NARROW, Locale.getDefault()), Modifier.weight(1f), style = MaterialTheme.typography.labelSmall,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        days.chunked(7).forEach { week ->
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                week.forEach { day ->
                    val future = day.date > today
                    Box(
                        Modifier
                            .weight(1f)
                            .aspectRatio(1f)
                            .background(if (future) Color.Transparent else shade(day.minutes), RoundedCornerShape(5.dp))
                            .clickable(enabled = !future) { selected = day },
                    )
                }
            }
        }
    }
}

// MARK: - Year

@Composable
private fun YearSection(counter: DayCounter, today: LocalDate) {
    val context = LocalContext.current
    val years = remember(counter) { counter.years(today) }
    var year by rememberSaveable { mutableIntStateOf(today.year) }
    val stats = remember(counter, year) { YearStats(year, counter, today) }
    var selected by remember(year) { mutableStateOf<DayMinutes?>(null) }

    FocusCard {
        CardHeader(stringResource(R.string.focus_this_year))
        if (years.size > 1) {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                years.forEach { FilterChip(selected = it == year, onClick = { year = it }, label = { Text("$it") }) }
            }
        }
        Text(formatMinutes(context, stats.total), style = MaterialTheme.typography.displaySmall, fontWeight = FontWeight.Bold)
        Row {
            Metric(stringResource(R.string.daily_average), formatMinutes(context, stats.dailyAverage), Modifier.weight(1f))
            Metric(stringResource(R.string.days_with_focus), "${stats.activeDays}", Modifier.weight(1f))
        }
        Row {
            Metric(stringResource(R.string.best_day), stats.bestDay?.let { formatMinutes(context, it.minutes) } ?: "—", Modifier.weight(1f))
            Metric(stringResource(R.string.date), stats.bestDay?.date?.format(DateTimeFormatter.ofPattern("d MMM", Locale.getDefault())) ?: "—", Modifier.weight(1f))
        }
        BarChart(
            values = stats.months.map { it / 60f },
            labels = (1..12).map { java.time.Month.of(it).getDisplayName(TextStyle.NARROW, Locale.getDefault()) },
            unit = "h",
        )
        // One column per Monday-first week, one cell per day.
        val leading = stats.days.first().date.dayOfWeek.value - 1
        val cells: List<DayMinutes?> = List(leading) { null } + stats.days
        Row(Modifier.horizontalScroll(rememberScrollState(Int.MAX_VALUE)), horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            cells.chunked(7).forEach { week ->
                Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    (0 until 7).forEach { row ->
                        val day = week.getOrNull(row)
                        val future = day == null || day.date > today
                        Box(
                            Modifier
                                .size(12.dp)
                                .background(if (future) Color.Transparent else shade(day!!.minutes), RoundedCornerShape(2.5.dp))
                                .clickable(enabled = !future) { selected = day },
                        )
                    }
                }
            }
        }
        Text(
            selected?.let { "${formatDay(it.date)}: ${formatMinutes(context, it.minutes)}" } ?: stringResource(R.string.tap_a_day),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

// MARK: - Usage

@Composable
private fun UsageSection(state: UiState) {
    val context = LocalContext.current
    var profileId by rememberSaveable { mutableStateOf(state.activeProfileId) }
    val profile = state.profile(profileId)
    var report by remember { mutableStateOf<UsageTracker.Report?>(null) }

    LaunchedEffect(profile?.id, profile?.selection, state.hasUsageAccess) {
        report = null
        if (profile != null && state.hasUsageAccess && !profile.isEmpty) {
            report = withContext(Dispatchers.IO) { UsageTracker.weekReport(context, profile.selection) }
        }
    }

    FocusCard {
        CardHeader(stringResource(R.string.real_usage), stringResource(R.string.real_usage_footer))
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            state.profiles.forEach { FilterChip(selected = it.id == profile?.id, onClick = { profileId = it.id }, label = { Text(it.name) }) }
        }
        when {
            !state.hasUsageAccess -> {
                Text(stringResource(R.string.usage_access_text), color = MaterialTheme.colorScheme.onSurfaceVariant)
                Button(onClick = {
                    context.startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }) { Text(stringResource(R.string.open_settings)) }
            }
            profile == null || profile.isEmpty -> Text(stringResource(R.string.profile_has_no_apps), color = MaterialTheme.colorScheme.onSurfaceVariant)
            report == null -> Text(stringResource(R.string.loading), color = MaterialTheme.colorScheme.onSurfaceVariant)
            else -> {
                val days = report!!.days
                Row {
                    Metric(stringResource(R.string.today), formatMinutes(context, (days.last().second / 60_000).toInt()), Modifier.weight(1f))
                    Metric(stringResource(R.string.seven_days), formatMinutes(context, (days.sumOf { it.second } / 60_000).toInt()), Modifier.weight(1f))
                }
                BarChart(
                    values = days.map { it.second / 3_600_000f },
                    labels = days.map { it.first.dayOfWeek.getDisplayName(TextStyle.NARROW, Locale.getDefault()) },
                    unit = "h",
                    color = com.focuskey.app.ui.theme.FocusColors.Orange,
                )
                CardHeader(stringResource(R.string.most_used))
                if (report!!.apps.isEmpty()) Text(stringResource(R.string.no_usage), color = MaterialTheme.colorScheme.onSurfaceVariant)
                report!!.apps.forEach { app ->
                    Row {
                        Text(app.label, Modifier.weight(1f), maxLines = 1)
                        Text(formatMinutes(context, (app.millis / 60_000).toInt()), color = MaterialTheme.colorScheme.onSurfaceVariant, fontFamily = FontFamily.Default)
                    }
                }
            }
        }
    }
}
