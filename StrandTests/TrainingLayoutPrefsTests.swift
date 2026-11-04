import XCTest
@testable import Strand

/// « Customize Training » (personal fork, chantier 9): the stored order and hidden set of the blocks under
/// the day card.
final class TrainingLayoutPrefsTests: XCTestCase {

    func testNothingStoredIsTheMockupOrder() {
        XCTAssertEqual(TrainingLayoutPrefs.decodeSectionOrder(""), [.progression, .programs, .otherActivities])
        XCTAssertEqual(TrainingLayoutPrefs.shownSections(orderRaw: "", hiddenRaw: ""),
                       TrainingSection.defaultOrder)
    }

    func testStoredOrderKeepsEachBlockOnceAndInsertsTheMissingOnes() {
        XCTAssertEqual(TrainingLayoutPrefs.decodeSectionOrder("otherActivities,progression,programs"),
                       [.otherActivities, .progression, .programs])
        // Unknown and repeated tokens dropped; Programs missing, inserted after Progression.
        XCTAssertEqual(TrainingLayoutPrefs.decodeSectionOrder("otherActivities, progression,stats,progression"),
                       [.otherActivities, .progression, .programs])
        // Progression missing: no block precedes it in the default order, so it goes first.
        XCTAssertEqual(TrainingLayoutPrefs.decodeSectionOrder("programs,otherActivities"),
                       [.progression, .programs, .otherActivities])
    }

    func testHiddenBlocksLeaveThePageAndRoundTrip() {
        let order = TrainingLayoutPrefs.encodeSections([.programs, .otherActivities, .progression])
        XCTAssertEqual(order, "programs,otherActivities,progression")
        XCTAssertEqual(TrainingLayoutPrefs.decodeHiddenSections("progression,nope"), [.progression])
        XCTAssertEqual(TrainingLayoutPrefs.shownSections(orderRaw: order, hiddenRaw: "progression"),
                       [.programs, .otherActivities])
    }
}
