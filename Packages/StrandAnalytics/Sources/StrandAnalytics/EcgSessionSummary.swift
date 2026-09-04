import Foundation

// MARK: - MG ECG session summary (descriptive only, never diagnostic)
//
// Pure, database-free rollup of one stored ECG capture session into the handful of
// numbers the ECG page shows. Every field is a description of what was recorded:
// coverage (how much of the run carried waveform), HR center/spread from the
// strap-stamped per-record bytes, duration and record rate.
// HRV, any rhythm classification, any score or gate. An empty session summarizes to
// zeros and nils — absent data is never fabricated into a reading.
//
// Median is the LOWER median (sorted ascending, element at (n-1)/2): deterministic,
// trivially mirrored in Kotlin, and documented so the twin cannot drift.
// Kotlin twin: `com.noop.analytics.EcgSessionSummary` — keep byte-identical.
public enum EcgSessionSummary {

    /// One stored record, as plain values (never a store row — analytics stays database-free).
    public struct Record: Equatable, Sendable {
        public let tsMs: Int
        public let hrBpm: Int?
        public let signalPresent: Bool

        public init(tsMs: Int, hrBpm: Int? = nil, signalPresent: Bool) {
            self.tsMs = tsMs; self.hrBpm = hrBpm; self.signalPresent = signalPresent
        }
    }

    public struct Summary: Equatable, Sendable {
        public let recordCount: Int
        public let waveRecords: Int
        /// Fraction of records carrying waveform, 0...1. 0 when the session is empty.
        public let waveCoverage: Double
        /// Lower median over non-null stamped HR bytes. Nil when no record carries one.
        public let medianHr: Int?
        public let minHr: Int?
        public let maxHr: Int?
        /// Whole seconds between first and last record. 0 with fewer than two records.
        public let durationSec: Int
        /// Records per second over the span. 0 with no span.
        public let recordsPerSec: Double
    }

    public static func summarize(_ records: [Record]) -> Summary {
        guard !records.isEmpty else {
            return Summary(recordCount: 0, waveRecords: 0, waveCoverage: 0,
                           medianHr: nil, minHr: nil, maxHr: nil,
                           durationSec: 0, recordsPerSec: 0)
        }
        let wave = records.filter(\.signalPresent).count
        let hrs = records.compactMap(\.hrBpm).sorted()
        let median: Int? = hrs.isEmpty ? nil : hrs[(hrs.count - 1) / 2]
        let lo = records.map(\.tsMs).min() ?? 0
        let hi = records.map(\.tsMs).max() ?? 0
        let spanMs = max(0, hi - lo)
        let durationSec = spanMs / 1000
        return Summary(
            recordCount: records.count,
            waveRecords: wave,
            waveCoverage: Double(wave) / Double(records.count),
            medianHr: median,
            minHr: hrs.first,
            maxHr: hrs.last,
            durationSec: durationSec,
            recordsPerSec: durationSec > 0 ? Double(records.count) / Double(durationSec) : 0
        )
    }

// MARK: - Waveform BPM estimate (peak intervals, descriptive only)
//
// Estimates heart rate from the stored WAVEFORM SAMPLES (not the stamped bytes): detrend
// with a 31-point moving average, take positive peaks above 1σ with a 0.30 s refractory,
// and convert the median inter-peak interval to bpm. Returns nil unless at least 4 peaks
// form a plausible rhythm (30...220 bpm); nil means "too noisy to read", never a guess.
// No diagnosis, no HRV, no classification — a rate reading beside the stamped bytes.
//
// Validated on two real MG captures against the strap's own optical HR: a 74→60 fall
// (estimate ~60) and an 82→93→82 stairs recovery (estimate ~90s). Single subject and
// sessions — instrumentation, not a measurement. The record-period autocorrelation trap
// (#194) is avoided structurally: peaks are detected as events, never spectrally, and
// the validation asserted phase-spread across the record grid rather than a grid-locked
// peak. Kotlin twin: `EcgSessionSummary.estimateBpm` — keep byte-identical.
public struct BeatEstimate: Equatable, Sendable {
    /// Whole-bpm estimate, or nil when the strip is too noisy to read.
    public let bpm: Int?
    /// Peaks admitted to the estimate (0 when unreadable).
    public let beats: Int

    public init(bpm: Int?, beats: Int) {
        self.bpm = bpm; self.beats = beats
    }
}

public static func estimateBpm(samples: [Int], samplesPerSec: Double) -> BeatEstimate {
    guard samples.count >= 3, samplesPerSec > 0 else { return BeatEstimate(bpm: nil, beats: 0) }
    // Detrend: 31-point centered moving average (edge-clamped), matching the validated setup.
    let w = 31
    var detrended = [Double]()
    detrended.reserveCapacity(samples.count)
    for i in samples.indices {
        let lo = max(0, i - w / 2)
        let hi = min(samples.count - 1, i + w / 2)
        var sum = 0.0
        for j in lo...hi { sum += Double(samples[j]) }
        detrended.append(Double(samples[i]) - sum / Double(hi - lo + 1))
    }
    let mean = detrended.reduce(0, +) / Double(detrended.count)
    let variance = detrended.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(detrended.count)
    let sd = variance.squareRoot()
    guard sd > 0 else { return BeatEstimate(bpm: nil, beats: 0) }
    // Peaks: strictly greater than both neighbours (ties broken left), refractory 0.30 s.
    let threshold = sd
    let refractory = max(1, Int((0.30 * samplesPerSec).rounded()))
    var peaks: [Int] = []
    var last = -refractory * 2
    for i in 1..<(detrended.count - 1) {
        if detrended[i] > threshold && detrended[i] >= detrended[i - 1]
            && detrended[i] > detrended[i + 1] && i - last >= refractory {
            peaks.append(i)
            last = i
        }
    }
    guard peaks.count >= 4 else { return BeatEstimate(bpm: nil, beats: peaks.count) }
    let ibis = zip(peaks, peaks.dropFirst()).map { $1 - $0 }.sorted()
    let medianIbi = ibis[(ibis.count - 1) / 2]
    guard medianIbi > 0 else { return BeatEstimate(bpm: nil, beats: peaks.count) }
    let bpm = Int((60.0 * samplesPerSec / Double(medianIbi)).rounded())
    guard (30...220).contains(bpm) else { return BeatEstimate(bpm: nil, beats: peaks.count) }
    return BeatEstimate(bpm: bpm, beats: peaks.count)
}

// MARK: - Cross-validated display rule
//
// The peak detector tracks clean runs but locks onto T-waves or motion cadence on noisy
// ones — always reading HIGH, never low, and no regularity gate separates the two (the
// wrong answers are steady). So a waveform rate is shown ONLY when it agrees with the
// INDEPENDENT optical path (the strap-stamped bytes, measured by different hardware):
// within 10 bpm of their lower median. Agreement of two independent sensors is the
// validation signal; anything else shows nothing rather than a confident wrong number.
// The ±10 window is calibrated on eleven real runs (single subject): six agreements all
// within 6, five disagreements all beyond 10. Provisional constant, principled shape.
// Kotlin twin: `EcgSessionSummary.agreedWaveBpm` — keep byte-identical.
public static func agreedWaveBpm(medianHr: Int?, estimate: BeatEstimate) -> Int? {
    guard let median = medianHr, let bpm = estimate.bpm,
          abs(bpm - median) <= 10 else { return nil }
    return bpm
}

}
