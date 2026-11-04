package com.focuskey.app.ui

import android.text.format.DateFormat
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.focuskey.app.data.Schedule
import com.focuskey.app.data.Weekday
import java.time.LocalTime

private data class ScheduleTemplate(val name: String, val startHour: Int, val endHour: Int, val repeats: Set<Weekday>)

private val templates = listOf(
    ScheduleTemplate("Estudio", 9, 14, Weekday.WORKDAYS),
    ScheduleTemplate("Trabajo", 9, 17, Weekday.WORKDAYS),
    ScheduleTemplate("Dormir", 23, 7, Weekday.entries.toSet()),
)

/** New / edit schedule form. Android version of ScheduleForm in ScheduleView.swift. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScheduleForm(
    schedule: Schedule?,
    wouldStartNow: (Schedule) -> Boolean,
    onSave: (Schedule) -> Unit,
    onCancel: () -> Unit,
) {
    var name by remember { mutableStateOf(schedule?.name ?: "") }
    var start by remember { mutableStateOf(schedule?.startTime ?: LocalTime.of(9, 0)) }
    var end by remember { mutableStateOf(schedule?.endTime ?: LocalTime.of(10, 0)) }
    var repeats by remember { mutableStateOf(schedule?.repeats ?: Weekday.WORKDAYS) }
    var isEnabled by remember { mutableStateOf(schedule?.isEnabled ?: true) }
    var editingTime by remember { mutableStateOf<Boolean?>(null) } // true = start, false = end
    var showingStartNow by remember { mutableStateOf(false) }

    val id = remember { schedule?.id ?: java.util.UUID.randomUUID().toString() }
    fun draft() = Schedule(
        id = id,
        name = name,
        startMinutes = start.hour * 60 + start.minute,
        endMinutes = end.hour * 60 + end.minute,
        repeats = repeats,
        isEnabled = isEnabled,
    )
    val canSave = repeats.isNotEmpty() && start != end

    Dialog(onDismissRequest = onCancel, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(if (schedule == null) "Nuevo horario" else "Editar horario") },
                    navigationIcon = {
                        IconButton(onClick = onCancel) { Icon(Icons.Filled.Close, contentDescription = "Cancelar") }
                    },
                    actions = {
                        TextButton(
                            enabled = canSave,
                            onClick = {
                                val draft = draft()
                                if (wouldStartNow(draft)) showingStartNow = true else onSave(draft)
                            }
                        ) { Text("Guardar") }
                    }
                )
            }
        ) { padding ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .imePadding()
                    .verticalScroll(rememberScrollState())
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(20.dp)
            ) {
                FormSection("Plantillas") {
                    templates.forEachIndexed { index, template ->
                        if (index > 0) HorizontalDivider()
                        Column(
                            Modifier
                                .fillMaxWidth()
                                .clickable {
                                    name = template.name
                                    start = LocalTime.of(template.startHour, 0)
                                    end = LocalTime.of(template.endHour, 0)
                                    repeats = template.repeats
                                }
                                .padding(16.dp)
                        ) {
                            Text(template.name, color = MaterialTheme.colorScheme.primary)
                            Text(
                                "%02d:00–%02d:00".format(template.startHour, template.endHour),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }

                FormSection("Nombre", footer = "Opcional. Usa un nombre que te ayude a identificar este bloqueo.") {
                    OutlinedTextField(
                        value = name,
                        onValueChange = { name = it },
                        placeholder = { Text("Nombre del horario") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth().padding(12.dp)
                    )
                }

                FormSection("Horario", footer = "El horario puede terminar al día siguiente.") {
                    FormRow("Inicio", onClick = { editingTime = true }) { Text(formatTime(start)) }
                    HorizontalDivider()
                    FormRow("Fin", onClick = { editingTime = false }) { Text(formatTime(end)) }
                }

                FormSection("Repetición", footer = "Elige al menos un día para activar este horario.") {
                    Weekday.entries.forEachIndexed { index, day ->
                        if (index > 0) HorizontalDivider()
                        val selected = day in repeats
                        FormRow(day.shortName, onClick = { repeats = if (selected) repeats - day else repeats + day }) {
                            Switch(checked = selected, onCheckedChange = { repeats = if (it) repeats + day else repeats - day })
                        }
                    }
                }

                FormSection("Vista previa") {
                    Row(Modifier.padding(16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Box(
                            Modifier.size(40.dp).background(MaterialTheme.colorScheme.primary, RoundedCornerShape(12.dp)),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(Icons.Filled.CalendarMonth, contentDescription = null, tint = Color.White)
                        }
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(name.ifEmpty { "Horario de concentración" }, fontWeight = FontWeight.SemiBold)
                            Text(
                                recurrenceSummary(repeats, start, end),
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }

                FormSection(
                    "Estado",
                    footer = if (isEnabled) "El bloqueo se aplicará en el horario indicado."
                    else "Puedes guardarlo ahora y activarlo más tarde."
                ) {
                    FormRow("Horario activado", onClick = { isEnabled = !isEnabled }) {
                        Switch(checked = isEnabled, onCheckedChange = { isEnabled = it })
                    }
                }
            }
        }

        editingTime?.let { isStart ->
            TimePickerDialog(
                initial = if (isStart) start else end,
                onConfirm = {
                    if (isStart) start = it else end = it
                    editingTime = null
                },
                onDismiss = { editingTime = null }
            )
        }

        if (showingStartNow) {
            StartsNowDialog(
                endTime = end,
                onConfirm = {
                    showingStartNow = false
                    onSave(draft())
                },
                onDismiss = { showingStartNow = false }
            )
        }
    }
}

@Composable
private fun FormSection(title: String, footer: String? = null, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            title.uppercase(),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 16.dp)
        )
        Column(
            Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(12.dp)),
            content = content
        )
        footer?.let {
            Text(
                it,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp)
            )
        }
    }
}

@Composable
private fun FormRow(label: String, onClick: () -> Unit, trailing: @Composable () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, modifier = Modifier.weight(1f))
        trailing()
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TimePickerDialog(initial: LocalTime, onConfirm: (LocalTime) -> Unit, onDismiss: () -> Unit) {
    val state = rememberTimePickerState(
        initialHour = initial.hour,
        initialMinute = initial.minute,
        is24Hour = DateFormat.is24HourFormat(LocalContext.current)
    )
    AlertDialog(
        onDismissRequest = onDismiss,
        text = { TimePicker(state = state) },
        confirmButton = {
            TextButton(onClick = { onConfirm(LocalTime.of(state.hour, state.minute)) }) { Text("Aceptar") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancelar") } }
    )
}
