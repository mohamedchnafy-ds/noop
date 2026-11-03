import XCTest
@testable import Strand
import WhoopStore

/// The Coach's action cards (personal fork, chantier 8): how a nap, a workout correction, a set correction
/// and a fact to remember are read, bounded and worded. Pure: no store, no network.
final class CoachActionProposalTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-11-03 16:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_793_721_600)

    private func input(_ json: String) -> [String: Any] { CoachTools.input(fromJSON: json) }

    // MARK: Tools

    func testTheToolsAreNamedAndTheCorrectionsNeedData() {
        XCTAssertEqual(CoachActionProposal.Kind(toolName: "log_nap"), .nap)
        XCTAssertEqual(CoachActionProposal.Kind(toolName: "correct_lift_session"), .liftSets)
        XCTAssertNil(CoachActionProposal.Kind(toolName: "get_night"))
        XCTAssertTrue(CoachActionProposal.Kind.workout.readsData)
        XCTAssertFalse(CoachActionProposal.Kind.remember.readsData)
        let without = CoachTools.definitions(dataConsent: false, labBook: false).compactMap { $0["name"] as? String }
        XCTAssertTrue(without.contains("log_nap"))
        XCTAssertTrue(without.contains("remember"))
        XCTAssertFalse(without.contains("correct_workout"))
        let with = CoachTools.definitions(dataConsent: true, labBook: false).compactMap { $0["name"] as? String }
        XCTAssertTrue(with.contains("correct_workout"))
        XCTAssertTrue(with.contains("correct_lift_session"))
    }

    // MARK: Nap

    func testANapOnTodayWithItsTimes() throws {
        let parsed = CoachActionProposal.nap(from: input(#"{"start": "13:20", "end": "13:50"}"#), now: now,
                                             calendar: calendar)
        let proposal = try XCTUnwrap(parsed.proposal, parsed.problem ?? "")
        XCTAssertEqual(proposal.kind, .nap)
        XCTAssertEqual(proposal.nap, .init(startTs: 1_793_712_000, endTs: 1_793_713_800))
        XCTAssertEqual(proposal.lines.count, 2)
        XCTAssertTrue(proposal.lines[1].hasPrefix("13:20 – 13:50"), proposal.lines[1])
        XCTAssertEqual(proposal.state, .proposed)
    }

    func testANapMustBeShortPastAndRecent() {
        XCTAssertNotNil(CoachActionProposal.nap(from: input(#"{"start": "13:20", "end": "13:25"}"#), now: now,
                                                calendar: calendar).problem)
        XCTAssertNotNil(CoachActionProposal.nap(from: input(#"{"start": "17:00", "end": "17:40"}"#), now: now,
                                                calendar: calendar).problem, "not ended yet")
        XCTAssertNotNil(CoachActionProposal.nap(from: input(#"{"date": "2026-10-20", "start": "13:00", "end": "13:30"}"#),
                                                now: now, calendar: calendar).problem, "too far back")
        XCTAssertNotNil(CoachActionProposal.nap(from: input(#"{"start": "1pm", "end": "13:30"}"#), now: now,
                                                calendar: calendar).problem)
        XCTAssertNotNil(CoachActionProposal.nap(from: input(#"{"date": "2026-11-02", "start": "14:00", "end": "14:45"}"#),
                                                now: now, calendar: calendar).proposal)
    }

    // MARK: Workout

    /// 2026-11-02 18:00–18:45 UTC.
    private func workout(source: String = "manual", sport: String = "Running") -> WorkoutRow {
        WorkoutRow(startTs: 1_793_642_400, endTs: 1_793_642_400 + 2700, sport: sport, source: source,
                   durationS: 2700, energyKcal: 400, avgHr: 140, maxHr: 170, strain: 11, distanceM: 5000,
                   zonesJSON: nil, notes: nil, steps: nil)
    }

    private func km(_ meters: Double) -> String { String(format: "%.1f km", meters / 1000) }

    func testAWorkoutCorrectionKeepsWhatItDoesNotChange() throws {
        let parsed = CoachActionProposal.workoutFix(
            from: input(#"{"date": "2026-11-02", "start": "18:00", "distance_km": 6.2, "avg_hr": 150}"#),
            rows: [workout()], now: now, calendar: calendar, distance: km)
        let proposal = try XCTUnwrap(parsed.proposal, parsed.problem ?? "")
        let fix = try XCTUnwrap(proposal.workout)
        XCTAssertEqual(fix.before, workout())
        XCTAssertEqual(fix.after.distanceM, 6200)
        XCTAssertEqual(fix.after.avgHr, 150)
        XCTAssertEqual(fix.after.startTs, workout().startTs)
        XCTAssertEqual(fix.after.endTs, workout().endTs)
        XCTAssertEqual(fix.after.energyKcal, 400)
        XCTAssertEqual(fix.after.strain, 11, "captured strain kept, as the Workouts sheet does")
        XCTAssertTrue(proposal.lines.contains { $0.hasSuffix("5.0 km → 6.2 km") }, "\(proposal.lines)")
        XCTAssertTrue(proposal.lines.contains { $0.hasSuffix("140 → 150") }, "\(proposal.lines)")
    }

    func testANewStartKeepsTheDurationAndADurationMovesTheEnd() throws {
        let moved = try XCTUnwrap(CoachActionProposal.workoutFix(
            from: input(#"{"date": "2026-11-02", "start": "18:00", "new_start": "18:10"}"#),
            rows: [workout()], now: now, calendar: calendar, distance: km).proposal?.workout)
        XCTAssertEqual(moved.after.startTs, workout().startTs + 600)
        XCTAssertEqual(moved.after.endTs, workout().endTs + 600)
        let longer = try XCTUnwrap(CoachActionProposal.workoutFix(
            from: input(#"{"date": "2026-11-02", "start": "18:00", "duration_min": 60}"#),
            rows: [workout()], now: now, calendar: calendar, distance: km).proposal?.workout)
        XCTAssertEqual(longer.after.endTs, workout().startTs + 3600)
    }

    func testOnlyAHandEnteredWorkoutCanBeCorrected() {
        let parsed = CoachActionProposal.workoutFix(
            from: input(#"{"date": "2026-11-02", "start": "18:00", "avg_hr": 150}"#),
            rows: [workout(source: "my-whoop")], now: now, calendar: calendar, distance: km)
        XCTAssertNil(parsed.proposal)
        XCTAssertTrue(parsed.problem?.contains("cannot be corrected") == true)
        XCTAssertNotNil(CoachActionProposal.workoutFix(
            from: input(#"{"date": "2026-11-02", "start": "19:00", "avg_hr": 150}"#),
            rows: [workout()], now: now, calendar: calendar, distance: km).problem, "no workout then")
        XCTAssertNotNil(CoachActionProposal.workoutFix(
            from: input(#"{"date": "2026-11-02", "start": "18:00"}"#),
            rows: [workout()], now: now, calendar: calendar, distance: km).problem, "nothing changes")
    }

    // MARK: Sets

    private func set(_ id: String, _ exercise: String, _ index: Int, ord: Int, kg: Double, reps: Int) -> LiftSetRow {
        LiftSetRow(id: id, deviceId: "d", sessionId: "s1", ord: ord, exercise: exercise, primaryMuscle: nil,
                   secondaryMuscles: [], setIndex: index, weightKg: kg, reps: reps, rpe: nil, isWarmup: false,
                   startTs: nil, endTs: nil, restSec: nil, note: nil)
    }

    private var session: CoachActionProposal.LiftSession {
        CoachActionProposal.LiftSession(
            row: LiftSessionRow(id: "s1", deviceId: "d", startTs: 1_793_642_400, endTs: 1_793_646_000,
                                sport: "Strength Training", programId: nil, programName: "Full body A",
                                sessionRpe: nil, note: nil),
            sets: [set("a", "Squat", 1, ord: 0, kg: 80, reps: 5), set("b", "Squat", 2, ord: 1, kg: 80, reps: 5),
                   set("c", "Squat", 3, ord: 2, kg: 80, reps: 4), set("d", "Curl", 1, ord: 3, kg: 12, reps: 10)])
    }

    func testASetCorrectionChangesOnlyWhatItNames() throws {
        let parsed = CoachActionProposal.liftFix(
            from: input(#"{"date": "2026-11-02", "changes": [{"exercise": "squat", "set": 2, "weight": 85}]}"#),
            sessions: [session], system: .metric, now: now, calendar: calendar)
        let fix = try XCTUnwrap(parsed.proposal?.lift, parsed.problem ?? "")
        XCTAssertEqual(fix.upserts.map(\.id), ["b"])
        XCTAssertEqual(fix.upserts.first?.weightKg, 85)
        XCTAssertEqual(fix.upserts.first?.reps, 5)
        XCTAssertTrue(fix.deletedIds.isEmpty)
        XCTAssertEqual(fix.before, session.sets)
        XCTAssertTrue(parsed.proposal?.lines.last?.contains("80 kg × 5 → 85 kg × 5") == true,
                      "\(parsed.proposal?.lines ?? [])")
    }

    func testRemovingASetRenumbersTheRestAndAddingOneGoesLast() throws {
        let parsed = CoachActionProposal.liftFix(
            from: input(#"{"date": "2026-11-02", "changes": [{"exercise": "Squat", "set": 1, "remove": true},"#
                        + #"{"exercise": "Curl", "weight": 12, "reps": 8}]}"#),
            sessions: [session], system: .metric, now: now, calendar: calendar, newId: { "new" })
        let fix = try XCTUnwrap(parsed.proposal?.lift, parsed.problem ?? "")
        XCTAssertEqual(fix.deletedIds, ["a"])
        let byId = Dictionary(uniqueKeysWithValues: fix.upserts.map { ($0.id, $0) })
        XCTAssertEqual(byId["b"]?.setIndex, 1)
        XCTAssertEqual(byId["c"]?.setIndex, 2)
        XCTAssertEqual(byId["new"]?.setIndex, 2)
        XCTAssertEqual(byId["new"]?.ord, 4)
        XCTAssertEqual(byId["new"]?.reps, 8)
        XCTAssertNil(byId["d"], "an untouched set is not rewritten")
    }

    func testASetCorrectionNamesWhatIsWrong() {
        func problem(_ json: String) -> String? {
            CoachActionProposal.liftFix(from: input(json), sessions: [session], system: .metric, now: now,
                                        calendar: calendar).problem
        }
        XCTAssertTrue(problem(#"{"date": "2026-11-02", "changes": [{"exercise": "Bench", "set": 1, "reps": 5}]}"#)?
            .contains("Squat, Curl") == true)
        XCTAssertNotNil(problem(#"{"date": "2026-11-02", "changes": [{"exercise": "Squat", "set": 9, "reps": 5}]}"#))
        XCTAssertNotNil(problem(#"{"date": "2026-11-02", "changes": [{"exercise": "Squat", "set": 1, "weight": 900}]}"#))
        XCTAssertNotNil(problem(#"{"date": "2026-11-01", "changes": [{"exercise": "Squat", "set": 1, "reps": 5}]}"#))
        XCTAssertNotNil(problem(#"{"date": "2026-11-02", "changes": [{"exercise": "Squat", "set": 1, "reps": 5}]}"#),
                        "nothing changes")
    }

    // MARK: Remember

    func testAFactGoesToItsFieldAndUndoTakesItOut() throws {
        var profile = CoachProfile()
        profile.constraints = "Shoulder: no overhead press"
        let parsed = CoachActionProposal.rememberCard(
            from: input(#"{"fact": "Knee pain on stairs since October", "kind": "constraint"}"#), profile: profile)
        let fact = try XCTUnwrap(parsed.proposal?.fact)
        let added = CoachActionProposal.profileAdding(fact, to: profile)
        XCTAssertEqual(added.constraints, "Shoulder: no overhead press\nKnee pain on stairs since October")
        XCTAssertEqual(CoachActionProposal.profileRemoving(fact, from: added).constraints, "Shoulder: no overhead press")
        XCTAssertNotNil(CoachActionProposal.rememberCard(
            from: input(#"{"fact": "knee pain on stairs since october", "kind": "constraint"}"#), profile: added).problem,
            "already there")
        let other = try XCTUnwrap(CoachActionProposal.rememberCard(
            from: input(#"{"fact": "Trains at 7 am", "kind": "other"}"#), profile: profile).proposal?.fact)
        XCTAssertEqual(CoachActionProposal.profileAdding(other, to: CoachProfile()).other, "Trains at 7 am")
    }

    // MARK: Stored with the reply

    func testTheCardRoundTripsWithTheReplyAndIsReadBackByTheModel() throws {
        var proposal = try XCTUnwrap(CoachActionProposal.nap(from: input(#"{"start": "13:20", "end": "13:50"}"#),
                                                             now: now, calendar: calendar).proposal)
        proposal.state = .applied
        let text = CoachReplyMeta.join(body: "Noted.", meta: CoachReplyMeta(action: proposal))
        XCTAssertEqual(CoachReplyMeta.split(text).meta?.action, proposal)
        XCTAssertEqual(CoachReplyMeta.body(text), "Noted.")
        let wire = CoachReplyMeta.forModel(text, system: .metric)
        XCTAssertTrue(wire.contains("[log_nap card, confirmed by the user:"), wire)
    }
}
