import Foundation
import SwiftUI
import StrandAnalytics
import StrandDesign
import WhoopProtocol

// EcgView.swift — banked MG ECG capture sessions (experimental instrumentation).
//
// Session list (newest first, summary tiles) → session detail (waveform strip +
// descriptive stats). Descriptive readings only: duration, waveform coverage,
// strap-stamped heart rate, record count, firmware + variant. No rhythm
// classification, no HRV, no diagnosis, no scores — the framing card pinned
// above the data says so in words. Renders stored samples verbatim.
//
// The writer lives in BLEManager's armed probe path (beginEcgProbeRun opens the
// session, noteEcgProbeRawRecord banks each type-43 record); this page only
// reads back through Repository. Shared macOS + iOS: design tokens only, no
// platform imports. Reachable only while the ECG opt-in is on (the nav entries
// self-gate); the page itself carries no gate.

struct EcgView: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var live: LiveState
    @State private var sessions: [EcgWaveformSession] = []

    var body: some View {
        #if os(macOS)
        NavigationStack { content }
        #else
        content
        #endif
    }

    private var content: some View {
        ScreenScaffold(title: "ECG", subtitle: "Banked MG captures",
                       onRefresh: { await load() }) {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                EcgFramingCard()
                EcgCaptureCard()
                if sessions.isEmpty {
                    EcgNilState()
                } else {
                SectionHeader("Captures", overline: "Sessions",
                                  trailing: String(localized: "\(sessions.count) sessions"))
                    LazyVStack(spacing: NoopMetrics.gap) {
                        ForEach(sessions, id: \.id) { session in
                            NavigationLink {
                                EcgSessionDetailView(session: session) {
                                    Task { await load() }
                                }
                            } label: {
                                EcgSessionRow(session: session)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .task { await load() }
        .onChange(of: live.ecgProbe) { probe in
            // The verdict lands 30–90 s after Start (arming + window); reload then so the
            // new session appears without a manual pull. Fires only on the final text —
            // both sentinels (arming, capturing) are skipped.
            if probe != nil && probe != BLEManager.ecgProbeWaiting && probe != BLEManager.ecgProbeArming {
                Task { await load() }
            }
        }
    }

    private func load() async {
        sessions = await repo.ecgSessions()
    }
}

// MARK: - Framing (pinned above data, list + detail)

/// The standing non-medical framing: unvalidated instrumentation, never a
/// diagnosis. Shown above every reading on both the list and the detail.
private struct EcgFramingCard: View {
    var body: some View {
        NoopCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .accessibilityHidden(true)
                Text("Experimental captures from your MG strap: unvalidated instrumentation, not a diagnosis. These describe what the strap recorded during a short capture run — duration, waveform coverage, and strap-stamped heart rate. They are not a medical measurement and cannot detect or rule out any condition. If you feel unwell, contact a qualified professional; in an emergency, your local emergency service.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Nil state

/// Empty state: how a capture happens (Devices → ECG capture → hold clasp 30 s).
private struct EcgNilState: View {
    var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("No ECG captures yet")
                    .font(StrandFont.title2)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("To capture: open Devices, choose your MG strap, start ECG capture, and hold the clasp for the whole 30-second window.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Session row (summary tile)

// One session's descriptive summary. Loads its own records so the list stays
// cheap until rows appear; sessions are probe-run volumes (~30 records each).
private struct EcgSessionRow: View {
    @EnvironmentObject var repo: Repository
    let session: EcgWaveformSession
    @State private var summary: EcgSessionSummary.Summary?

    var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(EcgFormat.sessionDate(session.startedAtMs))
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textPrimary)
                if let summary {
                    Text(EcgFormat.rowLine(summary))
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                } else {
                    Text("Loading capture…")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await load() }
    }

    private func load() async {
        let rows = await repo.ecgWaveformSamples(sessionId: session.id)
        summary = EcgSessionSummary.summarize(rows.map {
            EcgSessionSummary.Record(tsMs: $0.tsMs, hrBpm: $0.hrBpm, signalPresent: $0.signalPresent)
        })
    }
}

// MARK: - Session detail
private struct EcgSessionDetailView: View {
    @EnvironmentObject var repo: Repository
    @Environment(\.dismiss) private var dismiss
    let session: EcgWaveformSession
    /// Reloads the parent list after a delete (the pushed detail is dismissed first).
    var onDelete: () -> Void
    @State private var samples: [EcgWaveformSample] = []
    @State private var loaded = false
    @State private var showDeleteConfirm = false

    private var summary: EcgSessionSummary.Summary {
        EcgSessionSummary.summarize(samples.map {
            EcgSessionSummary.Record(tsMs: $0.tsMs, hrBpm: $0.hrBpm, signalPresent: $0.signalPresent)
        })
    }

    /// Stored samples verbatim, in capture order, stride-capped for rendering.
    private var stripValues: [Double] {
        let all = samples.sorted { $0.seq < $1.seq }.flatMap { $0.samples }
        guard all.count > 1200 else { return all.map(Double.init) }
        let step = (all.count + 1199) / 1200
        return stride(from: 0, to: all.count, by: step).map { Double(all[$0]) }
    }

    /// Waveform BPM inputs: the full stored series (never the stride-capped strip) and the
    /// MEASURED sample rate (samples ÷ wall span), never an assumed firmware rate.
    private var beatEstimate: EcgSessionSummary.BeatEstimate {
        let ordered = samples.sorted { $0.seq < $1.seq }
        let all = ordered.flatMap { $0.samples }
        let stamps = ordered.map(\.tsMs)
        guard let lo = stamps.min(), let hi = stamps.max(), hi > lo, !all.isEmpty else {
            return EcgSessionSummary.BeatEstimate(bpm: nil, beats: 0)
        }
        let sps = Double(all.count) / (Double(hi - lo) / 1000.0)
        return EcgSessionSummary.estimateBpm(samples: all, samplesPerSec: sps)
    }

    /// Displayed wave rate: the estimate ONLY when the independent optical path agrees
    /// (cross-validated display rule) — otherwise nil, and the tile says so honestly.
    private var agreedBpm: Int? {
        EcgSessionSummary.agreedWaveBpm(medianHr: summary.medianHr, estimate: beatEstimate)
    }

    var body: some View {
        ScreenScaffold(title: "ECG capture", subtitle: "\(EcgFormat.sessionDate(session.startedAtMs))") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                EcgFramingCard()
                if !loaded {
                    NoopCard {
                        Text("Loading capture…")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if samples.isEmpty {
                    NoopCard {
                        Text("This capture banked no waveform records — the raw pump emitted nothing during the window (off, or never started).")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ChartCard(title: "Waveform strip",
                              subtitle: String(localized: "\(summary.recordCount) records, stored samples verbatim"),
                              trailing: EcgFormat.medianShort(summary)) {
                        Sparkline(values: stripValues, showsHover: false)
                    } footer: {
                        ChartFooter([
                            ("Records", "\(summary.recordCount)"),
                            ("Coverage", EcgFormat.percent(summary.waveCoverage)),
                        ])
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 168), spacing: NoopMetrics.gap)],
                              alignment: .leading, spacing: NoopMetrics.gap) {
                        StatTile(label: "Duration", value: EcgFormat.duration(summary),
                                 caption: String(localized: "First to last record"))
                        StatTile(label: "Waveform coverage", value: EcgFormat.percent(summary.waveCoverage),
                                 caption: String(localized: "\(summary.waveRecords) of \(summary.recordCount) records"))
                        StatTile(label: "Median heart rate", value: EcgFormat.median(summary),
                                 caption: EcgFormat.range(summary))
                        StatTile(label: "Waveform BPM", value: EcgFormat.waveBpm(agreedBpm),
                                 caption: EcgFormat.beatCaption(agreed: agreedBpm, beats: beatEstimate.beats))
                    }
                    NoopCard {
                        Text(EcgFormat.provenance(session))
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if loaded {
                    Button(String(localized: "Delete capture"), role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .buttonStyle(.plain)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.statusCritical)
                }
            }
        }
        .confirmationDialog("Delete this capture?",
                            isPresented: $showDeleteConfirm,
                            titleVisibility: .visible) {
            Button(String(localized: "Delete capture"), role: .destructive) {
                Task {
                    _ = await repo.deleteEcgSession(session.id)
                    onDelete()
                    dismiss()
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text("This removes the banked records for this capture. The strap is untouched.")
        }
        .task { await load() }
    }

    private func load() async {
        samples = await repo.ecgWaveformSamples(sessionId: session.id)
        loaded = true
    }
}

// MARK: - Formatting (display-only, no clinical wording)

private enum EcgFormat {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    static func sessionDate(_ startedAtMs: Int) -> String {
        dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(startedAtMs) / 1000))
    }

    static func percent(_ fraction: Double) -> String {
        String(localized: "\(Int((fraction * 100).rounded()))%")
    }

    static func duration(_ s: EcgSessionSummary.Summary) -> String {
        String(localized: "\(s.durationSec)s")
    }

    static func median(_ s: EcgSessionSummary.Summary) -> String {
        guard let m = s.medianHr else { return String(localized: "No stamped rate") }
        return String(localized: "\(m) bpm")
    }

    static func medianShort(_ s: EcgSessionSummary.Summary) -> String? {
        guard let m = s.medianHr else { return nil }
        return String(localized: "\(m) bpm median")
    }

    /// Spread of the strap-stamped rates, or the honest nil when none was stamped.
    static func range(_ s: EcgSessionSummary.Summary) -> String {
        guard let lo = s.minHr, let hi = s.maxHr else {
            return String(localized: "No strap-stamped heart rate")
        }
        return String(localized: "\(lo)–\(hi) bpm stamped")
    }

    /// One-line list summary: duration, coverage, median stamped rate.
    static func rowLine(_ s: EcgSessionSummary.Summary) -> String {
        let rate: String
        if let m = s.medianHr {
            rate = String(localized: "\(m) bpm median")
        } else {
            rate = String(localized: "no stamped rate")
        }
        return String(localized: "\(s.durationSec)s · \(Int((s.waveCoverage * 100).rounded()))% waveform · \(rate)")
    }

    static func waveBpm(_ agreed: Int?) -> String {
        guard let bpm = agreed else { return String(localized: "—") }
        return String(localized: "\(bpm) bpm")
    }

    /// Beat count behind a shown estimate, or the honest nil-state when hidden.
    static func beatCaption(agreed: Int?, beats: Int) -> String {
        guard agreed != nil else { return String(localized: "too noisy to read") }
        return String(localized: "\(beats) beats")
    }

    /// Provenance: which strap build banked this, plus the standing disclaimer.
    static func provenance(_ session: EcgWaveformSession) -> String {
        let fw = session.firmware ?? String(localized: "unknown firmware")
        let variant = session.variantLabel ?? String(localized: "unknown variant")
        return String(localized: "Firmware \(fw) · \(variant) · unvalidated instrumentation, not a diagnosis")
    }
}

// MARK: - Capture controls (page-owned start/stop)

/// Why a capture cannot start right now. Pure so StrandTests pins every case without
/// a strap; the card maps each case to user-facing copy. Deliberately NOT gated on
/// Test Centre: the Experimental opt-in + MG attestation + encrypted bond are the safety
/// gates, and a shipped feature must not hide behind a diagnostics switch. The read-only
/// Devices probes keep theirs; this entry never had a diagnostic-only reason.
enum EcgCaptureBlock: Equatable {
    case disconnected
    case notMG
    case notBonded

    /// Nil when a capture can start; otherwise the blocking precondition. Order matches
    /// the cheapest check first (link, hardware, bond).
    static func check(connected: Bool, isMG: Bool, bonded: Bool) -> EcgCaptureBlock? {
        if !connected { return .disconnected }
        if !isMG { return .notMG }
        if !bonded { return .notBonded }
        return nil
    }
}

/// Page-owned Start/Stop for an MG ECG capture run. Same wire flow as the Devices entry
/// (`model.ecgStartCapture()` / `model.ecgStopCapture()` — bonded-MG + opt-in gated again
/// at send time), so this is a second door to the same room, not a second room. The wrist
/// selection stays Devices-only: it is a persistent strap write with its own confirmation.
private struct EcgCaptureCard: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var live: LiveState
    @AppStorage(PuffinExperiment.ecgKey) private var ecgEnabled = false
    @State private var showStartConfirm = false

    private var block: EcgCaptureBlock? {
        EcgCaptureBlock.check(connected: live.connected,
                              isMG: model.isWhoop5MG,
                              bonded: live.encryptedBond)
    }

    var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 8) {
                if let block {
                    Text(EcgCaptureCopy.blockedReason(block))
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if model.ecgMayBeRunning {
                    Button(String(localized: "Stop ECG capture")) { model.ecgStopCapture() }
                        .buttonStyle(.plain)
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.statusWarning)
                } else {
                    Button(String(localized: "Start ECG capture")) { showStartConfirm = true }
                        .buttonStyle(.plain)
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.accent)
                }
                if live.ecgProbe != nil {
                    EcgProbeStatus(text: live.ecgProbe ?? "")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog("Start ECG capture",
                            isPresented: $showStartConfirm,
                            titleVisibility: .visible) {
            Button(String(localized: "Start ECG capture")) {
                model.ecgStartCapture()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text("Asks your MG to start its ECG subsystem and logs whatever comes back. Not a medical measurement or diagnosis. Hold both clasp indents for the whole window.")
        }
    }
}

/// The running/waiting probe state plus the finished verdict, read-only. The verdict text
/// carries its own header; this only frames it with a close control.
private struct EcgProbeStatus: View {
    @EnvironmentObject var model: AppModel
    let text: String
    private var waiting: Bool { text == BLEManager.ecgProbeWaiting }
    private var arming: Bool { text == BLEManager.ecgProbeArming }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if arming {
                Text("Waiting for the first waveform — hold the clasp.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
            } else {
                Text(text)
                    .font(StrandFont.mono)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(String(localized: "Close")) { model.clearEcgProbe() }
                .buttonStyle(.plain)
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
        }
    }
}

/// User copy for each blocking precondition. Kept beside the gate so prose and logic
/// cannot drift apart; localized where the call sites need Strings.
private enum EcgCaptureCopy {
    static func blockedReason(_ block: EcgCaptureBlock) -> String {
        switch block {
        case .disconnected:
            return String(localized: "Not connected. Open Live to pair.")
        case .notMG:
            return String(localized: "Waiting for your strap to identify as a WHOOP MG.")
        case .notBonded:
            return String(localized: "Needs the encrypted bond — pair the strap first.")
        }
    }
}
