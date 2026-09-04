package com.noop.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Pins the ECG page's capture gate: every blocking precondition maps to its case, and
 * all-true maps to null. Twin of the Swift `EcgCaptureGateTests` (minus the opt-in, which
 * lives at the entry points on both platforms rather than in the gate itself).
 */
class EcgCaptureGateTest {

    @Test
    fun readyNeedsEverything() {
        assertNull(ecgCaptureBlockedReason(connected = true, isMG = true, bonded = true))
    }

    @Test
    fun disconnectedWinsOverEverything() {
        assertEquals(
            EcgCaptureBlock.DISCONNECTED,
            ecgCaptureBlockedReason(connected = false, isMG = false, bonded = false),
        )
    }

    @Test
    fun unattestedStrapIsNotMG() {
        assertEquals(
            EcgCaptureBlock.NOT_MG,
            ecgCaptureBlockedReason(connected = true, isMG = false, bonded = true),
        )
    }

    @Test
    fun liveHROnlyLinkCannotCapture() {
        assertEquals(
            EcgCaptureBlock.NOT_BONDED,
            ecgCaptureBlockedReason(connected = true, isMG = true, bonded = false),
        )
    }
}
