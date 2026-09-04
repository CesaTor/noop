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

    // MARK: - estimateBpm (synthetic spike trains at known rates; real-capture
    // validation lives in the analyzer's doc comment, not in fixtures)

    /// A clean spike train: unit impulses every `period` samples over `count` peaks.
    private func spikeTrain(period: Int, peaks: Int, amp: Int = 1000) -> [Int] {
        var s = [Int](repeating: 0, count: period * peaks + 10)
        for k in 0..<peaks { s[k * period + 5] = amp }
        return s
    }

    func testClean60bpmTrain() {
        // 100 Hz, one spike/sec -> 60 bpm, 6 beats.
        let est = EcgSessionSummary.estimateBpm(samples: spikeTrain(period: 100, peaks: 6),
                                                samplesPerSec: 100)
        XCTAssertEqual(est.beats, 6)
        XCTAssertEqual(est.bpm, 60)
    }

    func testClean90bpmTrain() {
        // 100 Hz, spike every 67 samples (~0.67 s) -> ~90 bpm.
        let est = EcgSessionSummary.estimateBpm(samples: spikeTrain(period: 67, peaks: 8),
                                                samplesPerSec: 100)
        XCTAssertEqual(est.bpm, 90)
    }

    func testFlatIsUnreadable() {
        XCTAssertEqual(EcgSessionSummary.estimateBpm(samples: [Int](repeating: 0, count: 500),
                                                     samplesPerSec: 100),
                       EcgSessionSummary.BeatEstimate(bpm: nil, beats: 0))
        XCTAssertNil(EcgSessionSummary.estimateBpm(samples: [Int](repeating: 7, count: 500),
                                                   samplesPerSec: 100).bpm)
    }

    func testTooFewBeatsIsUnreadable() {
        // Two spikes only: below the 4-beat floor, even though the rate is sensible.
        let est = EcgSessionSummary.estimateBpm(samples: spikeTrain(period: 100, peaks: 2),
                                                samplesPerSec: 100)
        XCTAssertNil(est.bpm)
        XCTAssertEqual(est.beats, 2)
    }

    func testImplausiblySlowIsRejected() {
        // Four spikes 3 s apart: detected, but 20 bpm is outside 30...220, so nil.
        let est = EcgSessionSummary.estimateBpm(samples: spikeTrain(period: 300, peaks: 4),
                                                samplesPerSec: 100)
        XCTAssertNil(est.bpm)
        XCTAssertEqual(est.beats, 4)
    }

    func testEmptyAndDegenerate() {
        XCTAssertNil(EcgSessionSummary.estimateBpm(samples: [], samplesPerSec: 100).bpm)
        XCTAssertNil(EcgSessionSummary.estimateBpm(samples: [1, 2], samplesPerSec: 100).bpm)
        XCTAssertNil(EcgSessionSummary.estimateBpm(samples: spikeTrain(period: 100, peaks: 6),
                                                   samplesPerSec: 0).bpm)
    }

    // MARK: - agreedWaveBpm (cross-validated display rule)

    func testAgreementShows() {
        // Within 10 of the stamped median: the number may show.
        XCTAssertEqual(EcgSessionSummary.agreedWaveBpm(
            medianHr: 63, estimate: EcgSessionSummary.BeatEstimate(bpm: 65, beats: 28)), 65)
        // Boundary is inclusive.
        XCTAssertEqual(EcgSessionSummary.agreedWaveBpm(
            medianHr: 60, estimate: EcgSessionSummary.BeatEstimate(bpm: 70, beats: 28)), 70)
    }

    func testDisagreementHides() {
        // T-wave lock (reads high): hidden, not shown wrong.
        XCTAssertNil(EcgSessionSummary.agreedWaveBpm(
            medianHr: 67, estimate: EcgSessionSummary.BeatEstimate(bpm: 98, beats: 40)))
        // Unreadable estimate: hidden.
        XCTAssertNil(EcgSessionSummary.agreedWaveBpm(
            medianHr: 67, estimate: EcgSessionSummary.BeatEstimate(bpm: nil, beats: 2)))
        // No stamped median to agree with: hidden.
        XCTAssertNil(EcgSessionSummary.agreedWaveBpm(
            medianHr: nil, estimate: EcgSessionSummary.BeatEstimate(bpm: 65, beats: 28)))
    }
}
