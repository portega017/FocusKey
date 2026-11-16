package com.focuskey.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.focuskey.app.R
import com.focuskey.app.data.AppCategory
import com.focuskey.app.data.Profile
import com.focuskey.app.data.SessionPreset
import com.focuskey.app.logic.FocusEngine
import com.focuskey.app.nfc.NfcKeyReader

/** Top bar with a back arrow and an optional action, for pushed screens. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SubScreen(
    title: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    action: @Composable () -> Unit = {},
    content: @Composable ColumnScope.() -> Unit,
) {
    Scaffold(
        modifier = modifier,
        contentWindowInsets = WindowInsets(0),
        topBar = {
            TopAppBar(
                title = { Text(title) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.back))
                    }
                },
                actions = { action() },
            )
        },
    ) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
            content = content,
        )
    }
}

/** Grouped section of a form, like an iOS Form section. */
@Composable
fun FormSection(title: String? = null, footer: String? = null, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        title?.let {
            Text(
                it.uppercase(),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp),
            )
        }
        Column(
            Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surface, RoundedCornerShape(Design.innerRadius)),
            content = content,
        )
        footer?.takeIf { it.isNotEmpty() }?.let {
            Text(
                it,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp),
            )
        }
    }
}

@Composable
fun FormRow(label: String, onClick: (() -> Unit)? = null, trailing: @Composable () -> Unit = {}) {
    Row(
        Modifier
            .fillMaxWidth()
            .let { if (onClick != null) it.clickable(onClick = onClick) else it }
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, modifier = Modifier.weight(1f))
        trailing()
    }
}

/** Dropdown to pick a profile. */
@Composable
fun ProfilePicker(profiles: List<Profile>, selectedId: String?, onSelect: (String) -> Unit) {
    profiles.forEachIndexed { index, profile ->
        if (index > 0) HorizontalDivider()
        Row(
            Modifier.fillMaxWidth().clickable { onSelect(profile.id) }.padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            ProfileIcon(profile.icon, profile.colorName, size = 30.dp)
            Text(profile.name, modifier = Modifier.weight(1f))
            if (profile.id == selectedId) Icon(Icons.Filled.Check, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
        }
    }
}

// MARK: - Profiles

@Composable
fun ProfilesScreen(viewModel: FocusViewModel, navigate: (Route) -> Unit, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    SubScreen(
        title = stringResource(R.string.profiles),
        onBack = onBack,
        modifier = modifier,
        action = {
            IconButton(onClick = { navigate(Route.ProfileEditor(null)) }) {
                Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.new_profile))
            }
        },
    ) {
        FormSection(footer = stringResource(R.string.profiles_footer)) {
            state.profiles.forEachIndexed { index, profile ->
                if (index > 0) HorizontalDivider()
                ListItem(
                    modifier = Modifier.clickable { navigate(Route.ProfileEditor(profile)) },
                    leadingContent = { ProfileIcon(profile.icon, profile.colorName, size = 36.dp) },
                    headlineContent = { Text(profile.name) },
                    supportingContent = { Text(selectionSummary(context, profile)) },
                    trailingContent = {
                        if (state.profiles.size > 1) {
                            IconButton(onClick = { viewModel.deleteProfile(profile.id) }) {
                                Icon(Icons.Filled.Delete, contentDescription = stringResource(R.string.delete))
                            }
                        }
                    },
                )
            }
        }
    }
}

@Composable
fun ProfileEditorScreen(viewModel: FocusViewModel, profile: Profile?, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    var draft by remember {
        mutableStateOf(profile ?: Profile(name = "", colorName = Profile.nextColor(state.profiles)))
    }
    var picking by remember { mutableStateOf(false) }
    val lockReason = profile?.let { viewModel.profileLockReason(it.id) }

    if (picking) {
        androidx.activity.compose.BackHandler { picking = false }
        AppPickerScreen(
            initial = draft.selection,
            onDone = { draft = draft.copy(selection = it); picking = false },
            onCancel = { picking = false },
            modifier = modifier,
        )
        return
    }

    SubScreen(
        title = stringResource(if (profile == null) R.string.new_profile else R.string.edit_profile),
        onBack = onBack,
        modifier = modifier,
        action = {
            TextButton(
                enabled = draft.name.isNotBlank(),
                onClick = { viewModel.saveProfile(draft.copy(name = draft.name.trim())); onBack() },
            ) { Text(stringResource(R.string.save)) }
        },
    ) {
        FormSection(stringResource(R.string.name)) {
            OutlinedTextField(
                value = draft.name,
                onValueChange = { draft = draft.copy(name = it) },
                placeholder = { Text(stringResource(R.string.profile_name_hint)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().padding(12.dp),
            )
        }
        FormSection(stringResource(R.string.color)) {
            Row(Modifier.fillMaxWidth().padding(12.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                Profile.COLORS.take(5).forEach { ColorDot(it, draft.colorName == it) { draft = draft.copy(colorName = it) } }
            }
            Row(Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, bottom = 12.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                Profile.COLORS.drop(5).forEach { ColorDot(it, draft.colorName == it) { draft = draft.copy(colorName = it) } }
            }
        }
        FormSection(stringResource(R.string.icon)) {
            Profile.ICONS.chunked(6).forEach { row ->
                Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                    row.forEach { icon ->
                        val selected = draft.icon == icon
                        Box(
                            Modifier
                                .size(40.dp)
                                .background(if (selected) profileColor(draft.colorName) else MaterialTheme.colorScheme.surfaceVariant, CircleShape)
                                .clickable { draft = draft.copy(icon = icon) },
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(profileIcon(icon), contentDescription = icon, tint = if (selected) Color.White else MaterialTheme.colorScheme.onSurface)
                        }
                    }
                }
            }
        }
        FormSection(stringResource(R.string.block), footer = lockReason ?: selectionSummary(context, draft)) {
            FormRow(stringResource(R.string.choose_apps), onClick = if (lockReason == null) ({ picking = true }) else null)
            draft.selection.categories.forEach {
                HorizontalDivider()
                FormRow(AppCategory.labelFor(context, it))
            }
            draft.selection.domains.forEach {
                HorizontalDivider()
                FormRow(it)
            }
        }
    }
}

@Composable
private fun ColorDot(name: String, selected: Boolean, onClick: () -> Unit) {
    Box(
        Modifier.size(38.dp).background(profileColor(name), CircleShape).clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        if (selected) Icon(Icons.Filled.Check, contentDescription = null, tint = Color.White)
    }
}

// MARK: - Presets

@Composable
fun PresetEditorScreen(viewModel: FocusViewModel, preset: SessionPreset?, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    var name by remember { mutableStateOf(preset?.name ?: "") }
    var profileId by remember { mutableStateOf(preset?.profileId ?: state.activeProfileId) }
    var isPomodoro by remember { mutableStateOf(preset?.pomodoro != null) }
    var minutes by remember { mutableIntStateOf(preset?.minutes ?: 60) }
    var pomodoro by remember { mutableStateOf(preset?.pomodoro ?: SessionPreset.PomodoroSettings()) }
    val profile = state.profile(profileId)
    val draft = SessionPreset(
        id = preset?.id ?: java.util.UUID.randomUUID().toString(),
        name = name.trim(),
        profileId = profile?.id.orEmpty(),
        minutes = minutes,
        pomodoro = if (isPomodoro) pomodoro else null,
    )

    SubScreen(
        title = stringResource(if (preset == null) R.string.new_quick_session else R.string.edit_quick_session),
        onBack = onBack,
        modifier = modifier,
        action = {
            TextButton(enabled = profile != null, onClick = { viewModel.savePreset(draft); onBack() }) {
                Text(stringResource(R.string.save))
            }
        },
    ) {
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            SegmentedButton(selected = !isPomodoro, onClick = { isPomodoro = false }, shape = SegmentedButtonDefaults.itemShape(0, 2)) {
                Text(stringResource(R.string.session))
            }
            SegmentedButton(selected = isPomodoro, onClick = { isPomodoro = true }, shape = SegmentedButtonDefaults.itemShape(1, 2)) {
                Text(stringResource(R.string.pomodoro))
            }
        }
        FormSection(stringResource(R.string.what_to_block), footer = selectionSummary(context, profile)) {
            ProfilePicker(state.profiles, profile?.id) { profileId = it }
        }
        if (isPomodoro) {
            val total = pomodoro.cycles * pomodoro.focusMinutes + (pomodoro.cycles - 1) * pomodoro.breakMinutes
            FormSection(
                stringResource(R.string.pomodoro),
                footer = stringResource(R.string.pomodoro_preset_footer, formatMinutes(context, pomodoro.focusMinutes * pomodoro.cycles), formatMinutes(context, total)),
            ) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    PomodoroFields(
                        pomodoro.focusMinutes, pomodoro.breakMinutes, pomodoro.cycles,
                        { pomodoro = pomodoro.copy(focusMinutes = it) },
                        { pomodoro = pomodoro.copy(breakMinutes = it) },
                        { pomodoro = pomodoro.copy(cycles = it) },
                    )
                }
            }
        } else {
            FormSection(stringResource(R.string.duration)) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    OptionRow("", SessionPreset.DURATION_OPTIONS, minutes, { formatMinutes(context, it) }) { minutes = it }
                    Stepper(
                        formatMinutes(context, minutes),
                        onMinus = { minutes = (minutes - 15).coerceAtLeast(FocusEngine.MINIMUM_SESSION_MINUTES) },
                        onPlus = { minutes = (minutes + 15).coerceAtMost(720) },
                    )
                }
            }
        }
        FormSection(stringResource(R.string.name), footer = stringResource(R.string.preset_name_footer)) {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                placeholder = { Text(profile?.name.orEmpty()) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().padding(12.dp),
            )
        }
        FormSection(stringResource(R.string.preview)) {
            Box(Modifier.padding(12.dp)) { PresetTile(draft, profile) }
        }
    }
}

// MARK: - Settings

@Composable
fun SettingsScreen(viewModel: FocusViewModel, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val state by viewModel.state.collectAsState()
    SubScreen(stringResource(R.string.settings), onBack, modifier) {
        FormSection(stringResource(R.string.strict_mode), footer = stringResource(R.string.strict_footer)) {
            FormRow(stringResource(R.string.strict_mode)) {
                Switch(checked = state.strictMode, onCheckedChange = viewModel::setStrictMode)
            }
        }
        val context = LocalContext.current
        FormSection(stringResource(R.string.protection), footer = stringResource(R.string.protection_footer)) {
            FormRow(stringResource(R.string.prevent_removal)) {
                Switch(checked = state.preventRemoval, onCheckedChange = { enable ->
                    if (enable) {
                        val admin = android.content.ComponentName(context, com.focuskey.app.admin.FocusAdminReceiver::class.java)
                        context.startActivity(
                            android.content.Intent(android.app.admin.DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
                                .putExtra(android.app.admin.DevicePolicyManager.EXTRA_DEVICE_ADMIN, admin)
                                .putExtra(android.app.admin.DevicePolicyManager.EXTRA_ADD_EXPLANATION, context.getString(R.string.protection_explanation))
                        )
                    } else {
                        viewModel.disablePreventRemoval()
                    }
                })
            }
        }
        FormSection(stringResource(R.string.notification_section), footer = stringResource(R.string.live_footer)) {
            FormRow(stringResource(R.string.live_toggle)) {
                Switch(checked = state.liveNotification, onCheckedChange = viewModel::setLiveNotification)
            }
            HorizontalDivider()
            FormRow(stringResource(R.string.limit_warnings)) {
                Switch(checked = state.limitWarnings, onCheckedChange = viewModel::setLimitWarnings)
            }
        }
        FormSection(stringResource(R.string.usage_access_title), footer = stringResource(R.string.usage_access_text)) {
            FormRow(
                stringResource(if (state.hasUsageAccess) R.string.usage_access_on else R.string.usage_access_off),
                onClick = {
                    context.startActivity(android.content.Intent(android.provider.Settings.ACTION_USAGE_ACCESS_SETTINGS).addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK))
                },
            )
        }
        FormSection(stringResource(R.string.nfc_key), footer = stringResource(R.string.nfc_key_footer)) {
            FormRow(stringResource(R.string.tag_text)) {
                Text(NfcKeyReader.KEY_TEXT, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}
