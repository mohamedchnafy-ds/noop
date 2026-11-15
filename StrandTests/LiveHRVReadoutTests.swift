import XCTest
@testable import Strand

/// The Live screen's rolling RMSSD is shown only when it is believable (personal fork, Démarrer tools).
final class LiveHRVReadoutTests: XCTestCase {
    func testABelievableValueIsShownAndAnArtefactIsNot() {
        XCTAssertEqual(LiveHRVReadout.shownRMSSD(42), 42)
        XCTAssertEqual(LiveHRVReadout.shownRMSSD(250), 250)
        XCTAssertNil(LiveHRVReadout.shownRMSSD(454))
        XCTAssertNil(LiveHRVReadout.shownRMSSD(nil))
        XCTAssertNil(LiveHRVReadout.shownRMSSD(0))
        XCTAssertNil(LiveHRVReadout.shownRMSSD(.infinity))
    }
}
