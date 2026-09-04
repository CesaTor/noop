package com.noop.data

import com.noop.protocol.Whoop5Ecg
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * v35 -> v36: the MG ECG waveform tables (`ecgSession` + `ecgWaveformSample`), twin of the
 * Swift WhoopStore `v42-ecg-waveform` GRDB migration.
 *
 * This environment has no Robolectric / Room-testing, so the SQL is exposed as internal
 * constants and pinned to shape here rather than executed (the DailySkinTempAbsolute form).
 * The Swift side CAN open a store in-memory, so `EcgWaveformSampleTests` round-trips rows
 * there; the JVM side pins the contract the generated schema must satisfy.
 */
class EcgWaveformMigrationTest {

    @Test
    fun migrationCreatesBothTablesAdditive() {
        val sql = WhoopDatabase.ECG_WAVEFORM_MIGRATION_SQL
        assertEquals(2, sql.size)
        for (stmt in sql) {
            val upper = stmt.uppercase()
            assertTrue(upper.startsWith("CREATE TABLE IF NOT EXISTS"))
            for (banned in listOf("DROP ", "DELETE ", "UPDATE ", "INSERT ", "RENAME ", "ALTER ")) {
                assertTrue("migration must not contain $banned", !upper.contains(banned))
            }
        }
    }

    @Test
    fun migrationSpansTheRightVersions() {
        assertEquals(35, WhoopDatabase.MIGRATION_35_36.startVersion)
        assertEquals(36, WhoopDatabase.MIGRATION_35_36.endVersion)
        assertEquals(36, WhoopDatabase.SCHEMA_VERSION)
    }

    @Test
    fun columnOrderMatchesTheGrdbTwin() {
        // Room's generated CREATE TABLE follows entity field order; the oracle pins GRDB order,
        // so the SQL text must carry the same sequence on both tables.
        val session = WhoopDatabase.ECG_WAVEFORM_MIGRATION_SQL[0]
        val order = listOf("`id`", "`deviceId`", "`startedAtMs`", "`firmware`", "`variant`")
        assertTrue(order.map { session.indexOf(it) }.zipWithNext().all { (a, b) -> a < b })
        val samples = WhoopDatabase.ECG_WAVEFORM_MIGRATION_SQL[1]
        val sampleOrder = listOf("`sessionId`", "`seq`", "`deviceId`", "`tsMs`", "`hrBpm`",
            "`samples`", "`signalPresent`")
        assertTrue(sampleOrder.map { samples.indexOf(it) }.zipWithNext().all { (a, b) -> a < b })
        // Composite PKs match the GRDB twins.
        assertTrue(session.contains("PRIMARY KEY(`id`)"))
        assertTrue(samples.contains("PRIMARY KEY(`sessionId`, `seq`)"))
        // Nullable exactly where Swift is nullable: firmware, variant, hrBpm carry no NOT NULL.
        assertTrue(!session.substringAfter("`firmware`").startsWith(" TEXT NOT NULL"))
        assertTrue(!samples.substringAfter("`hrBpm`").startsWith(" INTEGER NOT NULL"))
    }

    @Test
    fun sessionIdMatchesTheSwiftTwin() {
        assertEquals("ecg-1788513405000", Whoop5Ecg.sessionId(1788513405000L))
    }

    @Test
    fun samplesShareThePpgEncoding() {
        // The ECG rows reuse the PPG i16-LE packing (one implementation); prove the shared
        // coder round-trips the signed extremes an ECG record actually carries.
        val samples = listOf(5, -5, 32767, -32768, 0)
        assertEquals(samples, StreamPersistence.unpackPpgSamples(StreamPersistence.packPpgSamples(samples)))
    }
}
