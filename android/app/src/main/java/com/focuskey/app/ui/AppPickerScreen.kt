package com.focuskey.app.ui

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.core.graphics.drawable.toBitmap
import com.focuskey.app.data.AppCategory
import com.focuskey.app.data.Selection
import com.focuskey.app.data.normalizeDomain
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private data class InstalledApp(
    val packageName: String,
    val name: String,
    val category: Int,
    val icon: ImageBitmap?,
)

/** Android version of the FamilyActivityPicker: apps, categories and websites. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppPickerScreen(
    initial: Selection,
    onDone: (Selection) -> Unit,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var apps by remember { mutableStateOf(initial.apps) }
    var categories by remember { mutableStateOf(initial.categories) }
    var domains by remember { mutableStateOf(initial.domains) }
    var tab by rememberSaveable { mutableIntStateOf(0) }

    Scaffold(
        modifier = modifier,
        contentWindowInsets = WindowInsets(0),
        topBar = {
            TopAppBar(
                title = { Text("Seleccionar") },
                navigationIcon = {
                    IconButton(onClick = onCancel) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Cancelar")
                    }
                },
                actions = {
                    TextButton(onClick = { onDone(Selection(apps, categories, domains)) }) { Text("Listo") }
                }
            )
        }
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            TabRow(selectedTabIndex = tab) {
                Tab(selected = tab == 0, onClick = { tab = 0 }, text = { Text("Apps (${apps.size})") })
                Tab(selected = tab == 1, onClick = { tab = 1 }, text = { Text("Categorías (${categories.size})") })
                Tab(selected = tab == 2, onClick = { tab = 2 }, text = { Text("Webs (${domains.size})") })
            }
            when (tab) {
                0 -> AppsTab(apps) { pkg, selected -> apps = if (selected) apps + pkg else apps - pkg }
                1 -> CategoriesTab(categories) { id, selected ->
                    categories = if (selected) categories + id else categories - id
                }
                else -> DomainsTab(domains, onAdd = { domains = domains + it }, onRemove = { domains = domains - it })
            }
        }
    }
}

@Composable
private fun AppsTab(selected: Set<String>, onToggle: (String, Boolean) -> Unit) {
    val context = LocalContext.current
    val installed by produceState<List<InstalledApp>?>(initialValue = null) {
        value = withContext(Dispatchers.IO) { loadInstalledApps(context) }
    }
    var query by rememberSaveable { mutableStateOf("") }

    Column(Modifier.fillMaxSize()) {
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            placeholder = { Text("Buscar aplicaciones") },
            leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
            singleLine = true
        )

        val list = installed
        if (list == null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    CircularProgressIndicator()
                    Spacer(Modifier.size(12.dp))
                    Text("Cargando aplicaciones...")
                }
            }
        } else {
            AppList(list, query, selected, onToggle)
        }
    }
}

@Composable
private fun AppList(
    list: List<InstalledApp>,
    query: String,
    selected: Set<String>,
    onToggle: (String, Boolean) -> Unit,
) {
    val filtered = list.filter {
        query.isBlank() || it.name.contains(query, ignoreCase = true) ||
            it.packageName.contains(query, ignoreCase = true)
    }
    LazyColumn(Modifier.fillMaxSize()) {
        items(filtered, key = { it.packageName }) { app ->
            val isSelected = app.packageName in selected
            ListItem(
                modifier = Modifier.clickable { onToggle(app.packageName, !isSelected) },
                leadingContent = {
                    app.icon?.let {
                        Image(it, contentDescription = null, modifier = Modifier.size(40.dp).clip(RoundedCornerShape(8.dp)))
                    }
                },
                headlineContent = { Text(app.name) },
                supportingContent = {
                    Text(
                        if (app.category != ApplicationInfo.CATEGORY_UNDEFINED) AppCategory.labelFor(app.category)
                        else app.packageName,
                        style = MaterialTheme.typography.bodySmall
                    )
                },
                trailingContent = {
                    Checkbox(checked = isSelected, onCheckedChange = { onToggle(app.packageName, it) })
                }
            )
        }
    }
}

@Composable
private fun CategoriesTab(selected: Set<Int>, onToggle: (Int, Boolean) -> Unit) {
    LazyColumn(Modifier.fillMaxSize()) {
        item {
            Text(
                "Bloquea todas las apps de una categoría, incluidas las que instales más tarde. " +
                    "La categoría la define cada app; algunas no indican ninguna.",
                modifier = Modifier.padding(16.dp),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        items(AppCategory.entries, key = { it.id }) { category ->
            val isSelected = category.id in selected
            ListItem(
                modifier = Modifier.clickable { onToggle(category.id, !isSelected) },
                headlineContent = { Text(category.label) },
                trailingContent = {
                    Checkbox(checked = isSelected, onCheckedChange = { onToggle(category.id, it) })
                }
            )
        }
    }
}

@Composable
private fun DomainsTab(domains: Set<String>, onAdd: (String) -> Unit, onRemove: (String) -> Unit) {
    var input by rememberSaveable { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }

    fun add() {
        val domain = normalizeDomain(input)
        if (domain == null) {
            error = "Escribe un dominio válido, por ejemplo youtube.com"
        } else {
            onAdd(domain)
            input = ""
            error = null
        }
    }

    val currentError = error
    LazyColumn(Modifier.fillMaxSize()) {
        item {
            Row(
                modifier = Modifier.fillMaxWidth().padding(16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OutlinedTextField(
                    value = input,
                    onValueChange = { input = it; error = null },
                    modifier = Modifier.weight(1f),
                    placeholder = { Text("ejemplo.com") },
                    singleLine = true,
                    isError = error != null,
                    supportingText = if (currentError != null) {
                        { Text(currentError) }
                    } else {
                        null
                    },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { add() })
                )
                Button(onClick = ::add) { Text("Añadir") }
            }
            Text(
                "Se bloquea el dominio y sus subdominios en Chrome, Firefox, Edge, Brave, Samsung Internet, Opera y DuckDuckGo.",
                modifier = Modifier.padding(horizontal = 16.dp),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            HorizontalDivider(Modifier.padding(top = 16.dp))
        }
        items(domains.sorted(), key = { it }) { domain ->
            ListItem(
                leadingContent = { Icon(Icons.Filled.Language, contentDescription = null) },
                headlineContent = { Text(domain) },
                trailingContent = {
                    IconButton(onClick = { onRemove(domain) }) {
                        Icon(Icons.Filled.Delete, contentDescription = "Eliminar $domain")
                    }
                }
            )
        }
    }
}

private fun loadInstalledApps(context: Context): List<InstalledApp> {
    val pm = context.packageManager
    val launcherIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
    val iconSize = (40 * context.resources.displayMetrics.density).toInt()
    return pm.queryIntentActivities(launcherIntent, 0)
        .map { it.activityInfo.applicationInfo }
        .distinctBy { it.packageName }
        .filter { it.packageName != context.packageName }
        .map { info ->
            InstalledApp(
                packageName = info.packageName,
                name = pm.getApplicationLabel(info).toString(),
                category = info.category,
                icon = runCatching {
                    pm.getApplicationIcon(info).toBitmap(iconSize, iconSize).asImageBitmap()
                }.getOrNull()
            )
        }
        .sortedBy { it.name.lowercase() }
}
