import XCTest
@testable import Strand
import WhoopStore

/// The coach's fiche (personal fork): the blocks the coach reads ahead of the day-by-day summary. Pure
/// formatting over resolved inputs, so every rule is pinned without a store or a clock.
final class CoachFicheTests: XCTestCase {

    private func body(stored: Bool = true, hrMaxSet: Bool = false) -> CoachFiche.Body {
        CoachFiche.Body(age: 30, sex: "male", sexStored: stored, heightCm: 178, heightStored: stored,
                        weightKg: 80, weightStored: stored, hrMax: 187, hrMaxSetByUser: hrMaxSet)
    }

    // MARK: Profile

    func testBodyBlockStatesEachFieldAndHowHRMaxWasObtained() {
        let block = CoachFiche.bodyBlock(body())
        XCTAssertTrue(block.hasPrefix("USER PROFILE"))
        XCTAssertTrue(block.contains("age 30, sex male, height 178 cm, weight 80.0 kg, HR max 187 bpm (estimated from age)"),
                      block)
        XCTAssertFalse(block.contains("app default"))
        XCTAssertTrue(CoachFiche.bodyBlock(body(hrMaxSet: true)).contains("(set by the user)"))
    }

    func testBodyBlockMarksTheDefaultsTheUserNeverEntered() {
        let block = CoachFiche.bodyBlock(body(stored: false))
        XCTAssertTrue(block.contains("sex male (not entered: app default)"), block)
        XCTAssertTrue(block.contains("height 178 cm (not entered: app default)"), block)
        XCTAssertTrue(block.contains("weight 80.0 kg (not entered: app default)"), block)
    }

    // MARK: Today

    func testTodayBlockSaysNotMeasuredRatherThanZero() {
        let block = CoachFiche.todayBlock(CoachFiche.Today(day: "2026-11-01"))
        XCTAssertTrue(block.contains("charge not measured, effort so far not measured"), block)
        XCTAssertTrue(block.contains("rest not measured"), block)
        XCTAssertFalse(block.contains("deep"), "no stage breakdown without a night: \(block)")
        XCTAssertTrue(block.contains("RHR not measured, HRV not measured"), block)
        XCTAssertTrue(block.contains("calories not measured"), block)
        XCTAssertFalse(block.contains(" 0 "), block)
    }

    func testTodayBlockNamesTheNightACarriedReadingComesFrom() {
        var today = CoachFiche.Today(day: "2026-11-01")
        today.charge = 66.4
        today.effort = 4.24
        today.restMin = 221
        today.deepMin = 36
        today.remMin = 48
        today.lightMin = 137
        today.efficiency = 0.88
        today.restingHR = CoachFiche.Reading(value: 58, day: "2026-11-01")
        today.hrv = CoachFiche.Reading(value: 38.4, day: "2026-10-31")
        today.skinTempDev = CoachFiche.Reading(value: 0.3, day: "2026-11-01")
        today.steps = 4210
        today.restingKcal = 760.2
        today.activityKcal = 185.4
        let block = CoachFiche.todayBlock(today)
        XCTAssertTrue(block.contains("charge 66, effort so far 4.2"), block)
        XCTAssertTrue(block.contains("rest 3.7h (deep 0.6h, REM 0.8h, light 2.3h, efficiency 88%)"), block)
        XCTAssertTrue(block.contains("RHR 58 bpm, HRV 38 ms (from 2026-10-31)"), block)
        XCTAssertTrue(block.contains("skin-temp deviation +0.3°C"), block)
        XCTAssertTrue(block.contains("steps 4210, calories so far 946 kcal (resting 760, activity 185"), block)
    }

    func testEfficiencyAcceptsAFractionOrAPercentage() {
        XCTAssertEqual(CoachFiche.efficiencyPercent(0.91), "91%")
        XCTAssertEqual(CoachFiche.efficiencyPercent(91), "91%")
        XCTAssertNil(CoachFiche.efficiencyPercent(nil))
        XCTAssertNil(CoachFiche.efficiencyPercent(0))
        XCTAssertNil(CoachFiche.efficiencyPercent(9400))
    }

    // MARK: Normals

    func testGaugeLineSaysWhereLastNightSitsInTheNormal() {
        let gauge = TodayVitalRange.Gauge(value: 38, low: 33, high: 60, normal: 41...51)
        XCTAssertEqual(CoachFiche.gaugeLine(gauge, normal: 41...51, unit: "ms"),
                       "last night 38 ms, your normal 41–51 (below it), last 30 nights 33–60")
        let high = TodayVitalRange.Gauge(value: 66, low: 52, high: 66, normal: 54...60)
        XCTAssertTrue(CoachFiche.gaugeLine(high, normal: 54...60, unit: "bpm").contains("(above it)"))
        let inside = TodayVitalRange.Gauge(value: 57, low: 52, high: 66, normal: 54...60)
        XCTAssertTrue(CoachFiche.gaugeLine(inside, normal: 54...60, unit: "bpm").contains("(within it)"))
    }

    func testGaugeLineUsesTheUnclampedBandAndSaysWhenItIsCalibrating() {
        // The gauge's own band is clamped for drawing; the line states the band the Charge score uses.
        let clamped = TodayVitalRange.Gauge(value: 50, low: 48, high: 58, normal: nil)
        XCTAssertTrue(CoachFiche.gaugeLine(clamped, normal: 60...70, unit: "bpm")
            .contains("your normal 60–70 (below it)"))
        XCTAssertTrue(CoachFiche.gaugeLine(clamped, normal: nil, unit: "bpm")
            .contains("normal not formed yet (calibrating)"))
    }

    func testNormalsBlockIsEmptyWithoutAnyReading() {
        XCTAssertEqual(CoachFiche.normalsBlock(restingHR: nil, restingHRNormal: nil, hrv: nil, hrvNormal: nil,
                                               sleep: nil), "")
        var sleep = CoachFiche.Sleep()
        sleep.lastNightMin = 221
        sleep.average30Min = 414
        XCTAssertEqual(CoachFiche.normalsBlock(restingHR: nil, restingHRNormal: nil, hrv: nil, hrvNormal: nil,
                                               sleep: sleep),
                       "YOUR NORMALS (compare with these, not with population norms):\n"
                       + "  sleep: last night 3.7h, 30-night average 6.9h")
    }

    // MARK: Sleep

    func testSleepBlockGivesTheSuggestedBedtimeFromTheUsualWake() {
        let sleep = CoachFiche.Sleep(needMin: 480, debtMin: 143, isDebt: true, lastShortfallMin: 70,
                                     usualWakeMin: 7 * 60 + 10, lastNightMin: 410, average30Min: nil)
        let block = CoachFiche.sleepBlock(sleep)
        XCTAssertTrue(block.contains("sleep need 8h 00m, sleep debt 2h 23m, last night short by 1h 10m"), block)
        XCTAssertTrue(block.contains("usual wake-up 07:10 (median of the last 14 nights), suggested bedtime 23:10"),
                      block)
    }

    func testSleepBlockWithoutDebtOrUsualWake() {
        let sleep = CoachFiche.Sleep(needMin: 480, debtMin: 4, isDebt: false, lastShortfallMin: nil,
                                     usualWakeMin: nil, lastNightMin: nil, average30Min: nil)
        let block = CoachFiche.sleepBlock(sleep)
        XCTAssertTrue(block.contains("sleep debt none"), block)
        XCTAssertTrue(block.contains("usual wake-up not known yet"), block)
        XCTAssertFalse(block.contains("bedtime"), block)
    }

    func testDurationAndClockFormats() {
        XCTAssertEqual(CoachFiche.duration(143), "2h 23m")
        XCTAssertEqual(CoachFiche.duration(45), "45m")
        XCTAssertEqual(CoachFiche.duration(480), "8h 00m")
        XCTAssertEqual(CoachFiche.clockText(7 * 60 + 5), "07:05")
        XCTAssertEqual(CoachFiche.clockText(-10), "23:50")
    }

    // MARK: Lift Log statuses

    private func exercise(_ name: String, _ status: LiftProgress.Status) -> LiftProgress.Exercise {
        LiftProgress.Exercise(name: name, primaryMuscle: nil, secondaryMuscles: [], line: nil, points: [],
                              status: status)
    }

    func testProgressionBlockPutsAttentionFirstAndStatesEachVerdict() {
        let block = CoachFiche.progressionBlock(
            exercises: [exercise("Squat", .ready(fromKg: 40, toKg: 42.5)),
                        exercise("Curl", .progressing),
                        exercise("Bench", .stalled(sessions: 3)),
                        exercise("Row", .notEnough(sessions: 2)),
                        exercise("Dips", .declining(percent: -6.4))],
            priorities: [LiftProgress.Priority(muscle: .hamstrings, setsPerWeek: 2, belowReference: true,
                                               stuckExercises: [])],
            system: .metric)
        let lines = block.components(separatedBy: "\n")
        XCTAssertTrue(lines[0].hasPrefix("LIFT PROGRESSION"))
        XCTAssertEqual(Array(lines[1...5]), [
            "  Bench: stalled (3 sessions without a record)",
            "  Dips: declining (last e1RM 6% under its best)",
            "  Squat: ready to go up (40 → 42.5 kg)",
            "  Curl: progressing (a record in the last 3 sessions)",
            "  Row: not enough sessions yet (2/3)",
        ])
        XCTAssertEqual(lines[6], "  muscles to prioritise (last 4 weeks): hamstrings (2.0 sets/week, under 4)")
    }

    func testProgressionBlockIsEmptyWithNothingLogged() {
        XCTAssertEqual(CoachFiche.progressionBlock(exercises: [], priorities: [], system: .metric), "")
    }

    // MARK: Order

    func testHeadReadsProfileThenWhatTheUserToldThenToday() {
        var inputs = CoachFiche.Inputs()
        inputs.body = body()
        inputs.today = CoachFiche.Today(day: "2026-11-01")
        inputs.sleep = CoachFiche.Sleep(needMin: 480)
        let head = CoachFiche.head(inputs, told: "WHAT THE USER TOLD THE COACH: …")
        let profile = head.range(of: "USER PROFILE")!.lowerBound
        let told = head.range(of: "WHAT THE USER TOLD THE COACH")!.lowerBound
        let today = head.range(of: "TODAY (")!.lowerBound
        let sleep = head.range(of: "SLEEP (")!.lowerBound
        XCTAssertTrue(profile < told && told < today && today < sleep, head)
        XCTAssertFalse(head.contains("YOUR NORMALS"), "no normals block without a reading")
    }
}
