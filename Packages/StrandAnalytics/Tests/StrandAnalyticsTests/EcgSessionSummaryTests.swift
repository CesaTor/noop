import XCTest
@testable import StrandAnalytics

/// Pins the MG ECG session summary: descriptive rollup only — coverage, stamped-HR
/// center/spread, duration, rate. Empty sessions summarize to zeros/nils (never fabricated),
/// and the median is the documented lower median. Same fixtures as the Kotlin twin.
final class EcgSessionSummaryTests: XCTestCase {

    private func rec(_ ms: Int, hr: Int? = 62, wave: Bool = true) -> EcgSessionSummary.Record {
        EcgSessionSummary.Record(tsMs: ms, hrBpm: hr, signalPresent: wave)
    }

    func testEmptySummarizesToZerosAndNils() {
        let s = EcgSessionSummary.summarize([])
        XCTAssertEqual(s.recordCount, 0)
        XCTAssertEqual(s.waveRecords, 0)
        XCTAssertEqual(s.waveCoverage, 0)
        XCTAssertNil(s.medianHr)
        XCTAssertNil(s.minHr)
        XCTAssertNil(s.maxHr)
        XCTAssertEqual(s.durationSec, 0)
        XCTAssertEqual(s.recordsPerSec, 0)
    }

    func testFullSession() {
        // 5 records over 4 s, one flat, HR bytes 60..64.
        let rows = [rec(1000, hr: 60), rec(2000, hr: 62), rec(3000, hr: 64, wave: false),
                    rec(4000, hr: 61), rec(5000, hr: 63)]
        let s = EcgSessionSummary.summarize(rows)
        XCTAssertEqual(s.recordCount, 5)
        XCTAssertEqual(s.waveRecords, 4)
        XCTAssertEqual(s.waveCoverage, 0.8)
        XCTAssertEqual(s.medianHr, 62)
        XCTAssertEqual(s.minHr, 60)
        XCTAssertEqual(s.maxHr, 64)
        XCTAssertEqual(s.durationSec, 4)
        XCTAssertEqual(s.recordsPerSec, 1.25)
    }

    func testLowerMedianOnEvenCount() {
        // Sorted HR: 60 61 62 63 -> lower median is 61 (index (4-1)/2 = 1).
        let rows = [rec(1000, hr: 63), rec(2000, hr: 60), rec(3000, hr: 62), rec(4000, hr: 61)]
        XCTAssertEqual(EcgSessionSummary.summarize(rows).medianHr, 61)
    }

    func testMissingHrBytesYieldNils() {
        let rows = [rec(1000, hr: nil), rec(2000, hr: nil, wave: false)]
        let s = EcgSessionSummary.summarize(rows)
        XCTAssertEqual(s.recordCount, 2)
        XCTAssertEqual(s.waveRecords, 1)
        XCTAssertEqual(s.waveCoverage, 0.5)
        XCTAssertNil(s.medianHr)
        XCTAssertNil(s.minHr)
        XCTAssertNil(s.maxHr)
    }

    func testSingleRecordHasNoSpan() {
        let s = EcgSessionSummary.summarize([rec(1000, hr: 70)])
        XCTAssertEqual(s.durationSec, 0)
        XCTAssertEqual(s.recordsPerSec, 0)
        XCTAssertEqual(s.medianHr, 70)
    }
}
