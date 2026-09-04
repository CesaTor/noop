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
}
