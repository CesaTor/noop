package com.noop.ui

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.MonitorHeart
import androidx.compose.material.icons.filled.WarningAmber
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.AlertDialog
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.noop.ble.PuffinExperiment
import com.noop.ble.WhoopBleClient
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.noop.R
import com.noop.analytics.EcgSessionSummary
import com.noop.data.EcgSessionEntity
import com.noop.data.EcgWaveformRow
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.roundToInt

/*
 * EcgScreen.kt — WHOOP MG ECG capture page (experimental, listen-only).
 *
 * Lists the on-device type-43 waveform sessions newest-first with descriptive summary tiles, and
 * drills into one session's stored waveform strip plus stat tiles and provenance. Descriptive
 * readings only — duration, waveform coverage, stamped-HR center/spread, record count, firmware +
 * variant — never rhythm classification, HRV, diagnosis, scores or gates. The non-medical framing
 * card renders pinned above the data, and the page itself is mounted only while the listen opt-in
 * ([com.noop.ble.PuffinExperiment.ecgListen]) is on (see AppRoot + HealthScreen).
 */

// MARK: - Data

/** One session with its unpacked rows and descriptive summary, loaded once per device. */
private data class EcgSessionView(
    val session: EcgSessionEntity,
    val rows: List<EcgWaveformRow>,
    val summary: EcgSessionSummary.Summary,
)

private fun summarizeEcg(rows: List<EcgWaveformRow>): EcgSessionSummary.Summary =
    EcgSessionSummary.summarize(rows.map { EcgSessionSummary.Record(it.tsMs, it.hrBpm, it.signalPresent) })

private fun ecgSessionTitle(startedAtMs: Long): String {
    val fmt = DateTimeFormatter.ofPattern("d MMM yyyy · HH:mm", Locale.getDefault())
        .withZone(ZoneId.systemDefault())
    return fmt.format(Instant.ofEpochMilli(startedAtMs))
}

// MARK: - Screen

@Composable
fun EcgScreen(vm: AppViewModel) {
    val deviceId = vm.activeStrapId
    var views by remember { mutableStateOf<List<EcgSessionView>>(emptyList()) }
    var loaded by remember { mutableStateOf(false) }
    var runEpoch by remember { mutableStateOf(0) }
    val scope = rememberCoroutineScope()
    suspend fun reload() {
        loaded = false
        val sessions = runCatching { vm.repo.ecgSessions(deviceId) }.getOrDefault(emptyList())
        views = sessions.map { session ->
            val rows = runCatching { vm.repo.ecgWaveformSamples(session.id) }.getOrDefault(emptyList())
            EcgSessionView(session, rows, summarizeEcg(rows))
        }
        loaded = true
    }
    LaunchedEffect(deviceId, runEpoch) { reload() }
    var selectedId by remember(deviceId) { mutableStateOf<String?>(null) }
    val selected = views.firstOrNull { it.session.id == selectedId }

    ScreenScaffold(
        uiString(R.string.l10n_ecg_screen_title),
        subtitle = uiString(R.string.l10n_ecg_screen_subtitle),
    ) {
        EcgFramingCard()
        EcgCaptureCard(
            vm = vm,
            onRunStarted = {
                // The verdict lands ~30 s after Start; reload then so the new session
                // appears without a manual pull.
                scope.launch {
                    delay(35_000)
                    runEpoch++
                }
            },
        )
        if (!loaded) return@ScreenScaffold
        when {
            selected != null -> EcgDetail(selected) { selectedId = null }
            views.isEmpty() -> EcgEmptyCard()
            else -> {
                SectionHeader(uiString(R.string.l10n_ecg_screen_sessions))
                views.forEach { view ->
                    EcgSessionRow(view) { selectedId = view.session.id }
                }
            }
        }
    }
}

// MARK: - Framing + empty state (non-medical, pinned above data)

/** Amber experimental-note panel: unvalidated instrumentation, not a measurement or diagnosis. */
@Composable
private fun EcgFramingCard() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Metrics.cornerSm))
            .background(Palette.statusWarning.copy(alpha = 0.10f))
            .padding(Metrics.space12),
        verticalArrangement = Arrangement.spacedBy(Metrics.space4),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(Metrics.space8)) {
            Icon(
                Icons.Filled.WarningAmber,
                contentDescription = null,
                tint = Palette.statusWarning,
                modifier = Modifier.size(Metrics.iconSmall),
            )
            Text(
                uiString(R.string.l10n_ecg_screen_framing_title),
                style = NoopType.headline,
                color = Palette.statusWarning,
            )
        }
        Text(
            uiString(R.string.l10n_ecg_screen_framing_body),
            style = NoopType.footnote,
            color = Palette.statusWarning,
        )
    }
}

/** Nil state: no sessions banked yet, with how to capture one. */
@Composable
private fun EcgEmptyCard() {
    NoopCard(tint = Palette.metricCyan) {
        Column(verticalArrangement = Arrangement.spacedBy(Metrics.space8)) {
            Text(
                uiString(R.string.l10n_ecg_screen_empty_title),
                style = NoopType.headline,
                color = Palette.textPrimary,
            )
            Text(
                uiString(R.string.l10n_ecg_screen_empty_body),
                style = NoopType.footnote,
                color = Palette.textSecondary,
            )
        }
    }
}

// MARK: - Session list

/** One session row: capture date + descriptive summary line, chevroning into the detail. */
@Composable
private fun EcgSessionRow(view: EcgSessionView, onClick: () -> Unit) {
    val title = ecgSessionTitle(view.session.startedAtMs)
    val meta = ecgSessionMeta(view.summary)
    val interaction = remember { MutableInteractionSource() }
    NoopCard(
        modifier = Modifier
            .clickable(
                interactionSource = interaction,
                indication = null,
                onClick = onClick,
            )
            .semantics {
                contentDescription = uiString(
                    R.string.l10n_health_screen_title_subtitle_8d9004e8,
                    title,
                    meta,
                )
            },
        padding = Metrics.space16,
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Metrics.space12),
        ) {
            Box(
                modifier = Modifier
                    .size(34.dp)
                    .clip(RoundedCornerShape(Metrics.cornerSm))
                    .background(Palette.metricCyan.copy(alpha = 0.14f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Filled.MonitorHeart,
                    contentDescription = null,
                    tint = Palette.metricCyan,
                    modifier = Modifier.size(18.dp),
                )
            }
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Metrics.space2)) {
                Text(title, style = NoopType.headline, color = Palette.textPrimary)
                Text(meta, style = NoopType.footnote, color = Palette.textTertiary)
            }
            Icon(
                Icons.Filled.ChevronRight,
                contentDescription = null,
                tint = Palette.textTertiary,
                modifier = Modifier.size(18.dp),
            )
        }
    }
}

/** "N records · P% waveform · median HR 62 bpm" (or the em-dash when nothing stamped an HR). */
@Composable
private fun ecgSessionMeta(summary: EcgSessionSummary.Summary): String {
    val median = summary.medianHr?.let { uiString(R.string.l10n_ecg_screen_median_hr, it) }
        ?: uiString(R.string.l10n_ecg_screen_no_hr)
    return uiString(
        R.string.l10n_ecg_screen_session_meta,
        summary.recordCount,
        (summary.waveCoverage * 100).roundToInt(),
        median,
    )
}

// MARK: - Session detail

@Composable
private fun EcgDetail(view: EcgSessionView, onBack: () -> Unit) {
    TextButton(onClick = onBack) {
        Icon(
            Icons.AutoMirrored.Filled.ArrowBack,
            contentDescription = null,
            tint = Palette.textSecondary,
            modifier = Modifier.size(Metrics.iconSmall),
        )
        Text(
            uiString(R.string.l10n_ecg_screen_sessions),
            style = NoopType.subhead,
            color = Palette.textSecondary,
        )
    }
    SectionHeader(ecgSessionTitle(view.session.startedAtMs))
    NoopCard(tint = Palette.metricCyan) {
        EcgStrip(view.rows.flatMap { it.samples })
    }
    EcgStatTiles(view.summary)
    EcgProvenanceCard(view.session)
}

/** The session's stored samples rendered verbatim as one continuous strip (101 per record). */
@Composable
private fun EcgStrip(samples: List<Int>, modifier: Modifier = Modifier) {
    val description = uiString(R.string.l10n_ecg_screen_strip_description)
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(Metrics.trendStripHeight)
            .clearAndSetSemantics { contentDescription = description }
            .drawWithCache {
                val pts = ecgStripPoints(samples, size.width, size.height)
                if (pts.isEmpty()) {
                    onDrawBehind {
                        val y = size.height / 2f
                        drawLine(
                            color = Palette.hairline,
                            start = Offset(0f, y),
                            end = Offset(size.width, y),
                            strokeWidth = 1f,
                        )
                    }
                } else {
                    val path = Path().apply {
                        moveTo(pts.first().x, pts.first().y)
                        for (i in 1 until pts.size) lineTo(pts[i].x, pts[i].y)
                    }
                    val stroke = Stroke(width = 2f, cap = StrokeCap.Round, join = StrokeJoin.Round)
                    onDrawBehind {
                        drawPath(path = path, color = Palette.metricCyan, style = stroke)
                    }
                }
            },
    )
}

/**
 * Map raw i16 counts onto canvas points. Downsamples by stride past ~600 plotted points (a 30-record
 * session is ~3k samples — plenty for the shape, wasteful as a path). A flat span centres rather
 * than pinning to an edge.
 */
private fun ecgStripPoints(samples: List<Int>, w: Float, h: Float): List<Offset> {
    val pad = 4f
    if (samples.size < 2 || w <= pad * 2 || h <= pad * 2) return emptyList()
    val stride = (samples.size + 599) / 600
    val series = if (stride > 1) samples.filterIndexed { i, _ -> i % stride == 0 } else samples
    if (series.size < 2) return emptyList()
    val lo = series.min().toFloat()
    val hi = series.max().toFloat()
    return series.mapIndexed { i, v ->
        val x = pad + (w - pad * 2) * i / (series.size - 1)
        val frac = if (hi > lo) (v - lo) / (hi - lo) else 0.5f
        Offset(x, pad + (h - pad * 2) * (1 - frac))
    }
}

/** Duration, waveform coverage, median HR (+ stamped range), record count — descriptive only. */
@Composable
private fun EcgStatTiles(summary: EcgSessionSummary.Summary) {
    val median = summary.medianHr?.let { uiString(R.string.l10n_ecg_screen_median_hr, it) }
        ?: uiString(R.string.l10n_ecg_screen_no_hr)
    val range = if (summary.minHr != null && summary.maxHr != null) {
        uiString(R.string.l10n_ecg_screen_hr_range, summary.minHr, summary.maxHr)
    } else {
        null
    }
    Column(verticalArrangement = Arrangement.spacedBy(Metrics.gap)) {
        Row(horizontalArrangement = Arrangement.spacedBy(Metrics.gap)) {
            StatTile(
                label = uiString(R.string.l10n_ecg_screen_stat_duration),
                value = uiString(R.string.l10n_ecg_screen_duration_value, summary.durationSec),
                modifier = Modifier.weight(1f),
            )
            StatTile(
                label = uiString(R.string.l10n_ecg_screen_stat_coverage),
                value = uiString(
                    R.string.l10n_ecg_screen_coverage_value,
                    (summary.waveCoverage * 100).roundToInt(),
                ),
                modifier = Modifier.weight(1f),
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(Metrics.gap)) {
            StatTile(
                label = uiString(R.string.l10n_ecg_screen_stat_median_hr),
                value = median,
                modifier = Modifier.weight(1f),
                caption = range,
            )
            StatTile(
                label = uiString(R.string.l10n_ecg_screen_stat_records),
                value = uiString(R.string.l10n_ecg_screen_records_value, summary.recordCount),
                modifier = Modifier.weight(1f),
            )
        }
    }
}

/** Firmware + variant the session was captured with — provenance, not a finding. */
@Composable
private fun EcgProvenanceCard(session: EcgSessionEntity) {
    NoopCard(tint = Palette.textTertiary) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Metrics.space8),
        ) {
            Icon(
                Icons.Filled.Info,
                contentDescription = null,
                tint = Palette.textTertiary,
                modifier = Modifier.size(Metrics.iconSmall),
            )
            Text(
                uiString(
                    R.string.l10n_ecg_screen_provenance,
                    session.firmware ?: uiString(R.string.l10n_ecg_screen_firmware_unknown),
                    session.variant ?: uiString(R.string.l10n_ecg_screen_firmware_unknown),
                ),
                style = NoopType.footnote,
                color = Palette.textSecondary,
            )
        }
    }
}
// MARK: - Capture controls (page-owned start/stop)

/** Why a capture cannot start right now. Pure so unit tests pin every case without a strap. */
internal enum class EcgCaptureBlock {
    DISCONNECTED,
    NOT_MG,
    NOT_BONDED,
}

/**
 * Nil when a capture can start; otherwise the blocking precondition (link, hardware, bond).
 * Deliberately NOT gated on Test Centre: the listen opt-in + MG attestation + encrypted bond
 * are the safety gates, and a shipped feature must not hide behind a diagnostics switch.
 * Twin of Swift `EcgCaptureBlock.check`.
 */
internal fun ecgCaptureBlockedReason(connected: Boolean, isMG: Boolean, bonded: Boolean): EcgCaptureBlock? {
    if (!connected) return EcgCaptureBlock.DISCONNECTED
    if (!isMG) return EcgCaptureBlock.NOT_MG
    if (!bonded) return EcgCaptureBlock.NOT_BONDED
    return null
}

/**
 * The listen opt-in as reactive state (SharedPreferences isn't observable, so watch the
 * experiments file like HealthScreen does). Used by the More drawer entry; the Health row
 * keeps its own inline watcher.
 */
@Composable
internal fun rememberEcgListen(): Boolean {
    val context = LocalContext.current
    var rev by remember { mutableIntStateOf(0) }
    DisposableEffect(Unit) {
        val prefs = context.getSharedPreferences(PuffinExperiment.PREFS, Context.MODE_PRIVATE)
        val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            if (key == null || key == PuffinExperiment.KEY_WHOOP5_ECG) rev++
        }
        prefs.registerOnSharedPreferenceChangeListener(listener)
        onDispose { prefs.unregisterOnSharedPreferenceChangeListener(listener) }
    }
    return remember(rev) { PuffinExperiment.from(context.applicationContext).ecgListen }
}

/** Page-owned Start/Stop for an MG ECG capture run. Same wire flow as macOS (`ecgStartCapture` /
 *  `ecgStopCapture` — bonded-MG + opt-in gated again at send time). The wrist selection stays
 *  out: it is a persistent strap write with its own confirmation elsewhere. */
@Composable
private fun EcgCaptureCard(vm: AppViewModel, onRunStarted: () -> Unit) {
    val live by vm.live.collectAsStateWithLifecycle()
    val variant by vm.ble.whoop5VariantFlow.collectAsStateWithLifecycle()
    val running by vm.ble.ecgCaptureRunning.collectAsStateWithLifecycle()
    val probe by vm.ble.ecgProbe.collectAsStateWithLifecycle()
    var confirm by remember { mutableStateOf(false) }
    val block = ecgCaptureBlockedReason(live.connected, variant.isMG, live.encryptedBond)
    NoopCard {
        Column(verticalArrangement = Arrangement.spacedBy(Metrics.space8)) {
            when {
                block != null -> Text(
                    text = when (block) {
                        EcgCaptureBlock.DISCONNECTED ->
                            uiString(R.string.l10n_ecg_screen_blocked_offline)
                        EcgCaptureBlock.NOT_MG ->
                            uiString(R.string.l10n_ecg_screen_blocked_variant)
                        EcgCaptureBlock.NOT_BONDED ->
                            uiString(R.string.l10n_ecg_screen_blocked_bond)
                    },
                    style = NoopType.subhead,
                    color = Palette.textSecondary,
                )
                running -> NoopButton(
                    text = uiString(R.string.l10n_ecg_screen_stop_capture),
                    kind = NoopButtonKind.Secondary,
                    fullWidth = true,
                    onClick = { vm.ble.ecgStopCapture() },
                )
                else -> NoopButton(
                    text = uiString(R.string.l10n_ecg_screen_start_capture),
                    fullWidth = true,
                    onClick = { confirm = true },
                )
            }
            probe?.let { EcgProbeStatus(it) { vm.ble.clearEcgProbe() } }
        }
    }
    if (confirm) {
        AlertDialog(
            onDismissRequest = { confirm = false },
            containerColor = Palette.surfaceOverlay,
            title = {
                Text(
                    uiString(R.string.l10n_ecg_screen_start_capture),
                    style = NoopType.title2,
                    color = Palette.textPrimary,
                )
            },
            text = {
                Text(
                    uiString(R.string.l10n_ecg_screen_confirm_body),
                    style = NoopType.subhead,
                    color = Palette.textSecondary,
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    confirm = false
                    vm.ble.ecgStartCapture()
                    onRunStarted()
                }) {
                    Text(
                        uiString(R.string.l10n_ecg_screen_start_capture),
                        style = NoopType.body,
                        color = Palette.accent,
                    )
                }
            },
            dismissButton = {
                TextButton(onClick = { confirm = false }) {
                    Text(
                        uiString(R.string.l10n_ecg_screen_cancel),
                        style = NoopType.body,
                        color = Palette.textSecondary,
                    )
                }
            },
        )
    }
}

/** The running probe state plus the finished verdict, read-only. */
@Composable
private fun EcgProbeStatus(text: String, onClose: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(Metrics.space4)) {
        if (text == WhoopBleClient.ECG_PROBE_WAITING) {
            Text(
                uiString(R.string.l10n_ecg_screen_running),
                style = NoopType.subhead,
                color = Palette.textSecondary,
            )
        } else {
            Text(
                text,
                style = NoopType.mono,
                color = Palette.textSecondary,
            )
        }
        TextButton(onClick = onClose) {
            Text(
                uiString(R.string.l10n_ecg_screen_cancel),
                style = NoopType.footnote,
                color = Palette.textTertiary,
            )
        }
    }
}
