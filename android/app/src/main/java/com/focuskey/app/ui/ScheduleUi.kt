package com.focuskey.app.ui

import android.text.format.DateFormat
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import com.focuskey.app.data.Weekday
import java.time.LocalTime
import java.time.format.DateTimeFormatter

/** Formats a time following the phone's 12/24 h setting. */
@Composable
fun formatTime(time: LocalTime): String {
    val is24 = DateFormat.is24HourFormat(LocalContext.current)
    return time.format(DateTimeFormatter.ofPattern(if (is24) "HH:mm" else "h:mm a"))
}

@Composable
fun recurrenceSummary(repeats: Set<Weekday>, start: LocalTime, end: LocalTime): String {
    val days = Weekday.entries.filter { it in repeats }.joinToString(", ") { it.shortName }
    val recurrence = if (days.isEmpty()) "Sin días seleccionados" else "Se repite $days"
    val overnight = if (start > end) " (termina al día siguiente)" else ""
    return "$recurrence, de ${formatTime(start)} a ${formatTime(end)}$overnight."
}

/** Warns that saving/enabling will block apps right away and lock the schedule until it ends. */
@Composable
fun StartsNowDialog(endTime: LocalTime, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("El bloqueo empezará ahora") },
        text = {
            Text(
                "Este horario incluye la hora actual. Las apps se bloquearán ya y no podrás " +
                    "modificar ni desactivar el horario hasta las ${formatTime(endTime)}."
            )
        },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text("Bloquear ahora", color = MaterialTheme.colorScheme.error)
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancelar") } }
    )
}
