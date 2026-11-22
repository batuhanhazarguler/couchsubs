// SPDX-License-Identifier: AGPL-3.0-only
// Profil (cihazlar ve tercihler; hesap yok) ve ayarlar (tuval: Telefon-Profil, -Ayarlar).
package com.couchsubs.mobile.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.couchsubs.mobile.BuildConfig
import com.couchsubs.mobile.R
import com.couchsubs.mobile.Services
import com.couchsubs.mobile.account.Backend
import com.couchsubs.mobile.core.SubtitleBackgroundShape
import com.couchsubs.mobile.core.SubtitlePlacement
import com.couchsubs.mobile.core.SubtitleTextColor
import com.couchsubs.mobile.core.TvDisplayMode
import com.couchsubs.mobile.remoteplay.LoginPasscode
import com.couchsubs.mobile.service.TranslationService
import com.couchsubs.mobile.settings.AppSettings
import com.couchsubs.mobile.settings.EngineChoice
import com.couchsubs.mobile.settings.SubtitleTarget
import com.couchsubs.mobile.translation.AiModel
import com.couchsubs.mobile.translation.AiRequest
import com.couchsubs.mobile.translation.AiProvider
import com.couchsubs.mobile.translation.DeepLKey
import com.couchsubs.mobile.translation.KeyCheck
import com.couchsubs.mobile.translation.OnlineKeyState
import com.couchsubs.mobile.translation.aiProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.couchsubs.mobile.tv.FoundTv
import com.couchsubs.mobile.tv.TvDiscovery


/**
 * Profil (tuval Telefon-Profil, hesapsız): cihazlar (PS5, TV'ler), ikinci PSN hesabı, bildirimler, küçük pencere ve
 * gizlilik. Ayarlar (havuz, kullanım verisi, deneysel ayarlar…) Mac'teki gibi Ayarlar'ın bölümlerinde (iPhone ile aynı).
 */
@Composable
fun ProfileScreen(onBack: () -> Unit, onSettings: () -> Unit, onPairing: () -> Unit, onTarget: () -> Unit, onPsn: () -> Unit) {
    val context = LocalContext.current
    val settings = Services.settings
    var tvs by remember { mutableStateOf<List<FoundTv>?>(null) }
    var notifyDisconnect by remember { mutableStateOf(settings.notifyDisconnect) }
    var notifyPacks by remember { mutableStateOf(settings.notifyNewPacks) }
    var backgroundPip by remember { mutableStateOf(settings.backgroundPip) }
    LaunchedEffect(Unit) { tvs = withContext(Dispatchers.IO) { runCatching { TvDiscovery.search() }.getOrDefault(emptyList()) } }
    ScreenScaffold(top = { TopBar(stringResource(R.string.profile), onBack = onBack) { SettingsAction(onSettings) } }) {
        TwoColumns(
            { StatusTile(CouchIcons.Gamepad, "PS5", settings.console?.name ?: stringResource(R.string.profile_not_paired), it,
                corner = { if (settings.console != null) StatusLabel(stringResource(R.string.main_paired)) }, chevron = true, onClick = onPairing) },
            { StatusTile(Icons.Filled.Person, stringResource(R.string.profile_psn),
                stringResource(if (settings.accountId != null) R.string.profile_psn_linked_short else R.string.profile_psn_missing), it,
                chevron = true, onClick = onPsn) },
        )
        Tile(Modifier.fillMaxWidth(), onClick = onTarget) {
            TileLabel(stringResource(R.string.profile_tvs))
            Text(targetName(settings), style = Tokens.Type.title, color = Tokens.Color.text)
            when (val found = tvs) {
                null -> Text(stringResource(R.string.target_searching), style = Tokens.Type.caption, color = Tokens.Color.secondary)
                else -> Text(if (found.isEmpty()) stringResource(R.string.target_tvs_none) else found.joinToString { "${it.name} (${brandName(it.brand)})" },
                    style = Tokens.Type.caption, color = Tokens.Color.secondary)
            }
        }
        RowList(listOf(
            { RowItem(stringResource(R.string.notify_disconnect)) { Switch(notifyDisconnect, { notifyDisconnect = it; settings.notifyDisconnect = it }) } },
            // iPhone ile aynı ad ve açıklama (orada Resim içinde resim penceresi çeviriyi ayakta tutar).
            { RowItem(stringResource(R.string.settings_background_pip), stringResource(R.string.settings_background_pip_short)) {
                Switch(backgroundPip, { backgroundPip = it; settings.backgroundPip = it })
            } },
            { RowItem(stringResource(R.string.notify_packs)) { Switch(notifyPacks, { notifyPacks = it; settings.notifyNewPacks = it }) } },
        ))
        RowList(listOf(
            { RowItem(stringResource(R.string.profile_privacy), onClick = { open(context, context.getString(R.string.url_privacy)) }) },
            { RowItem(stringResource(R.string.profile_help), onClick = { open(context, context.getString(R.string.url_help)) }) },
        ))
        Text(stringResource(R.string.profile_no_account), style = Tokens.Type.caption, color = Tokens.Color.secondary)
        DeveloperSignature()
    }
}

/**
 * Ayarlar: Mac'in yeni arayüzündeki bölümler aynı ad, alt yazı ve sırayla (iPhone ile aynı; Klavye Kısayolları telefonda
 * yok). Bölüme dokununca o bölümün sayfası açılır (bkz. SettingsPages.kt); geri tuşu bölüm listesine döner.
 */
@Composable
fun SettingsScreen(onBack: () -> Unit, onPacks: () -> Unit, onTarget: () -> Unit, onPairing: () -> Unit, onTvInstall: () -> Unit = {},
                   onPlatform: () -> Unit = {}, onDemo: () -> Unit = {}) {
    var section by androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf<String?>(null) }
    val open = section?.let { name -> SettingsSection.entries.firstOrNull { it.name == name } }
    if (open != null) {
        androidx.activity.compose.BackHandler { section = null }
        SettingsPage(open, onBack = { section = null }, onOpen = { section = it.name }, onPacks = onPacks, onTarget = onTarget,
            onPairing = onPairing, onTvInstall = onTvInstall, onPlatform = onPlatform, onDemo = onDemo)
        return
    }
    var showAbout by remember { mutableStateOf(false) }
    ScreenScaffold(top = { TopBar(stringResource(R.string.settings), onBack = onBack) }) {
        RowList(SettingsSection.entries.map { item ->
            { RowItem(stringResource(item.title), stringResource(item.hint), onClick = { section = item.name }) }
        })
        RowList(listOf { RowItem(stringResource(R.string.settings_about), BuildConfig.VERSION_NAME, onClick = { showAbout = true }) })
        if (showAbout) AboutDialog { showAbout = false }
        Text(stringResource(R.string.settings_copyright), style = Tokens.Type.caption, color = Tokens.Color.secondary,
            modifier = Modifier.padding(top = Tokens.Space.inline))
        DeveloperSignature()
    }
}

/**
 * Yapay zekâ modeli: Gemini, OpenAI ve Claude (Mac ve Windows'taki Model seçimi, iPhone ile aynı). Seçenekler ortak
 * ai-models.json'dan gelir, ilki varsayılandır. Kayıt "geminiModel" / "openAIModel" / "claudeModel" adıyla tutulur;
 * Gemini'de dakikalık istek hakkı seçilen modelin sınırıdır.
 */
@Composable
internal fun AiModelChoice(settings: AppSettings, provider: AiProvider) {
    val context = LocalContext.current
    val models = remember(provider) { AiModel.load(context)[provider.id].orEmpty() }
    if (models.isEmpty()) return
    var selected by remember(provider) { mutableStateOf(AiModel.selected(models, settings.aiModel(provider))!!.id) }
    TileLabel(stringResource(R.string.settings_model))
    Segmented(models.map { modelLabel(it) }, models.indexOfFirst { it.id == selected }.coerceAtLeast(0)) { index ->
        selected = models[index].id
        settings.setAiModel(provider, selected)
    }
    Text(selected, style = Tokens.Type.caption, color = Tokens.Color.secondary)
}

/**
 * Ek talimat (#306; iPhone, Mac ve Windows ile aynı): yapay zekâ çevirmeninin talimatının sonuna eklenir, boşsa hiçbir
 * şey değişmez. Yazıldıkça kaydedilir; çeviri sürerken de sonraki istekten itibaren yeni talimat kullanılır.
 */
@Composable
internal fun AiInstructionField(settings: AppSettings) {
    var text by remember { mutableStateOf(settings.aiInstruction) }
    Field(text, { value ->
        text = value.take(AiRequest.MAX_INSTRUCTION_LENGTH)
        settings.aiInstruction = text
    }, stringResource(R.string.settings_instruction), lines = 3, placeholder = stringResource(R.string.settings_instruction_example))
    Text(stringResource(R.string.settings_instruction_note), style = Tokens.Type.caption, color = Tokens.Color.secondary)
}

/** Modelin kısa açıklaması; listedeki açıklama (label) tanınmazsa olduğu gibi gösterilir. */
@Composable
private fun modelLabel(model: AiModel): String = when (model.label) {
    "Fast and cheap (recommended)" -> stringResource(R.string.settings_model_fast)
    "Better quality, a little slower" -> stringResource(R.string.settings_model_quality)
    else -> model.label
}


/**
 * PSN'den çıkış (iPhone signOutPSN ile aynı): çeviri durur; ikinci hesabın kimliği, PS5 eşleşmesi (PS5 o hesaba bağlıdır)
 * ve giriş şifresi bu telefondan silinir. TV ve çeviri ayarları kalır. Yanlış hesapla giren kurulumu baştan almak zorundaydı.
 */
@Composable
internal fun PsnSignOutRow() {
    val context = LocalContext.current
    val settings = Services.settings
    var linked by remember { mutableStateOf(settings.accountId != null || settings.console != null) }
    var confirm by remember { mutableStateOf(false) }
    if (settings.xbox || !linked) return
    Tile(Modifier.fillMaxWidth()) {
        RowItem(stringResource(R.string.psn_sign_out), onClick = { confirm = true })
    }
    if (confirm) androidx.compose.material3.AlertDialog(
        onDismissRequest = { confirm = false },
        title = { Text(stringResource(R.string.psn_sign_out_title)) },
        text = { Text(stringResource(R.string.psn_sign_out_body)) },
        confirmButton = {
            androidx.compose.material3.TextButton({
                confirm = false
                TranslationService.stop(context)
                settings.accountId = null
                settings.console = null
                settings.loginPasscode = null
                linked = false
            }) { Text(stringResource(R.string.psn_sign_out_confirm), color = Tokens.Color.danger) }
        },
        dismissButton = { androidx.compose.material3.TextButton({ confirm = false }) { Text(stringResource(R.string.cancel)) } },
        containerColor = Tokens.Color.surface2,
    )
}

/** Hakkında (iPhone AboutScreen ile aynı): sürüm, lisans, Remote Play teşekkürü ve kaynak kodu bağlantısı. */
@Composable
private fun AboutDialog(onDismiss: () -> Unit) {
    val context = LocalContext.current
    androidx.compose.material3.AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("CouchSubs ${BuildConfig.VERSION_NAME}") },
        text = {
            Column(verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(Tokens.Space.inline)) {
                Text("Copyright © 2026 Sinan Yorulmaz", style = Tokens.Type.caption, color = Tokens.Color.secondary)
                Text(stringResource(R.string.about_body), style = Tokens.Type.body, color = Tokens.Color.secondary)
                // Uygulamanın günlükleri tek dosyada, kişisel veri maskelenmiş (iPhone'da da aynı; masaüstünde "Günlük
                // dosyasını göster").
                androidx.compose.material3.OutlinedButton({ shareLogs(context) }) { Text(stringResource(R.string.share_logs)) }
                Text(stringResource(R.string.share_logs_note), style = Tokens.Type.caption, color = Tokens.Color.secondary)
            }
        },
        confirmButton = {
            androidx.compose.material3.TextButton({ open(context, context.getString(R.string.url_source)) }) { Text(stringResource(R.string.about_source)) }
        },
        dismissButton = { androidx.compose.material3.TextButton(onDismiss) { Text(stringResource(R.string.close)) } },
        containerColor = Tokens.Color.surface2,
    )
}

/** Xbox seçiliyken ve giriş yapılmışken Microsoft hesabından çıkış (jeton Keystore'dan silinir). */
@Composable
internal fun XboxSignOutRow() {
    val settings = Services.settings
    var signedIn by remember { mutableStateOf(Services.xboxAuth.signedIn) }
    if (!settings.xbox || !signedIn) return
    Tile(Modifier.fillMaxWidth()) {
        RowItem(stringResource(R.string.xbox_sign_out), onClick = {
            Services.xboxAuth.signOut()
            signedIn = false
        })
    }
}

/**
 * DeepL anahtarının bu ayki kullanımı: "Bu ay: 500.000 karakterin 12.345 kadarı kullanıldı." (Mac, Windows ve iPhone ile
 * aynı metin). Ayarlar açılınca ve anahtar kaydedilince sorulur; sorgu karakter kotasından yemez.
 */
@Composable
internal fun DeepLUsageNote(settings: AppSettings) {
    var usage by remember { mutableStateOf<KeyCheck.DeepLUsage?>(null) }
    LaunchedEffect(Unit) {
        val key = settings.apiKey(EngineChoice.DEEPL)
        usage = if (key.isNullOrBlank()) null else withContext(Dispatchers.IO) { KeyCheck.deepLUsage(key) }
    }
    usage?.let { Text(deepLUsageText(it), style = Tokens.Type.caption, color = Tokens.Color.secondary) }
}

@Composable
internal fun deepLUsageText(usage: KeyCheck.DeepLUsage): String = when {
    // Mac/iPhone'daki DeepLUsageText ve Windows'taki ShowDeepLStatus ile aynı metinler.
    usage.state == OnlineKeyState.VALID && usage.limit >= KeyCheck.UNLIMITED ->
        stringResource(R.string.deepl_usage_unlimited, "%,d".format(usage.used))
    usage.state == OnlineKeyState.VALID && usage.limit <= 0 -> stringResource(R.string.deepl_usage_unknown)
    usage.state == OnlineKeyState.VALID -> stringResource(R.string.deepl_usage, "%,d".format(usage.used), "%,d".format(usage.limit))
    usage.state == OnlineKeyState.QUOTA_EXCEEDED -> stringResource(R.string.deepl_quota_used_up)
    usage.state == OnlineKeyState.INVALID && usage.reason == KeyCheck.Reason.MALFORMED_KEY -> stringResource(R.string.deepl_key_malformed)
    usage.state == OnlineKeyState.INVALID -> stringResource(R.string.deepl_key_not_accepted)
    usage.state == OnlineKeyState.BUSY -> stringResource(R.string.deepl_rate_limited)
    usage.reason == KeyCheck.Reason.HTTP_STATUS -> stringResource(R.string.deepl_server_error, usage.code)
    else -> stringResource(R.string.deepl_unreachable)
}

/** Altyazı hedefinin adı: TV'nin adı, "Bu telefon" ya da ikisi birden (iPhone ile aynı). */
/** Bekleme süresi kaydırıcısı: 0–1 sn, 0,1 sn adım; değer milisaniye olarak verilir. */
@Composable
internal fun WaitSlider(title: String, note: String, ms: Int, onChange: (Int) -> Unit) {
    val max = com.couchsubs.mobile.core.SubtitlePipeline.WAIT_SLIDER_MAX_MS
    val seconds = ms.coerceIn(0, max) / 1000f
    Column {
        SliderHeader(title, "${String.format(java.util.Locale.getDefault(), "%.1f", seconds)} ${stringResource(R.string.unit_seconds)}")
        Slider(seconds, { onChange(Math.round(it * 10) * 100) }, valueRange = 0f..max / 1000f, steps = max / 100 - 1,
            colors = couchSliderColors())
        Text(note, style = Tokens.Type.caption, color = Tokens.Color.secondary)
    }
}

@Composable
fun targetName(settings: AppSettings): String {
    val tv = settings.tvName ?: stringResource(R.string.main_target_tv)
    return when (settings.target) {
        SubtitleTarget.TV -> tv
        SubtitleTarget.PHONE -> stringResource(R.string.main_target_phone)
        SubtitleTarget.BOTH -> stringResource(R.string.main_target_both, tv)
        SubtitleTarget.OBS -> stringResource(R.string.target_obs)
    }
}
