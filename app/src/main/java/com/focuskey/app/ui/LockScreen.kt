package com.focuskey.app.ui

import android.content.Intent
import android.provider.Settings
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Nfc
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.focuskey.app.R
import com.focuskey.app.nfc.NfcKeyReader
import com.focuskey.app.ui.theme.FocusColors

/** Android version of ContentView.swift. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LockScreen(
    viewModel: FocusViewModel,
    nfcAvailability: () -> NfcKeyReader.Availability,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val status by viewModel.status.collectAsState()
    val isLocked by viewModel.isLocked.collectAsState()
    val isAuthorized by viewModel.isAuthorized.collectAsState()
    val selection by viewModel.selection.collectAsState()
    val now by viewModel.now.collectAsState()
    val schedules by viewModel.schedules.collectAsState()
    val nfcScanning by viewModel.nfcScanning.collectAsState()
    val nfcMessage by viewModel.nfcMessage.collectAsState()

    var showPicker by remember { mutableStateOf(false) }
    var showDisclosure by remember { mutableStateOf(false) }

    if (showPicker) {
        BackHandler { showPicker = false }
        AppPickerScreen(
            initial = selection,
            onDone = {
                viewModel.updateSelection(it)
                showPicker = false
            },
            onCancel = { showPicker = false },
            modifier = modifier
        )
        return
    }

    // `schedules` is read so the state recomputes when they change.
    val scheduleBlocking = remember(now, schedules, isLocked) { viewModel.isScheduleBlocking(now) }
    val blocked = isLocked || scheduleBlocking

    Scaffold(
        modifier = modifier,
        contentWindowInsets = WindowInsets(0),
        topBar = { TopAppBar(title = { Text("Concentración") }) }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp, vertical = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            Image(
                painter = painterResource(R.drawable.logo),
                contentDescription = null,
                modifier = Modifier.size(72.dp).clip(RoundedCornerShape(18.dp))
            )

            Text("FocusKey", style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)

            Text(status, textAlign = TextAlign.Center)

            Text(
                when {
                    isLocked -> "Bloqueado"
                    scheduleBlocking -> "Bloqueado por horario"
                    else -> "Desbloqueado"
                },
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = if (blocked) FocusColors.Red else FocusColors.Green
            )

            if (blocked) {
                OutlinedButton(onClick = { viewModel.startNfcScan(nfcAvailability()) }) {
                    Icon(Icons.Filled.Nfc, contentDescription = null)
                    Spacer(Modifier.size(8.dp))
                    Text("Desbloquear con NFC")
                }
            } else {
                OutlinedButton(onClick = viewModel::lock) { Text("Bloquear") }
            }

            if (!isAuthorized) {
                Button(onClick = { showDisclosure = true }) { Text("Autorizar bloqueo") }
            }

            OutlinedButton(onClick = { showPicker = true }) { Text("Seleccionar aplicaciones") }

            Text(
                selectionSummary(selection.apps.size, selection.categories.size, selection.domains.size),
                style = MaterialTheme.typography.bodyMedium,
                textAlign = TextAlign.Center
            )
        }
    }

    if (showDisclosure) {
        AlertDialog(
            onDismissRequest = { showDisclosure = false },
            title = { Text("Autorizar bloqueo") },
            text = {
                Text(
                    "FocusKey usa el servicio de accesibilidad de Android para saber qué app o web " +
                        "está en pantalla y bloquear las que hayas seleccionado. No recoge ni envía datos.\n\n" +
                        "En la siguiente pantalla, abre \"FocusKey – Bloqueo\" y actívalo."
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showDisclosure = false
                    context.startActivity(
                        Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                }) { Text("Abrir ajustes") }
            },
            dismissButton = {
                TextButton(onClick = { showDisclosure = false }) { Text("Ahora no") }
            }
        )
    }

    if (nfcScanning) {
        AlertDialog(
            onDismissRequest = viewModel::cancelNfcScan,
            icon = { Icon(Icons.Filled.Nfc, contentDescription = null) },
            title = { Text("Listo para escanear") },
            text = {
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text("Acerca tu etiqueta FocusKey a la parte trasera del teléfono.", textAlign = TextAlign.Center)
                    nfcMessage?.let {
                        Spacer(Modifier.height(12.dp))
                        Text(it, color = MaterialTheme.colorScheme.error, textAlign = TextAlign.Center)
                    }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onClick = viewModel::cancelNfcScan) { Text("Cancelar") } }
        )
    }
}

private fun selectionSummary(apps: Int, categories: Int, domains: Int): String {
    val parts = mutableListOf(plural(apps, "aplicación seleccionada", "aplicaciones seleccionadas"))
    if (categories > 0) parts += plural(categories, "categoría", "categorías")
    if (domains > 0) parts += plural(domains, "sitio web", "sitios web")
    return parts.joinToString(" · ")
}

private fun plural(count: Int, one: String, many: String) = "$count ${if (count == 1) one else many}"
