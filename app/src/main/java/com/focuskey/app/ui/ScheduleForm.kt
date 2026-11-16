package com.focuskey.app.ui

import android.text.format.DateFormat
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.focuskey.app.R
import com.focuskey.app.data.Profile
import com.focuskey.app.data.Schedule
import com.focuskey.app.data.Weekday
import java.time.LocalTime

private data class ScheduleTemplate(val name: Int, val startHour: Int, val endHour: Int, val repeats: Set<Weekday>)

private val templates = listOf(
    ScheduleTemplate(R.string.template_study, 9, 14, Weekday.WORKDAYS),
    ScheduleTemplate(R.string.template_work, 9, 17, Weekday.WORKDAYS),
    ScheduleTemplate(R.string.template_sleep, 23, 7, Weekday.entries.toSet()),
)

/** New / edit schedule form. Android version of ScheduleForm in ScheduleView.swift. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScheduleForm(
    schedule: Schedule?,
    profiles: List<Profile>,
    defaultProfileId: String?,
    onSave: (Schedule) -> Unit,
    onCancel: () -> Unit,
) {
    val context = LocalContext.current
    var name by remember { mutableStateOf(schedule?.name ?: "") }
    var start by remember { mutableStateOf(schedule?.startTime ?: LocalTime.of(9, 0)) }
    var end by remember { mutableStateOf(schedule?.endTime ?: LocalTime.of(10, 0)) }
    var repeats by remember { mutableStateOf(schedule?.repeats ?: Weekday.WORKDAYS) }
    var isEnabled by remember { mutableStateOf(schedule?.isEnabled ?: true) }
    var profileId by remember {
        mutableStateOf(profiles.firstOrNull { it.id == schedule?.profileId }?.id ?: defaultProfileId ?: profiles.firstOrNull()?.id)
    }
    var editingTime by remember { mutableStateOf<Boolean?>(null) } // true = start, false = end
    var showingStartNow by remember { mutableStateOf(false) }

    val id = remember { schedule?.id ?: java.util.UUID.randomUUID().toString() }
    fun draft() = Schedule(
        id = id,
        name = name.trim(),
        startMinutes = start.hour * 60 + start.minute,
        endMinutes = end.hour * 60 + end.minute,
        repeats = repeats,
        isEnabled = isEnabled,
        profileId = profileId,
        pausedDays = schedule?.pausedDays ?: emptySet(),
    )
    val canSave = repeats.isNotEmpty() && start != end

    Dialog(onDismissRequest = onCancel, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Scaffold(
            containerColor = MaterialTheme.colorScheme.background,
            topBar = {
                TopAppBar(
                    title = { Text(stringResource(if (schedule == null) R.string.new_schedule else R.string.edit_schedule)) },
                    navigationIcon = {
                        IconButton(onClick = onCancel) { Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.cancel)) }
                    },
                    actions = {
                        TextButton(
                            enabled = canSave,
                            onClick = {
                                val draft = draft()
                                if (draft.isActive()) showingStartNow = true else onSave(draft)
                            },
                        ) { Text(stringResource(R.string.save)) }
                    },
                )
            },
        ) { padding ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .imePadding()
                    .verticalScroll(rememberScrollState())
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(20.dp),
            ) {
                FormSection(stringResource(R.string.templates)) {
                    templates.forEachIndexed { index, template ->
                        if (index > 0) HorizontalDivider()
                        val templateName = stringResource(template.name)
                        Column(
                            Modifier
                                .fillMaxWidth()
                                .clickable {
                                    name = templateName
                                    start = LocalTime.of(template.startHour, 0)
                                    end = LocalTime.of(template.endHour, 0)
                                    repeats = template.repeats
                                }
                                .padding(16.dp),
                        ) {
                            Text(templateName, color = MaterialTheme.colorScheme.primary)
                            Text(
                                "%02d:00–%02d:00".format(template.startHour, template.endHour),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }

                FormSection(stringResource(R.string.name), footer = stringResource(R.string.schedule_name_footer)) {
                    OutlinedTextField(
                        value = name,
                        onValueChange = { name = it },
                        placeholder = { Text(stringResource(R.string.schedule_default_name)) },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth().padding(12.dp),
                    )
                }

                FormSection(stringResource(R.string.what_to_block), footer = selectionSummary(context, profiles.firstOrNull { it.id == profileId })) {
                    ProfilePicker(profiles, profileId) { profileId = it }
                }

                FormSection(stringResource(R.string.schedule), footer = stringResource(R.string.schedule_next_day_footer)) {
                    FormRow(stringResource(R.string.start_label), onClick = { editingTime = true }) { Text(formatTime(context, start)) }
                    HorizontalDivider()
                    FormRow(stringResource(R.string.end_label), onClick = { editingTime = false }) { Text(formatTime(context, end)) }
                }

                FormSection(stringResource(R.string.repeat), footer = stringResource(R.string.repeat_footer)) {
                    Weekday.entries.forEachIndexed { index, day ->
                        if (index > 0) HorizontalDivider()
                        val selected = day in repeats
                        FormRow(weekdayShort(context, day), onClick = { repeats = if (selected) repeats - day else repeats + day }) {
                            Switch(checked = selected, onCheckedChange = { repeats = if (it) repeats + day else repeats - day })
                        }
                    }
                }

                FormSection(
                    stringResource(R.string.state),
                    footer = stringResource(if (isEnabled) R.string.state_on_footer else R.string.state_off_footer),
                ) {
                    FormRow(stringResource(R.string.schedule_enabled), onClick = { isEnabled = !isEnabled }) {
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
                onDismiss = { editingTime = null },
            )
        }

        if (showingStartNow) {
            StartsNowDialog(
                endTime = end,
                onConfirm = {
                    showingStartNow = false
                    onSave(draft())
                },
                onDismiss = { showingStartNow = false },
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TimePickerDialog(initial: LocalTime, onConfirm: (LocalTime) -> Unit, onDismiss: () -> Unit) {
    val state = rememberTimePickerState(
        initialHour = initial.hour,
        initialMinute = initial.minute,
        is24Hour = DateFormat.is24HourFormat(LocalContext.current),
    )
    AlertDialog(
        onDismissRequest = onDismiss,
        text = { TimePicker(state = state) },
        confirmButton = {
            TextButton(onClick = { onConfirm(LocalTime.of(state.hour, state.minute)) }) { Text(stringResource(R.string.ok)) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}
