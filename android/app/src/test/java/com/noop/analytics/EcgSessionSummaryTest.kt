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

    @Test
    fun singleRecordHasNoSpan() {
        val s = EcgSessionSummary.summarize(listOf(rec(1000, hr = 70)))
        assertEquals(0L, s.durationSec)
        assertEquals(0.0, s.recordsPerSec, 0.0)
        assertEquals(70, s.medianHr)
    }
}
