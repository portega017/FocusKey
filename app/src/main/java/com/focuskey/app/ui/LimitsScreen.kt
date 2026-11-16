package com.focuskey.app.ui

import android.content.Intent
import android.provider.Settings
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AddCircleOutline
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.focuskey.app.R
import com.focuskey.app.data.UsageLimit
import com.focuskey.app.ui.theme.FocusColors

/** Daily usage limits. Android can measure usage, so each row shows today's minutes. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LimitsScreen(viewModel: FocusViewModel, modifier: Modifier = Modifier) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    var editing by remember { mutableStateOf<UsageLimit?>(null) }
    var creating by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf<UsageLimit?>(null) }

    Scaffold(
        modifier = modifier,
        contentWindowInsets = WindowInsets(0),
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.tab_limits), fontWeight = FontWeight.Bold) },
                actions = {
                    IconButton(onClick = { creating = true }) {
                        Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.add_limit))
                    }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(Design.cardSpacing),
        ) {
            if (!state.hasUsageAccess) {
                FocusCard {
                    CardHeader(stringResource(R.string.usage_access_title), stringResource(R.string.usage_access_text))
                    Button(onClick = {
                        context.startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    }) { Text(stringResource(R.string.open_settings)) }
                }
            }

            FocusCard {
                if (state.limits.isEmpty()) {
                    CardHeader(stringResource(R.string.no_limits), stringResource(R.string.no_limits_hint))
                    TextButton(onClick = { creating = true }) { Text(stringResource(R.string.add_limit)) }
                }
                state.limits.forEachIndexed { index, limit ->
                    if (index > 0) HorizontalDivider()
                    LimitRow(
                        limit = limit,
                        state = state,
                        onEdit = { editing = limit },
                        onToggle = { viewModel.setLimitEnabled(limit.id, it) },
                        onDelete = { deleting = limit },
                    )
                }
                if (state.blockingLimitIds.isNotEmpty()) {
                    MenuButton(
                        label = stringResource(R.string.extend_with_key),
                        icon = { Icon(Icons.Filled.AddCircleOutline, contentDescription = null) },
                        options = listOf(5, 15, 30).map { "+" + formatMinutes(context, it) to { viewModel.extendLimits(it) } },
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }

            Text(
                stringResource(R.string.limits_footer),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 6.dp),
            )
        }
    }

    if (creating || editing != null) {
        LimitForm(
            limit = editing,
            state = state,
            onSave = { viewModel.saveLimit(it); creating = false; editing = null },
            onCancel = { creating = false; editing = null },
        )
    }
    deleting?.let { limit ->
        AlertDialog(
            onDismissRequest = { deleting = null },
            title = { Text(stringResource(R.string.delete_confirm, limit.name.ifEmpty { stringResource(R.string.limit_default_name) })) },
            confirmButton = {
                TextButton(onClick = { deleting = null; viewModel.deleteLimit(limit.id) }) {
                    Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { deleting = null }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}

@Composable
private fun LimitRow(limit: UsageLimit, state: UiState, onEdit: () -> Unit, onToggle: (Boolean) -> Unit, onDelete: () -> Unit) {
    val context = LocalContext.current
    val profile = state.profile(limit.profileId)
    val used = state.limitUsage[limit.id]
    val blocking = limit.id in state.blockingLimitIds
    val extended = state.limitDays[limit.id]?.let { it.reached && it.extendedUntil != null && !blocking } == true
    val locked = blocking || extended
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(
                Modifier.weight(1f).clickable(enabled = !locked, onClick = onEdit),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                ProfileIcon(profile?.icon ?: "shield", profile?.colorName ?: "indigo", size = 42.dp, alpha = if (limit.isEnabled) 1f else 0.45f)
                Column(Modifier.weight(1f)) {
                    Text(
                        limit.name.ifEmpty { stringResource(R.string.limit_default_name) },
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                    )
                    Text(
                        stringResource(R.string.per_day, formatMinutes(context, limit.minutes)) + " · " + profile?.name.orEmpty(),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    when {
                        blocking -> Text(stringResource(R.string.reached_today), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = FocusColors.Orange)
                        extended -> Text(stringResource(R.string.extended_with_key), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = FocusColors.Orange)
                    }
                }
            }
            Switch(checked = limit.isEnabled, enabled = !locked, onCheckedChange = onToggle)
        }
        if (limit.isEnabled && used != null) {
            val progress = (used.toFloat() / limit.minutes).coerceIn(0f, 1f)
            LinearProgressIndicator(
                progress = { progress },
                modifier = Modifier.fillMaxWidth(),
                color = if (progress >= 1f) FocusColors.Orange else profileColor(profile?.colorName ?: "indigo"),
            )
            Row {
                Text(
                    stringResource(R.string.used_today, formatMinutes(context, used)),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f),
                )
                if (!locked) {
                    TextButton(onClick = onDelete) { Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error) }
                }
            }
        } else if (!locked) {
            TextButton(onClick = onDelete) { Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error) }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LimitForm(limit: UsageLimit?, state: UiState, onSave: (UsageLimit) -> Unit, onCancel: () -> Unit) {
    val context = LocalContext.current
    var name by remember { mutableStateOf(limit?.name ?: "") }
    var profileId by remember { mutableStateOf(state.profiles.firstOrNull { it.id == limit?.profileId }?.id ?: state.activeProfileId) }
    var minutes by remember { mutableIntStateOf(limit?.minutes ?: 30) }
    var enabled by remember { mutableStateOf(limit?.isEnabled ?: true) }

    Dialog(onDismissRequest = onCancel, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        SubScreen(
            title = stringResource(if (limit == null) R.string.new_limit else R.string.edit_limit),
            onBack = onCancel,
            modifier = Modifier.fillMaxSize(),
            action = {
                TextButton(onClick = {
                    onSave(
                        (limit ?: UsageLimit(profileId = profileId)).copy(name = name.trim(), profileId = profileId, minutes = minutes, isEnabled = enabled)
                    )
                }) { Text(stringResource(R.string.save)) }
            },
        ) {
            FormSection(stringResource(R.string.name)) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    placeholder = { Text(stringResource(R.string.limit_name_hint)) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth().padding(12.dp),
                )
            }
            FormSection(stringResource(R.string.what_to_limit), footer = stringResource(R.string.limit_profile_footer, selectionSummary(context, state.profile(profileId)))) {
                ProfilePicker(state.profiles, state.profile(profileId)?.id) { profileId = it }
            }
            FormSection(stringResource(R.string.max_per_day)) {
                Column(Modifier.padding(12.dp)) {
                    Stepper(
                        formatMinutes(context, minutes),
                        onMinus = { minutes = (minutes - 5).coerceAtLeast(5) },
                        onPlus = { minutes = (minutes + 5).coerceAtMost(600) },
                    )
                }
            }
            FormSection {
                FormRow(stringResource(R.string.limit_enabled), onClick = { enabled = !enabled }) {
                    Switch(checked = enabled, onCheckedChange = { enabled = it })
                }
            }
        }
    }
}
