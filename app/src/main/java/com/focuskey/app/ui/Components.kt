package com.focuskey.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** Shared look, like App/DesignSystem.swift on iOS. */
object Design {
    val cardRadius = 24.dp
    val innerRadius = 14.dp
    val cardPadding = 18.dp
    val cardSpacing = 16.dp
    val contentSpacing = 14.dp
}

/** Card used by every tab. */
@Composable
fun FocusCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(Design.cardRadius),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    ) {
        Column(
            Modifier.padding(Design.cardPadding),
            verticalArrangement = Arrangement.spacedBy(Design.contentSpacing),
            content = content,
        )
    }
}

/** Title row of a card, with an optional trailing action. */
@Composable
fun CardHeader(title: String, subtitle: String? = null, trailing: @Composable () -> Unit = {}) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            subtitle?.let {
                Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        trailing()
    }
}

/** Profile icon on its color, used in every row that refers to a profile. */
@Composable
fun ProfileIcon(iconName: String, colorName: String, size: Dp = 40.dp, alpha: Float = 1f) {
    Box(
        Modifier
            .size(size)
            .background(profileColor(colorName).copy(alpha = alpha), RoundedCornerShape(size * 0.28f)),
        contentAlignment = Alignment.Center,
    ) {
        Icon(profileIcon(iconName), contentDescription = null, tint = Color.White, modifier = Modifier.size(size * 0.52f))
    }
}

/** Small capsule with a state ("Running", "On"…). */
@Composable
fun StatusBadge(text: String, color: Color) {
    Text(
        text,
        style = MaterialTheme.typography.labelMedium,
        fontWeight = FontWeight.SemiBold,
        color = color,
        modifier = Modifier
            .background(color.copy(alpha = 0.14f), CircleShape)
            .padding(horizontal = 9.dp, vertical = 4.dp),
    )
}
