package com.adamhunt.retroguide.ui.settings

import android.app.Activity
import com.adamhunt.retroguide.purchases.ProStore
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.tv.material3.Text
import com.adamhunt.retroguide.AppModel
import com.adamhunt.retroguide.ui.components.Note
import com.adamhunt.retroguide.ui.components.RetroButton
import com.adamhunt.retroguide.ui.components.RetroRow
import com.adamhunt.retroguide.ui.components.SectionHeader
import com.adamhunt.retroguide.ui.theme.LocalTheme
import com.adamhunt.retroguide.ui.theme.ThemePalettes
import com.adamhunt.retroguide.ui.theme.Tokens
import com.adamhunt.retroguide.ui.theme.Typography
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** What RetroGuide Pro adds (the Apple app's `ProBenefit.all`, for Android TV). */
private val PRO_BENEFITS = listOf(
    "Favorite channels" to "Star your channels and browse or surf just your Favorites.",
    "Program reminders" to "Choose upcoming airings and get a reminder when they start.",
    "Multiple servers" to "Blend your server and ones shared with you into one lineup.",
    "Unlimited custom channels" to "Build as many of your own channels as you like.",
    "Every theme" to "${ThemePalettes.size} looks, from Local Forecast to Teletext.",
    "Schedule controls" to "Pick each channel's order and start programs on the hour and half hour.",
)

/** What RetroGuide Pro includes, with the purchase and restore buttons (the Apple app's `ProUpgradeView`). */
@Composable
fun ProPage(app: AppModel) {
    val theme = LocalTheme.current
    val activity = LocalContext.current as? Activity
    val isPro by app.isPro.collectAsState()
    val price by app.pro.price.collectAsState()
    val isLoading by app.pro.isLoadingProduct.collectAsState()
    val state by app.pro.state.collectAsState()
    LaunchedEffect(Unit) { app.pro.loadProductIfNeeded() }
    SettingsPage("RetroGuide Pro") {
        item {
            Note(if (isPro) "You have RetroGuide Pro. Thank you for supporting the app!" else "One purchase, no subscription. It unlocks Pro on every Android device signed in to your Google account.")
        }
        item { SectionHeader("Included") }
        items(PRO_BENEFITS, key = { it.first }) { (title, detail) ->
            // Focusable so the remote can scroll the list.
            RetroRow(title, {}, detail = detail, maxLines = Int.MAX_VALUE)
        }
        if (!isPro) {
            item {
                val title = price?.let { "★ Upgrade for $it" } ?: if (isLoading) "Contacting Google Play…" else "Couldn't reach Google Play"
                RetroButton(title, { activity?.let(app.pro::purchase) }, isPrimary = true,
                    enabled = price != null && state != ProStore.PurchaseState.Purchasing)
            }
            if (price == null && !isLoading) item { RetroButton("Try Again", app.pro::loadProductIfNeeded) }
            item { RetroButton("Restore Purchase", app.pro::restore) }
            val status = when (val current = state) {
                ProStore.PurchaseState.Idle -> null
                ProStore.PurchaseState.Purchasing -> "Contacting Google Play…"
                ProStore.PurchaseState.Pending -> "Waiting for the payment to go through. Pro unlocks as soon as it does."
                is ProStore.PurchaseState.Failed -> "The purchase didn't go through: ${current.message}"
            }
            status?.let { item { Text(it, style = Typography.caption, color = theme.textSecondary) } }
        }
    }
}

/** A library bundled in the app and its license. */
private data class Component(val name: String, val license: String, val source: String)

private val COMPONENTS = listOf(
    Component("libmpv for Android", "MIT License", "github.com/jarnedemeulemeester/libmpv-android"),
    Component("mpv", "GNU LGPL (via libmpv)", "mpv.io"),
    Component("FFmpeg", "GNU LGPL (via libmpv)", "ffmpeg.org"),
    Component("Swift runtime and Foundation", "Apache License 2.0 with Runtime Library Exception", "swift.org"),
    Component("AndroidX and Jetpack Compose", "Apache License 2.0", "developer.android.com/jetpack"),
    Component("Kotlin coroutines and serialization", "Apache License 2.0", "github.com/Kotlin"),
    Component("Coil", "Apache License 2.0", "coil-kt.github.io/coil"),
    Component("OkHttp", "Apache License 2.0", "square.github.io/okhttp"),
    Component("ZXing", "Apache License 2.0", "github.com/zxing/zxing"),
    Component("Mozilla CA certificate list", "Mozilla Public License 2.0", "curl.se/docs/caextract.html"),
)

/** The LGPL's text, from the app's assets. */
private const val LGPL_ASSET = "LGPL-3.0.txt"

/** Open-source notices for software bundled in the app (required by the LGPL). */
@Composable
fun AcknowledgementsPage() {
    val context = LocalContext.current
    var paragraphs by remember { mutableStateOf<List<String>>(emptyList()) }
    LaunchedEffect(Unit) {
        paragraphs = withContext(Dispatchers.IO) {
            runCatching { context.assets.open(LGPL_ASSET).bufferedReader().use { it.readText() } }.getOrDefault("")
                .split("\n\n").map(String::trim).filter(String::isNotEmpty)
        }
    }
    SettingsPage("Acknowledgements") {
        item {
            Note("RetroGuide.TV is open-source software under the MIT License. Video playback uses the following libraries. You can rebuild the app with modified versions of them from the public source code.")
        }
        item { SectionHeader("Libraries") }
        items(COMPONENTS, key = { it.name }) { component ->
            RetroRow(component.name, {}, detail = "${component.license} · ${component.source}", maxLines = Int.MAX_VALUE)
        }
        item { SectionHeader("GNU Lesser General Public License v3.0") }
        items(paragraphs.size) { index ->
            RetroRow(paragraphs[index], {}, maxLines = Int.MAX_VALUE, titleStyle = Typography.micro)
        }
    }
}
