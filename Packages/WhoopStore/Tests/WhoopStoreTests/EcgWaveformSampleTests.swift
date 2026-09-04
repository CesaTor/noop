import XCTest
import WhoopProtocol
@testable import WhoopStore

/// v42 migration: durable storage for the WHOOP MG type-43 ECG waveform.
/// Proves both tables exist with their keys/shapes, that session open + record insert
/// round-trips (including negative AC-ish samples and null hrBpm), that re-banking is
/// idempotent, that reads are session-scoped, and that device deletion clears both tables.
///
/// NOTE: every `try await` is hoisted into a `let` — XCTAssert's autoclosure parameters
/// cannot take an async call.
final class EcgWaveformSampleTests: XCTestCase {

    private func session(id: String = "ecg-1788513405000") -> EcgWaveformSession {
        EcgWaveformSession(id: id, startedAtMs: 1_788_513_405_000,
                           firmware: "50.39.1.0", variantLabel: "MG")
    }

    private func record(seq: Int, hr: Int? = 62) -> EcgWaveformSample {
        EcgWaveformSample(seq: seq, tsMs: 1_788_513_405_000 + seq * 1000, hrBpm: hr,
                          samples: [5, -5, 32767, -32768, 0], signalPresent: true)
    }

    func testV42CreatesEcgTables() async throws {
        let store = try await WhoopStore.inMemory()
        let tables = try await store.tableNames()
        XCTAssertTrue(tables.contains("ecgSession"))
        XCTAssertTrue(tables.contains("ecgWaveformSample"))
    }

    func testEcgPrimaryKeys() async throws {
        let store = try await WhoopStore.inMemory()
        let sessionPK = try await store.primaryKeyColumns("ecgSession")
        let samplePK = try await store.primaryKeyColumns("ecgWaveformSample")
        XCTAssertEqual(sessionPK, ["id"])
        XCTAssertEqual(samplePK, ["sessionId", "seq"])
    }

    func testEcgTableShapes() async throws {
        let store = try await WhoopStore.inMemory()
        let sessionCols = try await store.columnNamesForTest(table: "ecgSession")
        let sampleCols = try await store.columnNamesForTest(table: "ecgWaveformSample")
        XCTAssertEqual(sessionCols, ["id", "deviceId", "startedAtMs", "firmware", "variant"])
        XCTAssertEqual(sampleCols, ["sessionId", "seq", "deviceId", "tsMs", "hrBpm",
                                    "samples", "signalPresent"])
    }

    func testEcgSessionOpenIsIdempotent() async throws {
        let store = try await WhoopStore.inMemory()
        let first = try await store.openEcgSession(session(), deviceId: "dev-a")
        let second = try await store.openEcgSession(session(), deviceId: "dev-a")
        let listed = try await store.ecgSessions(deviceId: "dev-a")
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 0)
        XCTAssertEqual(listed, [session()])
    }

    func testEcgInsertRoundTripAndDedup() async throws {
        let store = try await WhoopStore.inMemory()
        _ = try await store.openEcgSession(session(), deviceId: "dev-a")
        // Null hrBpm (unstamped) + extreme i16 values exercise the nullable column
        // and the signed packing end to end.
        let rows = [record(seq: 0), record(seq: 1, hr: nil)]
        let inserted = try await store.insertEcgWaveform(rows, sessionId: session().id,
                                                         deviceId: "dev-a")
        let count1 = try await store.ecgWaveformCountForTest()
        let read = try await store.ecgWaveformSamples(sessionId: session().id)
        XCTAssertEqual(inserted, 2)
        XCTAssertEqual(count1, 2)
        XCTAssertEqual(read, rows)
        // Re-banking the same (sessionId, seq) rows is idempotent.
        let reinserted = try await store.insertEcgWaveform(rows, sessionId: session().id,
                                                           deviceId: "dev-a")
        let count2 = try await store.ecgWaveformCountForTest()
        XCTAssertEqual(reinserted, 0)
        XCTAssertEqual(count2, 2)
    }

    func testEcgReadsAreSessionScoped() async throws {
        let store = try await WhoopStore.inMemory()
        _ = try await store.openEcgSession(session(id: "ecg-1"), deviceId: "dev-a")
        _ = try await store.openEcgSession(session(id: "ecg-2"), deviceId: "dev-a")
        _ = try await store.insertEcgWaveform([record(seq: 0)], sessionId: "ecg-1", deviceId: "dev-a")
        _ = try await store.insertEcgWaveform([record(seq: 0)], sessionId: "ecg-2", deviceId: "dev-a")
        // Same seq in two sessions coexists (PK includes sessionId); each session reads its own.
        let total = try await store.ecgWaveformCountForTest()
        let one = try await store.ecgWaveformSamples(sessionId: "ecg-1")
        XCTAssertEqual(total, 2)
        XCTAssertEqual(one.count, 1)
        // Sessions list newest-first; other devices see nothing.
        _ = try await store.openEcgSession(
            EcgWaveformSession(id: "ecg-3", startedAtMs: 1_788_513_500_000), deviceId: "dev-a")
        let listed = try await store.ecgSessions(deviceId: "dev-a")
        let foreign = try await store.ecgSessions(deviceId: "dev-b")
        XCTAssertEqual(listed.map(\.id), ["ecg-3", "ecg-1", "ecg-2"])
        XCTAssertTrue(foreign.isEmpty)
    }

    func testEcgDeleteSingleSession() async throws {
        let store = try await WhoopStore.inMemory()
        _ = try await store.openEcgSession(session(id: "ecg-1"), deviceId: "dev-a")
        _ = try await store.openEcgSession(session(id: "ecg-2"), deviceId: "dev-a")
        _ = try await store.insertEcgWaveform([record(seq: 0)], sessionId: "ecg-1", deviceId: "dev-a")
        _ = try await store.insertEcgWaveform([record(seq: 0), record(seq: 1)],
                                              sessionId: "ecg-2", deviceId: "dev-a")
        let deleted = try await store.deleteEcgSession("ecg-1")
        let remaining = try await store.ecgSessions(deviceId: "dev-a")
        let count = try await store.ecgWaveformCountForTest()
        XCTAssertEqual(deleted, 2)
        XCTAssertEqual(remaining.map(\.id), ["ecg-2"])
        XCTAssertEqual(count, 2)
        // Deleting an absent session deletes nothing and throws nothing.
        let absent = try await store.deleteEcgSession("ecg-missing")
        XCTAssertEqual(absent, 0)
    }

    func testEcgDeleteClearsBothTables() async throws {
        let store = try await WhoopStore.inMemory()
        _ = try await store.openEcgSession(session(), deviceId: "dev-a")
        _ = try await store.insertEcgWaveform([record(seq: 0)], sessionId: session().id,
                                              deviceId: "dev-a")
        _ = try await store.openEcgSession(session(id: "ecg-9"), deviceId: "dev-b")
        let deleted = try await store.deleteEcgWaveform(deviceId: "dev-a")
        let remaining = try await store.ecgSessions(deviceId: "dev-a")
        let count = try await store.ecgWaveformCountForTest()
        let kept = try await store.ecgSessions(deviceId: "dev-b")
        XCTAssertGreaterThan(deleted, 0)
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertEqual(count, 0)
        // The other device's session survives.
        XCTAssertEqual(kept.map(\.id), ["ecg-9"])
    }

    func testEcgSessionIdFormat() {
        XCTAssertEqual(EcgWaveformSession.makeId(startTsMs: 1_788_513_405_000), "ecg-1788513405000")
    }
}
