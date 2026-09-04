package com.noop.analytics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Twin of the Swift `EcgSessionSummaryTests`: same fixtures, same expected outputs, so the
 * two summarizers cannot drift. Descriptive rollup only — coverage, stamped-HR center/spread,
 * duration, rate.
 */
class EcgSessionSummaryTest {

    private fun rec(ms: Long, hr: Int? = 62, wave: Boolean = true) =
        EcgSessionSummary.Record(tsMs = ms, hrBpm = hr, signalPresent = wave)

    @Test
    fun emptySummarizesToZerosAndNulls() {
        val s = EcgSessionSummary.summarize(emptyList())
        assertEquals(0, s.recordCount)
        assertEquals(0, s.waveRecords)
        assertEquals(0.0, s.waveCoverage, 0.0)
        assertNull(s.medianHr)
        assertNull(s.minHr)
        assertNull(s.maxHr)
        assertEquals(0L, s.durationSec)
        assertEquals(0.0, s.recordsPerSec, 0.0)
    }

    @Test
    fun fullSession() {
        val rows = listOf(rec(1000, hr = 60), rec(2000, hr = 62), rec(3000, hr = 64, wave = false),
            rec(4000, hr = 61), rec(5000, hr = 63))
        val s = EcgSessionSummary.summarize(rows)
        assertEquals(5, s.recordCount)
        assertEquals(4, s.waveRecords)
        assertEquals(0.8, s.waveCoverage, 1e-12)
        assertEquals(62, s.medianHr)
        assertEquals(60, s.minHr)
        assertEquals(64, s.maxHr)
        assertEquals(4L, s.durationSec)
        assertEquals(1.25, s.recordsPerSec, 1e-12)
    }

    @Test
    fun lowerMedianOnEvenCount() {
        val rows = listOf(rec(1000, hr = 63), rec(2000, hr = 60), rec(3000, hr = 62), rec(4000, hr = 61))
        assertEquals(61, EcgSessionSummary.summarize(rows).medianHr)
    }

    @Test
    fun missingHrBytesYieldNulls() {
        val rows = listOf(rec(1000, hr = null), rec(2000, hr = null, wave = false))
        val s = EcgSessionSummary.summarize(rows)
        assertEquals(2, s.recordCount)
        assertEquals(1, s.waveRecords)
        assertEquals(0.5, s.waveCoverage, 1e-12)
        assertNull(s.medianHr)
        assertNull(s.minHr)
        assertNull(s.maxHr)
    }


    // MARK: - estimateBpm (same fixtures as the Swift twin)

    private fun spikeTrain(period: Int, peaks: Int, amp: Int = 1000): List<Int> {
        val s = MutableList(period * peaks + 10) { 0 }
        for (k in 0 until peaks) s[k * period + 5] = amp
        return s
    }

    @Test
    fun clean60bpmTrain() {
        val est = EcgSessionSummary.estimateBpm(spikeTrain(period = 100, peaks = 6), 100.0)
        assertEquals(6, est.beats)
        assertEquals(60, est.bpm)
    }

    @Test
    fun clean90bpmTrain() {
        val est = EcgSessionSummary.estimateBpm(spikeTrain(period = 67, peaks = 8), 100.0)
        assertEquals(90, est.bpm)
    }

    @Test
    fun flatIsUnreadable() {
        assertEquals(
            EcgSessionSummary.BeatEstimate(null, 0),
            EcgSessionSummary.estimateBpm(List(500) { 0 }, 100.0),
        )
        assertNull(EcgSessionSummary.estimateBpm(List(500) { 7 }, 100.0).bpm)
    }

    @Test
    fun tooFewBeatsIsUnreadable() {
        val est = EcgSessionSummary.estimateBpm(spikeTrain(period = 100, peaks = 2), 100.0)
        assertNull(est.bpm)
        assertEquals(2, est.beats)
    }

    @Test
    fun implausiblySlowIsRejected() {
        val est = EcgSessionSummary.estimateBpm(spikeTrain(period = 300, peaks = 4), 100.0)
        assertNull(est.bpm)
        assertEquals(4, est.beats)
    }

    @Test
    fun emptyAndDegenerate() {
        assertNull(EcgSessionSummary.estimateBpm(emptyList(), 100.0).bpm)
        assertNull(EcgSessionSummary.estimateBpm(listOf(1, 2), 100.0).bpm)
        assertNull(EcgSessionSummary.estimateBpm(spikeTrain(period = 100, peaks = 6), 0.0).bpm)
    }
    @Test
    fun singleRecordHasNoSpan() {
        val s = EcgSessionSummary.summarize(listOf(rec(1000, hr = 70)))
        assertEquals(0L, s.durationSec)
        assertEquals(0.0, s.recordsPerSec, 0.0)
        assertEquals(70, s.medianHr)
    }

    // MARK: - agreedWaveBpm (same fixtures as the Swift twin)

    @Test
    fun agreementShows() {
        assertEquals(
            65,
            EcgSessionSummary.agreedWaveBpm(63, EcgSessionSummary.BeatEstimate(65, 28)),
        )
        assertEquals(
            70,
            EcgSessionSummary.agreedWaveBpm(60, EcgSessionSummary.BeatEstimate(70, 28)),
        )
    }

    @Test
    fun disagreementHides() {
        assertNull(
            EcgSessionSummary.agreedWaveBpm(67, EcgSessionSummary.BeatEstimate(98, 40)),
        )
        assertNull(
            EcgSessionSummary.agreedWaveBpm(67, EcgSessionSummary.BeatEstimate(null, 2)),
        )
        assertNull(
            EcgSessionSummary.agreedWaveBpm(null, EcgSessionSummary.BeatEstimate(65, 28)),
        )
    }
}
