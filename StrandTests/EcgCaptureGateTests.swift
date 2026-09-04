import XCTest
@testable import Strand

/// Pins the ECG page's capture gate: every blocking precondition maps to its case, and
/// all-true maps to nil. Order matters (link, hardware, bond) and is pinned too.
/// Deliberately no Test Centre case: the opt-in + attestation + bond are the safety
/// gates, and a shipped feature must not hide behind a diagnostics switch.
final class EcgCaptureGateTests: XCTestCase {
    func testReadyNeedsEverything() {
        XCTAssertNil(EcgCaptureBlock.check(connected: true, isMG: true, bonded: true))
    }

    func testDisconnectedWinsOverEverything() {
        XCTAssertEqual(EcgCaptureBlock.check(connected: false, isMG: false, bonded: false),
                       .disconnected)
    }

    func testUnattestedStrapIsNotMG() {
        XCTAssertEqual(EcgCaptureBlock.check(connected: true, isMG: false, bonded: true),
                       .notMG)
    }

    func testLiveHROnlyLinkCannotCapture() {
        XCTAssertEqual(EcgCaptureBlock.check(connected: true, isMG: true, bonded: false),
                       .notBonded)
    }
}
