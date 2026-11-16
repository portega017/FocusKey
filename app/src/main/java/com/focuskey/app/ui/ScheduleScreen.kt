package com.focuskey.app.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.PauseCircle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.focuskey.app.R
import com.focuskey.app.data.Schedule
import com.focuskey.app.logic.FocusEngine.toLocalDateTime
import com.focuskey.app.ui.theme.FocusColors
import java.time.LocalDate

/** Android version of ScheduleView.swift: one card with compact rows. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScheduleScreen(viewModel: FocusViewModel, navigate: (Route) -> Unit, modifier: Modifier = Modifier) {
    val state by viewModel.state.collectAsState()
    var adding by remember { mutableStateOf(false) }
    var pendingStart by remember { mutableStateOf<Schedule?>(null) }
    val now = state.now.toLocalDateTime()

    Scaffold(
        modifier = modifier,
        contentWindowInsets = WindowInsets(0),
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.tab_schedules), fontWeight = FontWeight.Bold) },
                actions = {
                    IconButton(onClick = { adding = true }) {
                        Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.add_schedule))
                    }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(Design.cardSpacing),
        ) {
            FocusCard {
                if (state.schedules.isEmpty()) {
                    CardHeader(stringResource(R.string.no_schedules), stringResource(R.string.no_schedules_hint))
                    TextButton(onClick = { adding = true }) { Text(stringResource(R.string.add_schedule)) }
                }
                state.schedules.forEachIndexed { index, schedule ->
                    if (index > 0) HorizontalDivider()
                    ScheduleRow(
                        schedule = schedule,
                        state = state,
                        isRunning = schedule.isActive(now),
                        onOpen = { navigate(Route.ScheduleDetail(schedule.id)) },
                        onToggle = { enabled ->
                            if (enabled && schedule.copy(isEnabled = true).isActive(now)) {
                                // Ask first: it would block right away.
                                pendingStart = schedule
                            } else {
                                viewModel.setScheduleEnabled(schedule.id, enabled)
                            }
                        },
                    )
                }
            }
        }
    }

    pendingStart?.let { schedule ->
        StartsNowDialog(
            endTime = schedule.endTime,
            onConfirm = { pendingStart = null; viewModel.setScheduleEnabled(schedule.id, true) },
            onDismiss = { pendingStart = null },
        )
    }

    if (adding) {
        ScheduleForm(
            schedule = null,
            profiles = state.profiles,
            defaultProfileId = state.activeProfileId,
            onSave = { viewModel.saveSchedule(it); adding = false },
            onCancel = { adding = false },
        )
    }
}

@Composable
private fun ScheduleRow(
    schedule: Schedule,
    state: UiState,
    isRunning: Boolean,
    onOpen: () -> Unit,
    onToggle: (Boolean) -> Unit,
) {
    val context = LocalContext.current
    val profile = state.profile(schedule.profileId)
    val now = state.now.toLocalDateTime()
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(
            Modifier.weight(1f).clickable(onClick = onOpen),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            ProfileIcon(profile?.icon ?: "shield", profile?.colorName ?: "indigo", size = 42.dp, alpha = if (schedule.isEnabled) 1f else 0.45f)
            Column(Modifier.weight(1f)) {
                Text(
                    schedule.name.ifEmpty { stringResource(R.string.schedule_default_name) },
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = if (schedule.isEnabled) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                )
                Text(
                    "${formatTime(context, schedule.startTime)} – ${formatTime(context, schedule.endTime)}",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                val pause = schedule.activePauses(now).firstOrNull()
                when {
                    isRunning -> Text(
                        stringResource(R.string.running_until, formatTime(context, schedule.endTime)),
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = FocusColors.Orange,
                    )
                    schedule.isEnabled && pause != null -> Text(
                        stringResource(R.string.paused_on, formatDay(pause)),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    else -> Text(
                        daysSummary(context, schedule.repeats),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = MaterialTheme.colorScheme.outline)
        }
        Switch(checked = schedule.isEnabled, enabled = !isRunning, onCheckedChange = onToggle)
    }
}

/** Everything about one schedule, with its actions. */
@Composable
fun ScheduleDetailScreen(viewModel: FocusViewModel, id: String, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    val schedule = state.schedules.firstOrNull { it.id == id }
    if (schedule == null) {
        // Deleted (possibly after the key confirmed it): leave the screen.
        androidx.compose.runtime.LaunchedEffect(Unit) { onBack() }
        return
    }
    val now = state.now.toLocalDateTime()
    val isRunning = schedule.isActive(now)
    val profile = state.profile(schedule.profileId)
    var editing by remember { mutableStateOf(false) }
    var pausing by remember { mutableStateOf(false) }
    var confirmingDelete by remember { mutableStateOf(false) }
    var confirmingStart by remember { mutableStateOf(false) }
    val title = schedule.name.ifEmpty { stringResource(R.string.schedule_default_name) }

    SubScreen(title, onBack, modifier) {
        FormSection(footer = if (isRunning) stringResource(R.string.schedule_running_footer, formatTime(context, schedule.endTime)) else null) {
            Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                ProfileIcon(profile?.icon ?: "shield", profile?.colorName ?: "indigo", size = 52.dp)
                Column(Modifier.weight(1f)) {
                    Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                    Text(profile?.name.orEmpty(), color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                when {
                    isRunning -> StatusBadge(stringResource(R.string.running), FocusColors.Orange)
                    schedule.isEnabled -> StatusBadge(stringResource(R.string.on), FocusColors.Green)
                    else -> StatusBadge(stringResource(R.string.off), MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            HorizontalDivider()
            FormRow(stringResource(R.string.schedule_enabled)) {
                Switch(
                    checked = schedule.isEnabled,
                    enabled = !isRunning,
                    onCheckedChange = { enabled ->
                        if (enabled && schedule.copy(isEnabled = true).isActive(now)) confirmingStart = true
                        else viewModel.setScheduleEnabled(schedule.id, enabled)
                    },
                )
            }
        }

        FormSection(stringResource(R.string.schedule)) {
            FormRow(stringResource(R.string.start_label)) { Text(formatTime(context, schedule.startTime)) }
            HorizontalDivider()
            FormRow(stringResource(R.string.end_label)) {
                Text(formatTime(context, schedule.endTime) + if (schedule.crossesMidnight) " " + stringResource(R.string.next_day) else "")
            }
            HorizontalDivider()
            FormRow(stringResource(R.string.days)) { Text(daysSummary(context, schedule.repeats)) }
        }

        if (schedule.isEnabled) {
            FormSection(stringResource(R.string.pauses), footer = stringResource(R.string.pauses_footer)) {
                schedule.activePauses(now).forEach { day ->
                    FormRow(formatDay(day)) {
                        TextButton(onClick = { viewModel.resumeSchedule(schedule.id, day) }) { Text(stringResource(R.string.remove_pause)) }
                    }
                    HorizontalDivider()
                }
                FormRow(stringResource(R.string.pause_a_day), onClick = { pausing = true }) {
                    Icon(Icons.Filled.PauseCircle, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                }
            }
        }

        FormSection {
            FormRow(stringResource(R.string.edit), onClick = if (isRunning) null else ({ editing = true }))
            HorizontalDivider()
            FormRow(stringResource(R.string.duplicate), onClick = { viewModel.duplicateSchedule(schedule.id) })
            HorizontalDivider()
            Row(
                Modifier.fillMaxWidth().clickable(enabled = !isRunning) { confirmingDelete = true }.padding(horizontal = 16.dp, vertical = 12.dp),
            ) {
                Text(
                    stringResource(R.string.delete_schedule),
                    color = if (isRunning) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.error,
                )
            }
        }
    }

    if (editing) {
        ScheduleForm(
            schedule = schedule,
            profiles = state.profiles,
            defaultProfileId = state.activeProfileId,
            onSave = { viewModel.saveSchedule(it); editing = false },
            onCancel = { editing = false },
        )
    }
    if (pausing) {
        PauseDayDialog(
            schedule = schedule,
            needsKey = state.strictMode,
            onPause = { day -> pausing = false; viewModel.pauseSchedule(schedule.id, day) },
            onDismiss = { pausing = false },
        )
    }
    if (confirmingStart) {
        StartsNowDialog(
            endTime = schedule.endTime,
            onConfirm = { confirmingStart = false; viewModel.setScheduleEnabled(schedule.id, true) },
            onDismiss = { confirmingStart = false },
        )
    }
    if (confirmingDelete) {
        AlertDialog(
            onDismissRequest = { confirmingDelete = false },
            title = { Text(stringResource(R.string.delete_confirm, title)) },
            confirmButton = {
                TextButton(onClick = { confirmingDelete = false; viewModel.deleteSchedule(schedule.id) }) {
                    Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { confirmingDelete = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}

/** Picks one upcoming day to skip. */
@Composable
private fun PauseDayDialog(schedule: Schedule, needsKey: Boolean, onPause: (LocalDate) -> Unit, onDismiss: () -> Unit) {
    val context = LocalContext.current
    var selected by remember { mutableStateOf<LocalDate?>(null) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.pause_a_day)) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                schedule.upcomingDays().forEach { day ->
                    val paused = day in schedule.pausedDays
                    Row(
                        Modifier.fillMaxWidth().clickable(enabled = !paused) { selected = day }.padding(vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        RadioButton(selected = selected == day, enabled = !paused, onClick = { selected = day })
                        Column {
                            Text(formatDay(day))
                            Text(
                                if (paused) stringResource(R.string.already_paused)
                                else stringResource(R.string.from_time, formatTime(context, schedule.startTime)),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
                Spacer(Modifier.size(8.dp))
                Text(
                    stringResource(if (needsKey) R.string.pause_footer_strict else R.string.pause_footer),
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        },
        confirmButton = {
            TextButton(enabled = selected != null, onClick = { selected?.let(onPause) }) {
                Text(stringResource(if (needsKey) R.string.pause_with_key else R.string.pause))
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}
