package com.noop.ble

import com.noop.protocol.Whoop5Ecg
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pins the MG ECG listen writer's session boundary rule ([WhoopBleClient.ecgCaptureStep]) + the
 * session-id format. Pure and strap-free: no BLE stack, no database.
 *
 * Contract: a CRC-valid type-43 frame persists only while bonded to an MG with the listen opt-in
 * on; the first record (or anything past the 60 s silence gap) opens `ecg-<nowMs>`, anything inside
 * the gap appends with `seq++`. Nothing here may authorize a strap write — the hook is read-only.
 */
class EcgCaptureTest {

    private val gap = WhoopBleClient.ECG_SESSION_GAP_MS

    @Test
    fun sessionIdFormat() {
        assertEquals("ecg-1234", Whoop5Ecg.sessionId(1234L))
        assertTrue(Whoop5Ecg.sessionId(System.currentTimeMillis()).startsWith("ecg-"))
    }

    @Test
    fun gapConstantIsSixtySeconds() {
        assertEquals(60_000L, gap)
    }

    @Test
    fun firstRecordOpensSessionAtSeqZero() {
        val step = WhoopBleClient.ecgCaptureStep(null, 1_000L, bonded = true, isMG = true, listenOn = true)
        assertEquals(Whoop5Ecg.sessionId(1_000L), step?.sessionId)
        assertEquals(0, step?.seq)
        assertEquals(true, step?.openSession)
    }

    @Test
    fun recordInsideGapAppendsWithNextSeq() {
        val cursor = EcgCaptureCursor("ecg-1000", lastTsMs = 1_000L, nextSeq = 3)
        val step = WhoopBleClient.ecgCaptureStep(cursor, 1_000L + gap - 1, bonded = true, isMG = true, listenOn = true)
        assertEquals("ecg-1000", step?.sessionId)
        assertEquals(3, step?.seq)
        assertEquals(false, step?.openSession)
    }

    @Test
    fun recordPastGapOpensNewSession() {
        val cursor = EcgCaptureCursor("ecg-1000", lastTsMs = 1_000L, nextSeq = 3)
        val step = WhoopBleClient.ecgCaptureStep(cursor, 1_000L + gap + 1, bonded = true, isMG = true, listenOn = true)
        assertEquals(Whoop5Ecg.sessionId(1_000L + gap + 1), step?.sessionId)
        assertEquals(0, step?.seq)
        assertEquals(true, step?.openSession)
    }

    @Test
    fun recordExactlyAtGapStillAppends() {
        val cursor = EcgCaptureCursor("ecg-1000", lastTsMs = 1_000L, nextSeq = 3)
        val step = WhoopBleClient.ecgCaptureStep(cursor, 1_000L + gap, bonded = true, isMG = true, listenOn = true)
        assertEquals("ecg-1000", step?.sessionId)
        assertEquals(false, step?.openSession)
    }

    @Test
    fun dropsWhenListenOff() {
        assertNull(WhoopBleClient.ecgCaptureStep(null, 1_000L, bonded = true, isMG = true, listenOn = false))
    }

    @Test
    fun dropsWhenNotBonded() {
        assertNull(WhoopBleClient.ecgCaptureStep(null, 1_000L, bonded = false, isMG = true, listenOn = true))
    }

    @Test
    fun dropsOnPlainFive() {
        assertNull(WhoopBleClient.ecgCaptureStep(null, 1_000L, bonded = true, isMG = false, listenOn = true))
    }
}
