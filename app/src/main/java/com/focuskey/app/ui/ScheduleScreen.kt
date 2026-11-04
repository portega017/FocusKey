package com.focuskey.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.focuskey.app.data.Schedule
import com.focuskey.app.data.Weekday
import com.focuskey.app.ui.theme.FocusColors

/** Android version of ScheduleView.swift. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScheduleScreen(viewModel: FocusViewModel, modifier: Modifier = Modifier) {
    val schedules by viewModel.schedules.collectAsState()
    val now by viewModel.now.collectAsState()
    val message by viewModel.scheduleMessage.collectAsState()
    val snackbar = remember { SnackbarHostState() }

    var showingAdd by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<Schedule?>(null) }

    LaunchedEffect(message) {
        message?.let {
            snackbar.showSnackbar(it)
            viewModel.consumeScheduleMessage()
        }
    }

    Scaffold(
        modifier = modifier,
        contentWindowInsets = WindowInsets(0),
        topBar = { TopAppBar(title = { Text("Horarios") }) },
        snackbarHost = { SnackbarHost(snackbar) }
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            if (schedules.isEmpty()) {
                item { EmptySchedules() }
            }
            items(schedules, key = { it.id }) { schedule ->
                ScheduleCard(
                    schedule = schedule,
                    isRunning = schedule.isActive(now),
                    wouldStartNow = { viewModel.isScheduleActive(it) },
                    onUpdate = viewModel::updateSchedule,
                    onSetEnabled = { viewModel.setScheduleEnabled(schedule.id, it) },
                    onEdit = { editing = schedule },
                    onDuplicate = { viewModel.duplicateSchedule(schedule.id) },
                    onDelete = { viewModel.deleteSchedule(schedule.id) }
                )
            }
            item {
                OutlinedButton(onClick = { showingAdd = true }, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Filled.Add, contentDescription = null)
                    Spacer(Modifier.size(8.dp))
                    Text("Añadir horario")
                }
            }
        }
    }

    if (showingAdd) {
        ScheduleForm(
            schedule = null,
            wouldStartNow = { viewModel.isScheduleActive(it) },
            onSave = { viewModel.addSchedule(it); showingAdd = false },
            onCancel = { showingAdd = false }
        )
    }
    editing?.let { schedule ->
        ScheduleForm(
            schedule = schedule,
            wouldStartNow = { viewModel.isScheduleActive(it) },
            onSave = { viewModel.updateSchedule(it); editing = null },
            onCancel = { editing = null }
        )
    }
}

@Composable
private fun EmptySchedules() {
    Column(
        modifier = Modifier.fillMaxWidth().padding(vertical = 72.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Icon(
            Icons.Filled.CalendarMonth,
            contentDescription = null,
            modifier = Modifier.size(48.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text("Sin horarios", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        Text(
            "Crea un horario para bloquear tus selecciones automáticamente.",
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun ScheduleCard(
    schedule: Schedule,
    isRunning: Boolean,
    wouldStartNow: (Schedule) -> Boolean,
    onUpdate: (Schedule) -> Unit,
    onSetEnabled: (Boolean) -> Unit,
    onEdit: () -> Unit,
    onDuplicate: () -> Unit,
    onDelete: () -> Unit,
) {
    var showingStartNow by remember { mutableStateOf(false) }
    val shape = RoundedCornerShape(24.dp)
    val subtle = MaterialTheme.colorScheme.surfaceVariant

    val badgeText = when {
        isRunning -> "En curso"
        schedule.isEnabled -> "Activo"
        else -> "Inactivo"
    }
    val badgeColor = when {
        isRunning -> FocusColors.Orange
        schedule.isEnabled -> FocusColors.Green
        else -> MaterialTheme.colorScheme.onSurfaceVariant
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface, shape)
            .border(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.2f), shape)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp)
    ) {
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Box(
                modifier = Modifier
                    .size(56.dp)
                    .background(MaterialTheme.colorScheme.primary, RoundedCornerShape(18.dp)),
                contentAlignment = Alignment.Center
            ) {
                Icon(Icons.Filled.CalendarMonth, contentDescription = null, tint = Color.White, modifier = Modifier.size(30.dp))
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(schedule.displayName, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                Text(
                    "Bloqueo programado",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    badgeText,
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = badgeColor,
                    modifier = Modifier
                        .background(badgeColor.copy(alpha = 0.14f), CircleShape)
                        .padding(horizontal = 9.dp, vertical = 5.dp)
                )
                Switch(
                    checked = schedule.isEnabled,
                    enabled = !isRunning,
                    onCheckedChange = { enabled ->
                        // Turning on a schedule whose time range includes "now" blocks immediately: ask first.
                        if (enabled && wouldStartNow(schedule.copy(isEnabled = true))) {
                            showingStartNow = true
                        } else {
                            onSetEnabled(enabled)
                        }
                    },
                    colors = SwitchDefaults.colors(checkedTrackColor = FocusColors.Green)
                )
            }
        }

        if (isRunning) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(FocusColors.Orange.copy(alpha = 0.12f), RoundedCornerShape(14.dp))
                    .padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Icon(Icons.Filled.Lock, contentDescription = null, tint = FocusColors.Orange, modifier = Modifier.size(18.dp))
                Text(
                    "En curso — no se puede modificar hasta las ${formatTime(schedule.endTime)}",
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = FontWeight.Medium,
                    color = FocusColors.Orange
                )
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Días de la semana", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Weekday.entries.forEach { day ->
                    val selected = day in schedule.repeats
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .heightIn(min = 40.dp)
                            .background(if (selected) MaterialTheme.colorScheme.primary else Color.Transparent, CircleShape),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            day.initial,
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                            color = if (selected) Color.White else MaterialTheme.colorScheme.onSurface
                        )
                    }
                }
            }
        }

        // Read-only: times are changed only from the edit form, which has a Save button.
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            TimeLabel("Hora de inicio", formatTime(schedule.startTime), subtle, Modifier.weight(1f))
            TimeLabel("Hora de fin", formatTime(schedule.endTime), subtle, Modifier.weight(1f))
        }

        Text(
            recurrenceSummary(schedule.repeats, schedule.startTime, schedule.endTime),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier
                .fillMaxWidth()
                .background(subtle, RoundedCornerShape(14.dp))
                .padding(12.dp)
        )

        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = onEdit, enabled = !isRunning) { Text("Editar") }
            OutlinedButton(onClick = onDuplicate) { Text("Duplicar") }
            Spacer(Modifier.weight(1f))
            OutlinedButton(
                onClick = onDelete,
                enabled = !isRunning,
                colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error)
            ) { Text("Eliminar") }
        }
    }

    if (showingStartNow) {
        StartsNowDialog(
            endTime = schedule.endTime,
            onConfirm = {
                showingStartNow = false
                onUpdate(schedule.copy(isEnabled = true))
            },
            onDismiss = { showingStartNow = false }
        )
    }
}

@Composable
private fun TimeLabel(title: String, time: String, background: Color, modifier: Modifier = Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        Text(
            time,
            style = MaterialTheme.typography.bodyLarge,
            modifier = Modifier
                .fillMaxWidth()
                .background(background, CircleShape)
                .padding(horizontal = 12.dp, vertical = 10.dp)
        )
    }
}
