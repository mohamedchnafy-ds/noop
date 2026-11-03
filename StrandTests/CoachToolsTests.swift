import XCTest
@testable import Strand
import StrandAnalytics
import WhoopStore

/// The Coach's read tools (personal fork): which tools a question carries, how inputs are read, and
/// how each result is written. Pure: no store, no network.
final class CoachToolsTests: XCTestCase {

    private func names(_ tools: [[String: Any]]) -> [String] { tools.compactMap { $0["name"] as? String } }

    // MARK: Definitions

    /// Without "Use my data" only the cards are offered (the session, the meal and its Ciqual search, the menu,
    /// the nap and the fact to remember): none reads the user's data and none saves anything without a tap.
    func testOnlyTheCardsWithoutDataAccess() {
        XCTAssertEqual(names(CoachTools.definitions(dataConsent: false, labBook: true)),
                       ["create_program", "search_foods", "log_meal", "read_label", "plan_menu", "log_nap", "remember"])
    }

    func testTheLabBookToolOnlyWithTheSecondOptIn() {
        XCTAssertFalse(names(CoachTools.definitions(dataConsent: true, labBook: false)).contains("get_lab_book"))
        XCTAssertTrue(names(CoachTools.definitions(dataConsent: true, labBook: true)).contains("get_lab_book"))
    }

    func testEveryToolIsNamedOnceAndHasAnObjectSchema() throws {
        let tools = CoachTools.definitions(dataConsent: true, labBook: true)
        let cards = ["create_program", "search_foods", "log_meal", "read_label", "plan_menu", "log_nap", "remember",
                     "correct_workout", "correct_lift_session"]
        XCTAssertEqual(Set(names(tools)), Set(CoachTools.Name.allCases.map(\.rawValue) + cards))
        XCTAssertEqual(names(tools).count, CoachTools.Name.allCases.count + cards.count)
        for tool in tools {
            let schema = try XCTUnwrap(tool["input_schema"] as? [String: Any])
            XCTAssertEqual(schema["type"] as? String, "object")
            XCTAssertNotNil(schema["properties"] as? [String: Any])
            XCTAssertFalse((tool["description"] as? String ?? "").isEmpty)
        }
        // The definitions are sent as JSON: they must serialise.
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: tools))
    }

    // MARK: Input

    func testIntegerInputsAreClampedAndDefaulted() {
        let input = CoachTools.input(fromJSON: #"{"days": 400, "sessions": "3", "other": -5}"#)
        XCTAssertEqual(CoachTools.integer(input, "days", fallback: 30, in: CoachTools.dayRange), 180)
        XCTAssertEqual(CoachTools.integer(input, "sessions", fallback: 8, in: CoachTools.sessionRange), 3)
        XCTAssertEqual(CoachTools.integer(input, "other", fallback: 8, in: CoachTools.sessionRange), 1)
        XCTAssertEqual(CoachTools.integer(input, "missing", fallback: 30, in: CoachTools.dayRange), 30)
    }

    func testInputThatIsNotAnObjectIsEmpty() {
        XCTAssertTrue(CoachTools.input(fromJSON: "[1, 2]").isEmpty)
        XCTAssertTrue(CoachTools.input(fromJSON: "not json").isEmpty)
        XCTAssertNil(CoachTools.text(CoachTools.input(fromJSON: #"{"exercise": "   "}"#), "exercise"))
    }

    func testALongResultIsCutAndSaysSo() {
        let long = String(repeating: "x", count: CoachTools.maxResultCharacters + 50)
        let capped = CoachTools.capped(long)
        XCTAssertTrue(capped.hasPrefix(String(repeating: "x", count: CoachTools.maxResultCharacters)))
        XCTAssertTrue(capped.contains("(cut"))
        XCTAssertEqual(CoachTools.capped("short"), "short")
    }

    // MARK: Results

    private func day(_ key: String, hrv: Double? = nil, sleepMin: Double? = nil) -> DailyMetric {
        DailyMetric(day: key, totalSleepMin: sleepMin, efficiency: 0.91, deepMin: 70, remMin: 90, lightMin: 250,
                    disturbances: 3, restingHr: 55, avgHrv: hrv, recovery: 66, strain: 40, exerciseCount: nil,
                    spo2Pct: 96.4, skinTempDevC: 0.2, respRateBpm: 14.8)
    }

    func testMetricHistoryListsEveryDayWithADashForTheMissingOnes() {
        let keys = ["2026-10-29", "2026-10-30", "2026-10-31"]
        let byDay = ["2026-10-29": day("2026-10-29", hrv: 44), "2026-10-31": day("2026-10-31", hrv: 50)]
        let text = CoachTools.metricHistory(.hrv, dayKeys: keys, byDay: byDay)
        XCTAssertTrue(text.contains("2026-10-29 44"))
        XCTAssertTrue(text.contains("2026-10-30 —"))
        XCTAssertTrue(text.contains("2026-10-31 50"))
        XCTAssertTrue(text.contains("Measured on 2 of 3 days: average 47, lowest 44, highest 50."))
    }

    func testMetricHistoryWithNothingMeasuredSaysSo() {
        let text = CoachTools.metricHistory(.spo2, dayKeys: ["2026-10-30"], byDay: [:])
        XCTAssertTrue(text.contains("Not measured on any of these 1 days."))
    }

    func testSleepIsWrittenInHours() {
        let text = CoachTools.metricHistory(.sleep, dayKeys: ["2026-10-31"],
                                            byDay: ["2026-10-31": day("2026-10-31", sleepMin: 444)])
        XCTAssertTrue(text.contains("2026-10-31 7.4"))
    }

    func testANightWithItsPeriodsInTheLocalTimeZone() {
        let paris = TimeZone(identifier: "Europe/Paris")!
        // 30 Oct 2026 22:41 UTC = 23:41 in Paris (winter time), 31 Oct 05:48 UTC = 06:48.
        let start = 1_793_400_060, end = 1_793_425_680
        let text = CoachTools.night(day: "2026-10-31", metric: day("2026-10-31", hrv: 44, sleepMin: 410),
                                    periods: [(start: start, end: end)], timeZone: paris)
        XCTAssertTrue(text.contains("asleep 6.8h (deep 1.2h, REM 1.5h, light 4.2h), efficiency 91%, disturbances 3"))
        XCTAssertTrue(text.contains("HRV 44 ms, RHR 55 bpm, SpO2 96.4%, respiration 14.8/min, skin-temp deviation +0.2°C"))
        XCTAssertTrue(text.contains("sleep periods: 23:41–06:48 (7.1h)"))
    }

    /// The Sleep screen's curves, grouped every 30 minutes on the clock, with the lowest beat and its time.
    func testANightCarriesItsCurvesEveryThirtyMinutes() {
        let utc = TimeZone(identifier: "UTC")!
        let base = 1_793_404_800 // 2026-10-31 00:00 UTC
        let hr = [HRBucket(ts: base, bpm: 56, minBpm: 54, maxBpm: 58),
                  HRBucket(ts: base + 600, bpm: 52, minBpm: 50, maxBpm: 54),
                  HRBucket(ts: base + 1800, bpm: 49, minBpm: 47, maxBpm: 51)]
        let hrv: [(ts: Int, value: Double)] = [(ts: base + 60, value: 40), (ts: base + 900, value: 50),
                                               (ts: base + 3600, value: 62)]
        let text = CoachTools.night(day: "2026-10-31", metric: nil, periods: [(start: base, end: base + 4000)],
                                    timeZone: utc, heartRate: hr, hrv: hrv)
        XCTAssertTrue(text.contains("sleeping heart rate every 30 min (bpm): 00:00 54, 00:30 49; lowest 49 at 00:30"), text)
        XCTAssertTrue(text.contains("HRV (rMSSD) every 30 min (ms): 00:00 45, 01:00 62"), text)
    }

    func testANightWithoutCurvesHasNoCurveLine() {
        let text = CoachTools.night(day: "2026-10-31", metric: day("2026-10-31", hrv: 44, sleepMin: 410),
                                    periods: [], timeZone: .current)
        XCTAssertFalse(text.contains("every 30 min"))
    }

    func testANightWithNothingRecorded() {
        XCTAssertEqual(CoachTools.night(day: "2026-10-31", metric: nil, periods: [], timeZone: .current),
                       "No night recorded ending on 2026-10-31.")
    }

    func testWorkoutsLeaveOutWhatIsUnknown() {
        let rows = [CoachTools.Workout(day: "2026-10-30", sport: "Running", durationMin: 42, effort: 12.3,
                                       avgHr: 151, maxHr: 178, kcal: 480, distance: "7.2 km"),
                    CoachTools.Workout(day: "2026-10-28", sport: "Walking", durationMin: nil, effort: nil,
                                       avgHr: nil, maxHr: nil, kcal: nil, distance: nil)]
        let text = CoachTools.workouts(rows, days: 30)
        XCTAssertTrue(text.contains("2026-10-30 Running, 42 min, effort 12.3, avg HR 151, max HR 178, 480 kcal, 7.2 km"))
        XCTAssertTrue(text.hasSuffix("2026-10-28 Walking"))
        XCTAssertEqual(CoachTools.workouts([], days: 14), "No workout recorded in the last 14 days.")
    }

    /// The start and "entered by hand" are what `correct_workout` names a workout by (chantier 8).
    func testAWorkoutNamesItsStartAndWhetherItWasEnteredByHand() {
        let row = CoachTools.Workout(day: "2026-11-02", sport: "Running", durationMin: 45, effort: nil, avgHr: nil,
                                     maxHr: nil, kcal: nil, distance: nil, start: "18:00", enteredByHand: true)
        XCTAssertTrue(CoachTools.workouts([row], days: 7).hasSuffix("2026-11-02 18:00 Running, 45 min, entered by hand"))
    }

    private func set(_ exercise: String, _ kg: Double?, _ reps: Int?, warmup: Bool = false) -> LiftSetRow {
        LiftSetRow(id: UUID().uuidString, deviceId: "d", sessionId: "s", ord: 0, exercise: exercise,
                   primaryMuscle: nil, setIndex: 0, weightKg: kg, reps: reps, rpe: nil, isWarmup: warmup,
                   startTs: nil, endTs: nil, restSec: nil, note: nil)
    }

    private let dayKey: (Int) -> String = { "day\($0)" }

    func testExerciseHistoryMatchesIgnoringCaseAndAccentsNewestFirst() {
        let sessions = [
            CoachTools.LiftSession(startTs: 1, programName: "Full body A",
                                   sets: [set("Développé couché", 20, 10, warmup: true), set("Développé couché", 60, 8),
                                          set("Squat", 80, 5)]),
            CoachTools.LiftSession(startTs: 2, programName: nil,
                                   sets: [set("Développé couché", 62.5, 8), set("Développé couché", 62.5, 0)]),
        ]
        let text = CoachTools.exerciseHistory(query: "developpe COUCHE", sessions: sessions, limit: 8,
                                              system: .metric, dayKey: dayKey)
        let lines = text.split(separator: "\n").map(String.init)
        XCTAssertTrue(lines[0].hasPrefix("Développé couché: working sets of its last 2 session(s)"))
        XCTAssertEqual(lines[1], "day2: 62.5×8 · best e1RM 79.17")
        XCTAssertEqual(lines[2], "day1 (Full body A): 60×8 · best e1RM 76")
        XCTAssertFalse(text.contains("20×10"), "warm-ups are left out")
    }

    func testExerciseHistoryKeepsTheLimit() {
        let sessions = (1...5).map { CoachTools.LiftSession(startTs: $0, programName: nil, sets: [set("Squat", 80, 5)]) }
        let text = CoachTools.exerciseHistory(query: "squat", sessions: sessions, limit: 2, system: .metric,
                                              dayKey: dayKey)
        XCTAssertEqual(text.split(separator: "\n").count, 3)
        XCTAssertTrue(text.contains("day5:"))
        XCTAssertFalse(text.contains("day3:"))
    }

    func testAnUnknownExerciseListsTheLoggedOnes() {
        let sessions = [CoachTools.LiftSession(startTs: 1, programName: nil, sets: [set("Squat", 80, 5), set("Curl", 10, 12)])]
        let text = CoachTools.exerciseHistory(query: "Deadlift", sessions: sessions, limit: 8, system: .metric,
                                              dayKey: dayKey)
        XCTAssertEqual(text, "No set of “Deadlift” in the Lift Log. Exercises logged: Curl, Squat")
    }

    func testProgramsWriteSupersetsAsOnPaper() {
        let row = LiftProgramRow(id: "p", deviceId: "d", name: "Full body A", note: nil, createdAt: 0,
                                 updatedAt: 0, archived: false)
        func item(_ ord: Int, _ name: String, group: String?, rest: Int?) -> LiftProgramItemRow {
            LiftProgramItemRow(id: "\(ord)", deviceId: "d", programId: "p", ord: ord, exercise: name,
                               targetSets: 3, targetRepsLow: 8, targetRepsHigh: 10, targetRpe: nil,
                               targetWeightKg: 60, restSec: rest, note: nil, supersetGroup: group)
        }
        let text = CoachTools.programs([.init(row: row, items: [item(0, "Squat", group: nil, rest: 150),
                                                                  item(2, "Press", group: "A", rest: 120),
                                                                  item(1, "Row", group: "A", rest: nil)])],
                                        system: .metric)
        XCTAssertTrue(text.contains("Full body A:"))
        XCTAssertTrue(text.contains("  Squat — 3 × 8-10 · 60 · rest 2:30"))
        XCTAssertTrue(text.contains("  A1 Row — 3 × 8-10 · 60"))
        XCTAssertTrue(text.contains("  A2 Press — 3 × 8-10 · 60 · rest 2:00"))
    }

    func testJournalAndLabBook() {
        let journal = CoachTools.journal([JournalEntry(day: "2026-10-31", question: "Alcohol", answeredYes: false, notes: nil),
                                          JournalEntry(day: "2026-10-30", question: "Caffeine", answeredYes: true,
                                                       notes: "2 cups\nmorning", numericValue: 2)], days: 7)
        XCTAssertTrue(journal.contains("2026-10-30 Caffeine: yes (2) — 2 cups morning"))
        XCTAssertTrue(journal.hasSuffix("2026-10-31 Alcohol: no"))

        let lab = CoachTools.labBook([.init(marker: "Ferritin", day: "2026-09-01", value: "80 ng/mL"),
                                      .init(marker: "Ferritin", day: "2026-10-01", value: "95 ng/mL")])
        XCTAssertTrue(lab.contains("Ferritin: 95 ng/mL (2026-10-01), 80 ng/mL (2026-09-01)"))
    }

    // MARK: Chantier 8 reads

    /// The series-backed metrics read one value per day; a day without one is a dash, never zero.
    func testSeriesMetricsListTheirValuesAndDashTheMissingDays() {
        let keys = ["2026-10-30", "2026-10-31", "2026-11-01"]
        let weight = CoachTools.metricHistory(.weight, dayKeys: keys, values: ["2026-10-30": 80.44, "2026-11-01": 79.9])
        XCTAssertTrue(weight.hasPrefix("Weight (kg, from Apple Health)"), weight)
        XCTAssertTrue(weight.contains("2026-10-30 80.4"))
        XCTAssertTrue(weight.contains("2026-10-31 —"))
        XCTAssertTrue(weight.contains("Measured on 2 of 3 days"))
        let water = CoachTools.metricHistory(.water, dayKeys: keys, values: ["2026-10-31": 1500])
        XCTAssertTrue(water.contains("logged water is not all the water drunk"))
        XCTAssertTrue(water.contains("2026-10-31 1500"))
        XCTAssertTrue(CoachTools.metricHistory(.stress, dayKeys: keys, values: ["2026-11-01": 1.234])
            .contains("2026-11-01 1.2"))
        XCTAssertFalse(CoachTools.Metric.weight.isDailyRow)
        XCTAssertTrue(CoachTools.Metric.hrv.isDailyRow)
        XCTAssertNil(CoachTools.Metric.stress.value(day("2026-11-01", hrv: 40)))
    }

    /// The day's buckets grouped every 30 minutes with the lowest and highest beat, the card's figures, the
    /// sleep inside the day and the zones.
    func testDayHeartRateGroupsTheBucketsAndStatesTheZones() {
        let utc = TimeZone(identifier: "UTC")!
        let base = 1_793_404_800 // 2026-10-31 00:00 UTC
        let buckets = [HRBucket(ts: base + 25_200, bpm: 60, minBpm: 55, maxBpm: 66),
                       HRBucket(ts: base + 25_500, bpm: 70, minBpm: 62, maxBpm: 90),
                       HRBucket(ts: base + 27_000, bpm: 110, minBpm: 95, maxBpm: 150)]
        let zones = TimeInZone(seconds: [600, 300, 0, 0, 0], belowZone1: 3600)
        let text = CoachTools.dayHeartRate(day: "2026-10-31", buckets: buckets,
                                           sleep: [base...(base + 21_600)], restingHR: 52, zones: zones,
                                           hrMax: 187, timeZone: utc)
        XCTAssertTrue(text.contains("lowest 5-min average 60, average 80, highest 110; lowest beat 55, highest beat 150; "
                                    + "resting HR 52"), text)
        XCTAssertTrue(text.contains("asleep: 00:00–06:00"), text)
        XCTAssertTrue(text.contains("  07:00 65 (55–90)"), text)
        XCTAssertTrue(text.contains("  07:30 110 (95–150)"), text)
        XCTAssertTrue(text.contains("below zone 1 1h 00m, zone 1 10m, zone 2 5m, zone 3 0m"), text)
        XCTAssertTrue(text.contains("HR max 187"), text)
    }

    func testADayWithoutHeartRateSaysSo() {
        let text = CoachTools.dayHeartRate(day: "2026-10-31", buckets: [], sleep: [], restingHR: nil, zones: nil,
                                           hrMax: 187, timeZone: .current)
        XCTAssertEqual(text, "No heart rate recorded on 2026-10-31: the strap was not worn or not synced.")
    }

    /// A whole day stays well under the result cap.
    func testAWholeDayOfBucketsFitsTheCap() {
        let base = 1_793_404_800
        let buckets = (0..<288).map { HRBucket(ts: base + $0 * 300, bpm: 60, minBpm: 50, maxBpm: 120) }
        let text = CoachTools.dayHeartRate(day: "2026-10-31", buckets: buckets, sleep: [], restingHR: nil,
                                           zones: nil, hrMax: 187, timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertLessThan(text.count, CoachTools.maxResultCharacters)
        XCTAssertEqual(text.components(separatedBy: "\n").filter { $0.hasPrefix("  ") }.count, 48)
    }

    func testCaffeineListsTheIntakesAndTheActiveEstimate() {
        let utc = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_793_448_000) // 2026-10-31 12:00 UTC
        let intakes = [CaffeineIntake(at: now.addingTimeInterval(-2 * 3600), mg: 95),
                       CaffeineIntake(at: now.addingTimeInterval(-26 * 3600)),
                       CaffeineIntake(at: now.addingTimeInterval(-4 * 3600), mg: 60, externalId: "hk-1")]
        let estimate = CaffeineActiveEstimate.compute(intakes: intakes, now: now)
        let text = CoachTools.caffeine(intakes, estimate: estimate, now: now, timeZone: utc)
        let lines = text.components(separatedBy: "\n")
        XCTAssertEqual(lines[1], "  10:00 (2.0 h ago): 95 mg")
        XCTAssertEqual(lines[2], "  08:00 (4.0 h ago): 60 mg (from Apple Health)")
        XCTAssertEqual(lines[3], "  10:00 (26.0 h ago): amount not given")
        XCTAssertTrue(text.contains("Still active now: about"), text)
        XCTAssertEqual(CoachTools.caffeine([], estimate: CaffeineActiveEstimate.compute(intakes: [], now: now),
                                           now: now, timeZone: utc),
                       "No caffeine logged in the last 48 hours. That says nothing about what was drunk.")
    }

    func testSlotsAlignOnTheClockAndSkipEmptySlots() {
        let slots = CoachTools.slots([(ts: 1800, value: 10), (ts: 3500, value: 20), (ts: 7300, value: 5)], seconds: 1800)
        XCTAssertEqual(slots.map(\.ts), [1800, 7200])
        XCTAssertEqual(slots.first?.mean, 15)
        XCTAssertEqual(slots.first?.low, 10)
        XCTAssertEqual(slots.first?.high, 20)
    }

    func testTheNewToolsAreOfferedWithDataAccessOnly() {
        let with = names(CoachTools.definitions(dataConsent: true, labBook: false))
        XCTAssertTrue(with.contains("get_day_heart_rate"))
        XCTAssertTrue(with.contains("get_caffeine"))
        XCTAssertFalse(names(CoachTools.definitions(dataConsent: false, labBook: false)).contains("get_caffeine"))
    }

    // MARK: Days and labels

    func testDayKeysEndOnTheGivenDayOldestFirst() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 9))!
        XCTAssertEqual(CoachTools.dayKeys(days: 3, endingAt: now, calendar: calendar),
                       ["2026-10-30", "2026-10-31", "2026-11-01"])
    }

    func testAnExerciseLabelIsItsName() {
        let input = CoachTools.input(fromJSON: #"{"exercise": "Squat barre"}"#)
        XCTAssertEqual(CoachTools.label(.exerciseHistory, input: input, now: Date()), "Squat barre")
    }

    func testSameExerciseIgnoresCaseAccentsAndSpaces() {
        XCTAssertTrue(CoachTools.sameExercise(" Développé Militaire ", "developpe militaire"))
        XCTAssertFalse(CoachTools.sameExercise("Squat", "Squat avant"))
    }
}

/// The streamed tool rounds (personal fork): how the Messages API's events become text and tool calls,
/// and what is sent back.
final class AnthropicToolStreamTests: XCTestCase {

    private func feed(_ payloads: [String]) throws -> (text: String, turn: AnthropicTurn) {
        var accumulator = AnthropicTurnAccumulator()
        var text = ""
        for payload in payloads { if let piece = try accumulator.consume(payload) { text += piece } }
        return (text, accumulator.turn())
    }

    func testTextThenAToolCallSplitAcrossDeltas() throws {
        let (text, turn) = try feed([
            #"{"type":"message_start","message":{"id":"m"}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Je "}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"regarde."}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"t1","name":"get_metric_history","input":{}}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"metric\": \"hr"}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"v\", \"days\": 60}"}}"#,
            #"{"type":"content_block_stop","index":1}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"tool_use"}}"#,
            #"{"type":"message_stop"}"#,
        ])
        XCTAssertEqual(text, "Je regarde.")
        XCTAssertEqual(turn.text, "Je regarde.")
        XCTAssertEqual(turn.stopReason, "tool_use")
        XCTAssertEqual(turn.toolCalls.count, 1)
        XCTAssertEqual(turn.toolCalls.first?.name, "get_metric_history")
        let input = CoachTools.input(fromJSON: turn.toolCalls.first?.inputJSON ?? "")
        XCTAssertEqual(input["metric"] as? String, "hrv")
        XCTAssertEqual(input["days"] as? Int, 60)
    }

    func testAToolCallWithNoInputGetsAnEmptyObject() throws {
        let (_, turn) = try feed([
            #"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"t","name":"get_programs","input":{}}}"#,
            #"{"type":"content_block_stop","index":0}"#,
        ])
        XCTAssertEqual(turn.blocks, [.toolUse(id: "t", name: "get_programs", inputJSON: "{}")])
    }

    func testAnErrorEventThrowsTheProviderMessage() {
        var accumulator = AnthropicTurnAccumulator()
        XCTAssertThrowsError(try accumulator.consume(
            #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#)) { error in
            XCTAssertEqual((error as? AICoachError)?.errorDescription,
                           AICoachError.network("Overloaded").errorDescription)
        }
    }

    func testUnknownAndMalformedPayloadsAreIgnored() throws {
        let (text, turn) = try feed(["ping", "{}", #"{"type":"something_new"}"#])
        XCTAssertEqual(text, "")
        XCTAssertTrue(turn.blocks.isEmpty)
    }

    func testTheAssistantTurnAndToolResultsSentBack() throws {
        let turn = AnthropicTurn(blocks: [.text("Je regarde."),
                                          .toolUse(id: "t1", name: "get_night", inputJSON: #"{"date":"2026-10-31"}"#)],
                                 stopReason: "tool_use")
        let assistant = AnthropicToolRequest.assistant(turn)
        XCTAssertEqual(assistant["role"] as? String, "assistant")
        let content = try XCTUnwrap(assistant["content"] as? [[String: Any]])
        XCTAssertEqual(content.map { $0["type"] as? String }, ["text", "tool_use"])
        XCTAssertEqual((content[1]["input"] as? [String: Any])?["date"] as? String, "2026-10-31")

        let results = AnthropicToolRequest.toolResults([(id: "t1", text: "Night ending…", isError: false),
                                                        (id: "t2", text: "Unknown tool x.", isError: true)])
        let blocks = try XCTUnwrap(results["content"] as? [[String: Any]])
        XCTAssertEqual(results["role"] as? String, "user")
        XCTAssertEqual(blocks.map { $0["tool_use_id"] as? String }, ["t1", "t2"])
        XCTAssertNil(blocks[0]["is_error"])
        XCTAssertEqual(blocks[1]["is_error"] as? Bool, true)
    }

    func testTheLastRoundForbidsAnotherCallButKeepsTheTools() throws {
        let tools = CoachTools.definitions(dataConsent: true, labBook: false)
        let open = try JSONSerialization.jsonObject(with: AnthropicToolRequest.body(
            model: "m", system: "s", messages: [AnthropicToolRequest.message(role: "user", text: "q")],
            tools: tools, allowTools: true)) as? [String: Any]
        XCTAssertNil(open?["tool_choice"])
        XCTAssertEqual((open?["tools"] as? [Any])?.count, tools.count)
        XCTAssertEqual(open?["stream"] as? Bool, true)

        let last = try JSONSerialization.jsonObject(with: AnthropicToolRequest.body(
            model: "m", system: "s", messages: [], tools: tools, allowTools: false)) as? [String: Any]
        XCTAssertEqual((last?["tool_choice"] as? [String: Any])?["type"] as? String, "none")
        XCTAssertEqual((last?["tools"] as? [Any])?.count, tools.count)
    }
}

/// What a reply stores besides its words (personal fork).
final class CoachReplyMetaTests: XCTestCase {

    func testRoundTrip() {
        let meta = CoachReplyMeta(consulted: ["HRV since 3 Sept", "Night of 31 Oct"])
        let stored = CoachReplyMeta.join(body: "**Yes**, but lighter.", meta: meta)
        let split = CoachReplyMeta.split(stored)
        XCTAssertEqual(split.body, "**Yes**, but lighter.")
        XCTAssertEqual(split.meta, meta)
        XCTAssertEqual(CoachReplyMeta.body(stored), "**Yes**, but lighter.")
    }

    func testNothingToStoreLeavesTheWordsAlone() {
        XCTAssertEqual(CoachReplyMeta.join(body: "Fine.", meta: nil), "Fine.")
        XCTAssertEqual(CoachReplyMeta.join(body: "Fine.", meta: CoachReplyMeta()), "Fine.")
    }

    func testAReplyWithoutABlockIsAllWords() {
        let text = "Here is code:\n\n```swift\nlet x = 1\n```"
        let split = CoachReplyMeta.split(text)
        XCTAssertEqual(split.body, text)
        XCTAssertNil(split.meta)
    }

    func testABrokenBlockIsKeptAsWords() {
        let text = "Answer." + CoachReplyMeta.fenceOpen + "{not json" + CoachReplyMeta.fenceClose
        XCTAssertEqual(CoachReplyMeta.split(text).body, text)
    }

    func testTheHistoryPreviewAndSearchSkipTheBlock() {
        let stored = CoachReplyMeta.join(body: "Keep Full body A.", meta: CoachReplyMeta(consulted: ["Lift Log programs"]))
        let digest = CoachConversationDigest(messages: [(role: .user, text: "What today?"), (role: .assistant, text: stored)],
                                             briefPrefix: "Today's brief\n\n")
        XCTAssertEqual(digest.preview, "Keep Full body A.")
        XCTAssertFalse(digest.searchText.contains("noop-coach"))
    }
}

/// The role with tools (personal fork): the tools section sits after the role and before the user's
/// own instructions.
@MainActor
final class CoachToolsRoleTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AICoachEngine.extraInstructionsKey)
        super.tearDown()
    }

    func testTheToolsSectionComesBetweenTheRoleAndTheUserInstructions() throws {
        UserDefaults.standard.set("Toujours en kg.", forKey: AICoachEngine.extraInstructionsKey)
        let engine = AICoachEngine(repo: Repository(deviceId: "test-coach-tools-role"))
        let prompt = engine.systemPrompt(withTools: true)
        XCTAssertTrue(prompt.hasPrefix(AICoachEngine.defaultSystemPrompt))
        let tools = try XCTUnwrap(prompt.range(of: "## Outils"))
        let extra = try XCTUnwrap(prompt.range(of: "Toujours en kg."))
        XCTAssertLessThan(tools.lowerBound, extra.lowerBound)
        XCTAssertFalse(engine.systemPrompt.contains("## Outils"), "providers without tools are not told about them")
    }
}
