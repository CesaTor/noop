import Foundation
import GRDB
import WhoopProtocol

// MARK: - v42 store: durable MG ECG (type-43) waveform capture
// Mirrors OuraRawStore's shape (Codable row structs, idempotent writes, scoped reads —
// all GRDB work via syncWrite/syncRead) over the row shapes in WhoopProtocol/Whoop5Ecg.swift.
// This is instrumentation storage: sessions banked by probe runs so a validated consumer
// (the ECG page) can read them back. No analytic, score, gate, or export reads these rows.

extension WhoopStore {

    /// Open a capture session. Idempotent by id: re-opening the same probe run is a no-op
    /// rather than a duplicate. Returns rows changed.
    @discardableResult
    public func openEcgSession(_ session: EcgWaveformSession, deviceId: String) async throws -> Int {
        try syncWrite { db in
            try db.execute(sql: """
                INSERT INTO ecgSession (id, deviceId, startedAtMs, firmware, variant)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO NOTHING
                """, arguments: [session.id, deviceId, session.startedAtMs,
                                 session.firmware, session.variantLabel])
            return db.changesCount
        }
    }

    /// Bank one probe run's records. Idempotent by (sessionId, seq): re-banking the same
    /// record is a no-op (mirrors every per-second stream's ON CONFLICT DO NOTHING rule).
    /// Samples pack via the shared i16-LE `packPpgSamples` — identical encoding, one
    /// implementation, so the two waveform tables cannot drift apart. Returns rows changed.
    @discardableResult
    public func insertEcgWaveform(_ rows: [EcgWaveformSample],
                                  sessionId: String,
                                  deviceId: String) async throws -> Int {
        try syncWrite { db in
            var n = 0
            for r in rows {
                try db.execute(sql: """
                    INSERT INTO ecgWaveformSample
                        (sessionId, seq, deviceId, tsMs, hrBpm, samples, signalPresent)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(sessionId, seq) DO NOTHING
                    """, arguments: [sessionId, r.seq, deviceId, r.tsMs, r.hrBpm,
                                     WhoopStore.packPpgSamples(r.samples),
                                     r.signalPresent])
                n += db.changesCount
            }
            return n
        }
    }

    /// Sessions for a device, newest first — the ECG page's session list.
    public func ecgSessions(deviceId: String) async throws -> [EcgWaveformSession] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT id, startedAtMs, firmware, variant FROM ecgSession
                WHERE deviceId = ?
                ORDER BY startedAtMs DESC
                """, arguments: [deviceId])
                .map { EcgWaveformSession(id: $0["id"], startedAtMs: $0["startedAtMs"],
                                          firmware: $0["firmware"], variantLabel: $0["variant"]) }
        }
    }

    /// One session's records in capture order. `samples` unpack from the stored BLOB;
    /// a malformed blob decodes short/empty rather than throwing (unpack drops odd bytes).
    public func ecgWaveformSamples(sessionId: String) async throws -> [EcgWaveformSample] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT seq, tsMs, hrBpm, samples, signalPresent FROM ecgWaveformSample
                WHERE sessionId = ?
                ORDER BY seq ASC
                """, arguments: [sessionId])
                .map { EcgWaveformSample(seq: $0["seq"], tsMs: $0["tsMs"], hrBpm: $0["hrBpm"],
                                         samples: WhoopStore.unpackPpgSamples($0["samples"]),
                                         signalPresent: $0["signalPresent"]) }
        }
    }

    public func ecgWaveformCountForTest() async throws -> Int {
        try syncRead { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ecgWaveformSample") ?? 0 }
    }

    /// Remove every ECG session + record for a device (device deletion hygiene — both new
    /// tables are deviceId-keyed precisely so this stays a flat clear with no join).
    /// Returns rows deleted.
    @discardableResult
    public func deleteEcgWaveform(deviceId: String) async throws -> Int {
        try syncWrite { db in
            try db.execute(sql: "DELETE FROM ecgWaveformSample WHERE deviceId = ?",
                           arguments: [deviceId])
            var n = db.changesCount
            try db.execute(sql: "DELETE FROM ecgSession WHERE deviceId = ?", arguments: [deviceId])
            n += db.changesCount
            return n
        }
    }

    /// Remove one capture session and its records (the ECG page's per-session Delete).
    /// Session ids are unique (`ecg-<startTsMs>`), so no device scoping is needed.
    /// Returns rows deleted.
    @discardableResult
    public func deleteEcgSession(_ sessionId: String) async throws -> Int {
        try syncWrite { db in
            try db.execute(sql: "DELETE FROM ecgWaveformSample WHERE sessionId = ?",
                           arguments: [sessionId])
            var n = db.changesCount
            try db.execute(sql: "DELETE FROM ecgSession WHERE id = ?", arguments: [sessionId])
            n += db.changesCount
            return n
        }
    }
}
