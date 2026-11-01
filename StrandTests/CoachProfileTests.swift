import XCTest
@testable import Strand

/// What the user tells the coach (personal fork): storage, the context block and the equipment toggle.
final class CoachProfileTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "test-coach-profile"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private var filled: CoachProfile {
        CoachProfile(goal: .muscle, sessionsPerWeek: 3, sessionMinutes: 60, equipment: [.fullGym, .dumbbells],
                     equipmentNote: "no leg press", constraints: "right shoulder\n sensitive  ",
                     other: "football on Sundays")
    }

    func testRoundTripsThroughUserDefaults() {
        filled.save(to: defaults)
        XCTAssertEqual(CoachProfile.load(from: defaults), filled)
    }

    func testAnEmptyProfileRemovesTheKey() {
        filled.save(to: defaults)
        CoachProfile().save(to: defaults)
        XCTAssertNil(defaults.data(forKey: CoachProfile.storageKey))
        XCTAssertEqual(CoachProfile.load(from: defaults), CoachProfile())
    }

    func testUnknownValuesAreDroppedOneByOne() throws {
        let json = #"{"goal":"marathon","sessionsPerWeek":12,"sessionMinutes":45,"equipment":["sled","dumbbells"],"other":"x"}"#
        defaults.set(Data(json.utf8), forKey: CoachProfile.storageKey)
        let profile = CoachProfile.load(from: defaults)
        XCTAssertNil(profile.goal)
        XCTAssertNil(profile.sessionsPerWeek, "outside the offered 1–7")
        XCTAssertEqual(profile.sessionMinutes, 45)
        XCTAssertEqual(profile.equipment, [.dumbbells])
        XCTAssertEqual(profile.other, "x")
    }

    func testToggledKeepsDisplayOrderAndRemoves() {
        var profile = CoachProfile()
        profile.equipment = profile.toggled(.bodyweight)
        profile.equipment = profile.toggled(.fullGym)
        XCTAssertEqual(profile.equipment, [.fullGym, .bodyweight])
        profile.equipment = profile.toggled(.bodyweight)
        XCTAssertEqual(profile.equipment, [.fullGym])
    }

    func testContextBlockStatesEachAnswerOnItsOwnLine() {
        XCTAssertEqual(filled.contextBlock, """
        WHAT THE USER TOLD THE COACH (their own answers; respect them):
          goal: muscle gain
          training: 3 sessions per week, about 60 min each
          equipment: full gym, dumbbells; no leg press
          pain or constraints: right shoulder / sensitive
          other: football on Sundays
        """)
    }

    func testContextBlockAsksTheCoachToAskWhenNothingIsFilled() {
        let block = CoachProfile().contextBlock
        XCTAssertTrue(block.contains("nothing yet"), block)
        XCTAssertTrue(block.contains("Ask before prescribing"), block)
        let blank = CoachProfile(constraints: "  \n ")
        XCTAssertTrue(blank.isEmpty, "whitespace is not an answer")
    }

    func testPartialRhythmLines() {
        XCTAssertTrue(CoachProfile(sessionsPerWeek: 4).contextBlock.contains("training: 4 sessions per week\n")
                      || CoachProfile(sessionsPerWeek: 4).contextBlock.hasSuffix("training: 4 sessions per week"))
        XCTAssertTrue(CoachProfile(sessionMinutes: 45).contextBlock.contains("training: sessions of about 45 min"))
    }

    func testSummaryIsNeverEmpty() {
        XCTAssertFalse(CoachProfile().summary.isEmpty)
        XCTAssertFalse(CoachProfile(other: "x").summary.isEmpty)
        XCTAssertTrue(filled.summary.contains(" · "))
    }
}
