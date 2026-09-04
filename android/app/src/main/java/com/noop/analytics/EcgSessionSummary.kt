package com.noop.analytics

import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * MG ECG session summary (descriptive only, never diagnostic) — the Kotlin twin of Swift
 * `EcgSessionSummary`. Pure and database-free: rolls one stored capture session into the
 * numbers the ECG page shows (coverage, stamped-HR center/spread, duration, rate).
 *
 * Deliberately NOT here: HRV, any rhythm classification, any score or gate.
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

    /**
     * Waveform BPM estimate (peak intervals, descriptive only) — twin of Swift
     * `EcgSessionSummary.estimateBpm`. Same algorithm, same constants, same nil rules:
     * 31-point detrend, 1-sigma peaks, 0.30 s refractory, 4-beat floor, 30...220 gate.
     */
    data class BeatEstimate(val bpm: Int?, val beats: Int)

    fun estimateBpm(samples: List<Int>, samplesPerSec: Double): BeatEstimate {
        if (samples.size < 3 || samplesPerSec <= 0) return BeatEstimate(null, 0)
        // Detrend: 31-point centered moving average (edge-clamped).
        val w = 31
        val detrended = samples.indices.map { i ->
            val lo = maxOf(0, i - w / 2)
            val hi = minOf(samples.size - 1, i + w / 2)
            var sum = 0.0
            for (j in lo..hi) sum += samples[j]
            samples[i] - sum / (hi - lo + 1)
        }
        val mean = detrended.sum() / detrended.size
        val sd = sqrt(detrended.sumOf { (it - mean) * (it - mean) } / detrended.size)
        if (sd <= 0) return BeatEstimate(null, 0)
        // Peaks: strictly greater than both neighbours (ties broken left), refractory 0.30 s.
        val threshold = sd
        val refractory = maxOf(1, (0.30 * samplesPerSec).roundToInt())
        val peaks = mutableListOf<Int>()
        var last = -refractory * 2
        for (i in 1 until detrended.size - 1) {
            if (detrended[i] > threshold && detrended[i] >= detrended[i - 1] &&
                detrended[i] > detrended[i + 1] && i - last >= refractory
            ) {
                peaks.add(i)
                last = i
            }
        }
        if (peaks.size < 4) return BeatEstimate(null, peaks.size)
        val ibis = peaks.zipWithNext { a, b -> b - a }.sorted()
        val medianIbi = ibis[(ibis.size - 1) / 2]
        if (medianIbi <= 0) return BeatEstimate(null, peaks.size)
        val bpm = (60.0 * samplesPerSec / medianIbi).roundToInt()
        if (bpm !in 30..220) return BeatEstimate(null, peaks.size)
        return BeatEstimate(bpm, peaks.size)
    }

    /**
     * Cross-validated display rule — twin of Swift `EcgSessionSummary.agreedWaveBpm`. A waveform
     * rate shows ONLY when it agrees within 10 bpm with the independent optical path (the
     * strap-stamped median); anything else shows nothing rather than a confident wrong number.
     */
    fun agreedWaveBpm(medianHr: Int?, estimate: BeatEstimate): Int? {
        val bpm = estimate.bpm ?: return null
        if (medianHr == null || kotlin.math.abs(bpm - medianHr) > 10) return null
        return bpm
    }
}
