package com.focuskey.app.ui

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.focuskey.app.R
import java.time.LocalTime

/** Warns that saving/enabling will block apps right away and lock the schedule until it ends. */
@Composable
fun StartsNowDialog(endTime: LocalTime, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    val context = LocalContext.current
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.starts_now_title)) },
        text = { Text(stringResource(R.string.starts_now_text, formatTime(context, endTime))) },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text(stringResource(R.string.lock_now), color = MaterialTheme.colorScheme.error)
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}
