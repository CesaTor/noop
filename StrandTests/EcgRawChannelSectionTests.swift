import XCTest
@testable import Strand

/// Pins the type-43 raw-channel appendix of the MG ECG probe report: counts-only observation with
/// the multiplex caveat always attached — never an ECG identification.
final class EcgRawChannelSectionTests: XCTestCase {
    func testZeroRecordsNamesThePumpSilence() {
        let section = BLEManager.ecgRawChannelSection(seen: 0, withSignal: 0, windowSeconds: 30)
        XCTAssertTrue(section.contains("Type-43 raw channel in 30s: 0 records"), section)
        XCTAssertTrue(section.contains("multiplexed raw carrier, not an ECG identification"), section)
    }

    func testCountsCarryTheWaveformSplit() {
        let section = BLEManager.ecgRawChannelSection(seen: 100, withSignal: 80, windowSeconds: 30)
        XCTAssertTrue(section.contains("100 records, 80 with waveform"), section)
        XCTAssertTrue(section.contains("more than 20 nonzero body bytes"), section)
        XCTAssertTrue(section.contains("Read alongside the verdict above, not instead of it"), section)
    }
}
