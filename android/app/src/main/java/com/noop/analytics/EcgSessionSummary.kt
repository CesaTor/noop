package com.noop.analytics

/**
 * MG ECG session summary (descriptive only, never diagnostic) — the Kotlin twin of Swift
 * `EcgSessionSummary`. Pure and database-free: rolls one stored capture session into the
 * numbers the ECG page shows (coverage, stamped-HR center/spread, duration, rate).
 *
 * Deliberately NOT here: peak detection, HRV, any rhythm classification, any score or gate.
 * An empty session summarizes to zeros and nulls. Median is the LOWER median (sorted
 * ascending, element at (n-1)/2), exactly as documented on the Swift side.
 */
object EcgSessionSummary {

    /** One stored record, as plain values (never a store row). */
    data class Record(val tsMs: Long, val hrBpm: Int? = null, val signalPresent: Boolean)

    data class Summary(
        val recordCount: Int,
        val waveRecords: Int,
        /** Fraction of records carrying waveform, 0..1. 0 when the session is empty. */
        val waveCoverage: Double,
        /** Lower median over non-null stamped HR bytes. Null when no record carries one. */
        val medianHr: Int?,
        val minHr: Int?,
        val maxHr: Int?,
        /** Whole seconds between first and last record. 0 with fewer than two records. */
        val durationSec: Long,
        /** Records per second over the span. 0 with no span. */
        val recordsPerSec: Double,
    )

    fun summarize(records: List<Record>): Summary {
        if (records.isEmpty()) {
            return Summary(0, 0, 0.0, null, null, null, 0, 0.0)
        }
        val wave = records.count { it.signalPresent }
        val hrs = records.mapNotNull { it.hrBpm }.sorted()
        val median = if (hrs.isEmpty()) null else hrs[(hrs.size - 1) / 2]
        val lo = records.minOf { it.tsMs }
        val hi = records.maxOf { it.tsMs }
        val spanMs = maxOf(0L, hi - lo)
        val durationSec = spanMs / 1000
        return Summary(
            recordCount = records.size,
            waveRecords = wave,
            waveCoverage = wave.toDouble() / records.size,
            medianHr = median,
            minHr = hrs.firstOrNull(),
            maxHr = hrs.lastOrNull(),
            durationSec = durationSec,
            recordsPerSec = if (durationSec > 0) records.size.toDouble() / durationSec else 0.0,
        )
    }
}
