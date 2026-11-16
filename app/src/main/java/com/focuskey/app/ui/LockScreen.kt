package com.focuskey.app.ui

import android.content.Context
import android.content.Intent
import android.provider.Settings
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AddCircleOutline
import androidx.compose.material.icons.filled.Coffee
import androidx.compose.material.icons.filled.FastForward
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material.icons.filled.Nfc
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.focuskey.app.R
import com.focuskey.app.data.PomodoroPlan
import com.focuskey.app.data.Profile
import com.focuskey.app.data.SessionPreset
import com.focuskey.app.logic.FocusEngine
import com.focuskey.app.ui.theme.FocusColors

private val SESSION_OPTIONS = listOf(15, 30, 60, 120, 240)

/** Android version of ContentView.swift. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LockScreen(viewModel: FocusViewModel, navigate: (Route) -> Unit, modifier: Modifier = Modifier) {
    val state by viewModel.state.collectAsState()
    var showingDisclosure by remember { mutableStateOf(false) }
    var showingCustom by remember { mutableStateOf(false) }
    var showingPomodoro by remember { mutableStateOf(false) }

    Scaffold(
        modifier = modifier,
        contentWindowInsets = WindowInsets(0),
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.app_name), fontWeight = FontWeight.Bold) },
                actions = {
                    IconButton(onClick = { navigate(Route.Settings) }) {
                        Icon(Icons.Filled.Settings, contentDescription = stringResource(R.string.settings))
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
            if (state.isRevoked) {
                FocusCard {
                    CardHeader(stringResource(R.string.revoked_title), stringResource(R.string.revoked_text))
                    Button(onClick = { showingDisclosure = true }) { Text(stringResource(R.string.authorize)) }
                }
            }
            StatusCard(
                state = state,
                onAuthorize = { showingDisclosure = true },
                onUnlock = { viewModel.startNfcScan() },
                onLock = { viewModel.lock() },
                onLockFor = { viewModel.lock(it) },
                onCustom = { showingCustom = true },
                onPomodoro = { showingPomodoro = true },
                onExtend = viewModel::extendSession,
                onSkipBreak = viewModel::skipBreak,
                onExtendLimits = viewModel::extendLimits,
            )
            PresetsCard(
                state = state,
                onStart = viewModel::startPreset,
                onBlocked = { viewModel.say(it) },
                onEdit = { navigate(Route.PresetEditor(it)) },
                onDelete = viewModel::deletePreset,
            )
            ProfileCard(state = state, onSelect = viewModel::setActiveProfile, onManage = { navigate(Route.Profiles) })
        }
    }

    if (showingDisclosure) {
        val context = LocalContext.current
        AlertDialog(
            onDismissRequest = { showingDisclosure = false },
            title = { Text(stringResource(R.string.authorize)) },
            text = { Text(stringResource(R.string.authorize_disclosure)) },
            confirmButton = {
                TextButton(onClick = {
                    showingDisclosure = false
                    context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }) { Text(stringResource(R.string.open_settings)) }
            },
            dismissButton = { TextButton(onClick = { showingDisclosure = false }) { Text(stringResource(R.string.not_now)) } },
        )
    }
    if (showingCustom) {
        DurationDialog(
            title = stringResource(R.string.session),
            onConfirm = { showingCustom = false; viewModel.lock(it) },
            onDismiss = { showingCustom = false },
        )
    }
    if (showingPomodoro) {
        PomodoroDialog(
            profile = state.activeProfile,
            onStart = { focus, rest, cycles -> showingPomodoro = false; viewModel.startPomodoro(focus, rest, cycles) },
            onDismiss = { showingPomodoro = false },
        )
    }
}

// MARK: - Status

/** Headline and detail of the current state, like FocusStatus on iOS. */
fun statusText(context: Context, state: UiState): Pair<String, String?> {
    val phase = state.pomodoroPhase
    val plan = state.pomodoro
    return when {
        phase is PomodoroPlan.Phase.Focus && plan != null -> context.getString(R.string.status_pomodoro_focus) to
            context.getString(R.string.until_named, state.manualProfile?.name.orEmpty(), formatClock(context, phase.end))
        phase is PomodoroPlan.Phase.Rest && plan != null && !state.isBlocked -> context.getString(R.string.status_pomodoro_break) to
            context.getString(R.string.cycle_at, context.getString(R.string.cycle_of, phase.cycle + 2, plan.cycles), formatClock(context, phase.end))
        state.hasSession -> context.getString(R.string.status_session) to
            context.getString(R.string.until_named, state.manualProfile?.name.orEmpty(), formatClock(context, state.sessionEnd))
        state.isLocked -> context.getString(R.string.status_locked) to
            context.getString(R.string.until_key, state.manualProfile?.name.orEmpty())
        state.runningSchedules.isNotEmpty() -> {
            val schedule = state.runningSchedules.first()
            val end = FocusEngine.run { schedule.currentIntervalEnd(state.now.toLocalDateTime()).toEpochMillis() }
            context.getString(R.string.status_schedule) to context.getString(
                R.string.until_named,
                schedule.name.ifEmpty { context.getString(R.string.schedule_default_name) },
                formatClock(context, end),
            )
        }
        state.blockingLimitIds.isNotEmpty() -> {
            val limit = state.limits.first { it.id in state.blockingLimitIds }
            context.getString(R.string.status_limit) to context.getString(
                R.string.until_midnight, limit.name.ifEmpty { context.getString(R.string.limit_default_name) },
            )
        }
        else -> context.getString(R.string.status_unlocked) to null
    }
}

@Composable
private fun StatusCard(
    state: UiState,
    onAuthorize: () -> Unit,
    onUnlock: () -> Unit,
    onLock: () -> Unit,
    onLockFor: (Int) -> Unit,
    onCustom: () -> Unit,
    onPomodoro: () -> Unit,
    onExtend: (Int) -> Unit,
    onSkipBreak: () -> Unit,
    onExtendLimits: (Int) -> Unit,
) {
    val context = LocalContext.current
    val tint = profileColor((state.blockingProfile ?: state.activeProfile)?.colorName ?: "indigo")
    val (headline, detail) = statusText(context, state)
    val rest = (state.pomodoroPhase as? PomodoroPlan.Phase.Rest)?.takeIf { !state.isBlocked }

    FocusCard {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            LockRing(state, tint, rest)
            Text(headline, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
            detail?.let {
                Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
            }
        }

        if (!state.isAuthorized) {
            Button(onClick = onAuthorize, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = tint)) {
                Text(stringResource(R.string.authorize))
            }
            return@FocusCard
        }

        if (state.blockingLimitIds.isNotEmpty()) {
            MenuButton(
                label = stringResource(R.string.extend_with_key),
                icon = { Icon(Icons.Filled.AddCircleOutline, contentDescription = null) },
                options = listOf(5, 15, 30).map { "+" + formatMinutes(context, it) to { onExtendLimits(it) } },
                modifier = Modifier.fillMaxWidth(),
            )
        }

        if (state.canUnlockWithKey) {
            Button(onClick = onUnlock, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = tint)) {
                Icon(Icons.Filled.Nfc, contentDescription = null)
                Spacer(Modifier.size(8.dp))
                Text(stringResource(if (state.pomodoro != null) R.string.end_with_key else R.string.unlock_with_key))
            }
        }

        if (state.hasSession && state.pomodoro == null) {
            MenuButton(
                label = stringResource(R.string.extend_session),
                icon = { Icon(Icons.Filled.AddCircleOutline, contentDescription = null) },
                options = listOf(15, 30, 60).map { "+" + formatMinutes(context, it) to { onExtend(it) } },
                modifier = Modifier.fillMaxWidth(),
            )
        }

        if (rest != null) {
            OutlinedButton(onClick = onSkipBreak, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Filled.FastForward, contentDescription = null)
                Spacer(Modifier.size(8.dp))
                Text(stringResource(R.string.skip_break))
            }
        }

        if (!state.isLocked && state.pomodoro == null) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Button(onClick = onLock, modifier = Modifier.weight(1f), colors = ButtonDefaults.buttonColors(containerColor = tint)) {
                    Icon(Icons.Filled.Lock, contentDescription = null)
                    Spacer(Modifier.size(6.dp))
                    Text(stringResource(R.string.lock))
                }
                MenuButton(
                    label = stringResource(R.string.lock_for),
                    icon = { Icon(Icons.Filled.Timer, contentDescription = null) },
                    modifier = Modifier.weight(1f),
                    options = SESSION_OPTIONS.map { formatMinutes(context, it) to { onLockFor(it) } } +
                        listOf(
                            context.getString(R.string.other_duration) to onCustom,
                            context.getString(R.string.pomodoro_ellipsis) to onPomodoro,
                        ),
                )
            }
        }
    }
}

@Composable
private fun LockRing(state: UiState, tint: Color, rest: PomodoroPlan.Phase.Rest?) {
    val remaining = when {
        rest != null -> 1f - ((state.now - rest.start).toFloat() / (rest.end - rest.start)).coerceIn(0f, 1f)
        state.hasSession && state.sessionEnd > state.sessionStart ->
            1f - ((state.now - state.sessionStart).toFloat() / (state.sessionEnd - state.sessionStart)).coerceIn(0f, 1f)
        state.isBlocked -> 1f
        else -> 0f
    }
    val ringColor = if (rest != null) FocusColors.Green else tint
    Box(Modifier.size(140.dp), contentAlignment = Alignment.Center) {
        CircularProgressIndicator(
            progress = { 1f },
            modifier = Modifier.fillMaxSize(),
            color = ringColor.copy(alpha = 0.15f),
            strokeWidth = 10.dp,
            trackColor = Color.Transparent,
        )
        CircularProgressIndicator(
            progress = { remaining },
            modifier = Modifier.fillMaxSize(),
            color = ringColor,
            strokeWidth = 10.dp,
            trackColor = Color.Transparent,
        )
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(
                when {
                    rest != null -> Icons.Filled.Coffee
                    state.isBlocked -> Icons.Filled.Lock
                    else -> Icons.Filled.LockOpen
                },
                contentDescription = null,
                tint = if (state.isBlocked) tint else FocusColors.Green,
                modifier = Modifier.size(44.dp),
            )
            val end = rest?.end ?: state.sessionEnd.takeIf { state.hasSession }
            end?.let {
                Text(
                    countdown(it - state.now),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

/** "1:05:09" or "4:59". */
private fun countdown(millis: Long): String {
    val total = (millis / 1000).coerceAtLeast(0)
    val h = total / 3600
    val m = (total % 3600) / 60
    val s = total % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
}

/** Outlined button that opens a menu of options. */
@Composable
fun MenuButton(
    label: String,
    icon: @Composable () -> Unit,
    options: List<Pair<String, () -> Unit>>,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }
    Box(modifier) {
        OutlinedButton(onClick = { expanded = true }, modifier = Modifier.fillMaxWidth()) {
            icon()
            Spacer(Modifier.size(6.dp))
            Text(label)
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            options.forEach { (text, action) ->
                DropdownMenuItem(text = { Text(text) }, onClick = { expanded = false; action() })
            }
        }
    }
}

// MARK: - Quick sessions

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun PresetsCard(
    state: UiState,
    onStart: (SessionPreset) -> Unit,
    onBlocked: (Int) -> Unit,
    onEdit: (SessionPreset?) -> Unit,
    onDelete: (String) -> Unit,
) {
    val context = LocalContext.current
    // Starting is unavailable during another manual block or pomodoro; editing never is.
    val blockedReason = when {
        !state.isAuthorized -> R.string.preset_blocked_auth
        state.pomodoro != null -> R.string.preset_blocked_pomodoro
        state.isLocked -> R.string.preset_blocked_locked
        else -> null
    }
    FocusCard {
        CardHeader(
            title = stringResource(R.string.quick_sessions),
            subtitle = if (state.presets.isEmpty()) stringResource(R.string.quick_sessions_hint) else null,
        )
        val tiles = state.presets.map { it as SessionPreset? } + null
        tiles.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                row.forEach { preset ->
                    Box(Modifier.weight(1f)) {
                        if (preset == null) {
                            NewTile { onEdit(null) }
                        } else {
                            var menu by remember { mutableStateOf(false) }
                            val profile = state.profile(preset.profileId)
                            PresetTile(
                                preset = preset,
                                profile = profile,
                                dimmed = blockedReason != null,
                                modifier = Modifier.combinedClickable(
                                    onClick = { if (blockedReason != null) onBlocked(blockedReason) else onStart(preset) },
                                    onLongClick = { menu = true },
                                ),
                            )
                            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                                DropdownMenuItem(text = { Text(stringResource(R.string.edit)) }, onClick = { menu = false; onEdit(preset) })
                                DropdownMenuItem(
                                    text = { Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error) },
                                    onClick = { menu = false; onDelete(preset.id) },
                                )
                            }
                        }
                    }
                }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

@Composable
fun PresetTile(preset: SessionPreset, profile: Profile?, modifier: Modifier = Modifier, dimmed: Boolean = false) {
    val context = LocalContext.current
    val color = profileColor(profile?.colorName ?: "indigo")
    Column(
        modifier
            .fillMaxWidth()
            .height(68.dp)
            .background(color.copy(alpha = if (dimmed) 0.5f else 1f), RoundedCornerShape(Design.innerRadius))
            .padding(12.dp),
        verticalArrangement = Arrangement.SpaceBetween,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(profileIcon(profile?.icon ?: "shield"), contentDescription = null, tint = Color.White, modifier = Modifier.size(20.dp))
            Spacer(Modifier.weight(1f))
            Text(
                (if (preset.pomodoro != null) "⏱ " else "") + presetDuration(context, preset),
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Bold,
                color = Color.White,
                modifier = Modifier.background(Color.White.copy(alpha = 0.22f), CircleShape).padding(horizontal = 7.dp, vertical = 2.dp),
            )
        }
        Text(presetName(preset, profile), color = Color.White, fontWeight = FontWeight.SemiBold, maxLines = 1)
    }
}

@Composable
private fun NewTile(onClick: () -> Unit) {
    val accent = MaterialTheme.colorScheme.primary
    TextButton(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .height(68.dp)
            .border(1.5.dp, accent.copy(alpha = 0.6f), RoundedCornerShape(Design.innerRadius)),
    ) {
        Icon(Icons.Filled.Add, contentDescription = null)
        Spacer(Modifier.size(6.dp))
        Text(stringResource(R.string.new_item))
    }
}

// MARK: - Profile

@Composable
private fun ProfileCard(state: UiState, onSelect: (String) -> Unit, onManage: () -> Unit) {
    val context = LocalContext.current
    val locked = state.isLocked || state.pomodoro != null
    FocusCard {
        CardHeader(
            title = stringResource(R.string.profile_to_lock),
            subtitle = selectionSummary(context, state.activeProfile),
        ) {
            TextButton(onClick = onManage) { Text(stringResource(R.string.manage)) }
        }
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            state.profiles.forEach { profile ->
                val color = profileColor(profile.colorName)
                FilterChip(
                    selected = profile.id == state.activeProfileId,
                    enabled = !locked,
                    onClick = { onSelect(profile.id) },
                    label = { Text(profile.name) },
                    leadingIcon = { Icon(profileIcon(profile.icon), contentDescription = null, modifier = Modifier.size(18.dp)) },
                    colors = androidx.compose.material3.FilterChipDefaults.filterChipColors(
                        selectedContainerColor = color,
                        selectedLabelColor = Color.White,
                        selectedLeadingIconColor = Color.White,
                        iconColor = color,
                    ),
                )
            }
        }
    }
}

// MARK: - Dialogs

/** Picks a session length (15 min – 12 h). */
@Composable
fun DurationDialog(title: String, initial: Int = 45, onConfirm: (Int) -> Unit, onDismiss: () -> Unit) {
    val context = LocalContext.current
    var minutes by remember { mutableIntStateOf(initial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Stepper(formatMinutes(context, minutes), onMinus = { minutes = (minutes - 15).coerceAtLeast(FocusEngine.MINIMUM_SESSION_MINUTES) }, onPlus = { minutes = (minutes + 15).coerceAtMost(720) })
                Text(stringResource(R.string.session_footer, FocusEngine.MINIMUM_SESSION_MINUTES), style = MaterialTheme.typography.bodySmall)
            }
        },
        confirmButton = { TextButton(onClick = { onConfirm(minutes) }) { Text(stringResource(R.string.start)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

@Composable
fun PomodoroDialog(profile: Profile?, onStart: (Int, Int, Int) -> Unit, onDismiss: () -> Unit) {
    var focus by remember { mutableIntStateOf(25) }
    var rest by remember { mutableIntStateOf(5) }
    var cycles by remember { mutableIntStateOf(4) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.pomodoro)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                PomodoroFields(focus, rest, cycles, { focus = it }, { rest = it }, { cycles = it })
                Text(stringResource(R.string.pomodoro_footer, profile?.name.orEmpty()), style = MaterialTheme.typography.bodySmall)
            }
        },
        confirmButton = { TextButton(onClick = { onStart(focus, rest, cycles) }) { Text(stringResource(R.string.start)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

/** Focus, break and cycles pickers, shared by the pomodoro dialog and the preset editor. */
@Composable
fun PomodoroFields(
    focus: Int, rest: Int, cycles: Int,
    onFocus: (Int) -> Unit, onRest: (Int) -> Unit, onCycles: (Int) -> Unit,
) {
    val context = LocalContext.current
    OptionRow(stringResource(R.string.focus), PomodoroPlan.FOCUS_OPTIONS, focus, { formatMinutes(context, it) }, onFocus)
    OptionRow(stringResource(R.string.break_label), PomodoroPlan.BREAK_OPTIONS, rest, { formatMinutes(context, it) }, onRest)
    Stepper(
        context.resources.getQuantityString(R.plurals.cycles, cycles, cycles),
        onMinus = { onCycles((cycles - 1).coerceAtLeast(PomodoroPlan.CYCLE_RANGE.first)) },
        onPlus = { onCycles((cycles + 1).coerceAtMost(PomodoroPlan.CYCLE_RANGE.last)) },
    )
}

@Composable
fun <T> OptionRow(label: String, options: List<T>, selected: T, text: (T) -> String, onSelect: (T) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(label, style = MaterialTheme.typography.labelLarge)
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            options.forEach { option ->
                FilterChip(selected = option == selected, onClick = { onSelect(option) }, label = { Text(text(option)) })
            }
        }
    }
}

@Composable
fun Stepper(value: String, onMinus: () -> Unit, onPlus: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(value, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
        OutlinedButton(onClick = onMinus) { Text("−") }
        Spacer(Modifier.size(8.dp))
        OutlinedButton(onClick = onPlus) { Text("+") }
    }
}
