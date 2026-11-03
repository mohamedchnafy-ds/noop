import XCTest
@testable import Strand
import StrandAnalytics
import WhoopStore

/// The day widgets' snapshot and wording (personal fork, chantier 6): what decodes from an older build, which
/// widgets a change reloads, when a day ends, the week strip's marks, the night's phases and the widgets' links.
/// Language-independent: the words come from the catalog and are checked by the render test, in French.
final class DayWidgetsTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        return cal
    }

    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)) ?? Date()
    }

    // MARK: Snapshot

    func testASnapshotFromAnOlderBuildStillDecodes() throws {
        let bare = try XCTUnwrap(DayWidgetsSnapshot.decodeDayWidgets(Data(#"{"dayKey":"2026-11-02"}"#.utf8)))
        XCTAssertEqual(bare.dayKey, "2026-11-02")
        XCTAssertNil(bare.session)
        XCTAssertNil(bare.nutrition)
        XCTAssertNil(bare.sleep)
        XCTAssertFalse(bare.isCurrent(at: date(2, 12)), "without an end, a snapshot is never current")

        let partial = #"{"labels":{"open":"Ouvrir"},"session":{"name":"Full body A","week":[{"letter":"L","mark":"done","isToday":true}]}}"#
        let decoded = try XCTUnwrap(DayWidgetsSnapshot.decodeDayWidgets(Data(partial.utf8)))
        XCTAssertEqual(decoded.labels?.open, "Ouvrir")
        XCTAssertEqual(decoded.labels?.sessionTitle, DayWidgetsSnapshot.Labels.english.sessionTitle,
                       "a label the older build did not write reads in English")
        XCTAssertEqual(decoded.session?.name, "Full body A")
        XCTAssertNil(decoded.session?.state)
        XCTAssertEqual(decoded.session?.week?.first?.mark, .done)
    }

    func testASnapshotRoundTripsAndReloadsOnlyTheWidgetsThatChanged() throws {
        let snap = DayWidgetsSnapshot.galleryPreview
        let data = try JSONEncoder().encode(snap)
        XCTAssertEqual(DayWidgetsSnapshot.decodeDayWidgets(data), snap)

        XCTAssertEqual(snap.changedWidgetKinds(from: nil).count, 3)
        XCTAssertEqual(snap.changedWidgetKinds(from: snap), [])
        var meal = snap
        meal.nutrition?.eaten = "1,800"
        XCTAssertEqual(meal.changedWidgetKinds(from: snap), [DayWidgetsSnapshot.nutritionKind])
        var night = snap
        night.sleep?.night = "7h 02m"
        XCTAssertEqual(night.changedWidgetKinds(from: snap), [DayWidgetsSnapshot.sleepKind])
        var nextDay = snap
        nextDay.validUntil = date(4)
        XCTAssertEqual(nextDay.changedWidgetKinds(from: snap).count, 3, "a new day reloads all three")
    }

    func testTheDayEndsAtTheAppsRollover() {
        let start = date(2)
        XCTAssertEqual(DayWidgetsContent.dayWidgetsValidUntil(dayStart: start, calendar: calendar, rolloverHour: 0),
                       date(3))
        XCTAssertEqual(DayWidgetsContent.dayWidgetsValidUntil(dayStart: start, calendar: calendar, rolloverHour: 4),
                       date(3, 4))
        let snap = DayWidgetsSnapshot(dayKey: "2026-11-02", validUntil: date(3))
        XCTAssertTrue(snap.isCurrent(at: date(2, 23, 59)))
        XCTAssertFalse(snap.isCurrent(at: date(3)), "past midnight the widgets say no data")
    }

    // MARK: Week

    private func day(_ dayOfMonth: Int, isToday: Bool = false, isPast: Bool = false, planned: String? = nil,
                     lifted: Bool = false, cardio: Bool = false) -> TrainingDay {
        let start = Int(date(dayOfMonth, 18).timeIntervalSince1970)
        return TrainingDay(
            date: date(dayOfMonth), key: "2026-11-0\(dayOfMonth)", isToday: isToday, isPast: isPast,
            planned: planned.map { [TrainingPlannedItem(item: .program($0), isDone: lifted)] } ?? [],
            lifts: lifted ? [TrainingLiftDone(sessionId: "s", programId: planned, name: "A", startTs: start,
                                              endTs: start + 3_000, workingSets: 12, effort: nil)] : [],
            activities: cardio ? [TrainingActivityDone(sport: "Run", source: "", startTs: start,
                                                       endTs: start + 1_800, kcal: nil)] : [])
    }

    func testTheWeekStripKeepsOneMarkPerDayByPriority() {
        XCTAssertEqual(DayWidgetsContent.weekMark(day(2, isPast: true, planned: "a", lifted: true, cardio: true)), .done)
        XCTAssertEqual(DayWidgetsContent.weekMark(day(4, isToday: true, planned: "a")), .planned)
        XCTAssertEqual(DayWidgetsContent.weekMark(day(6, planned: "a")), .planned)
        XCTAssertEqual(DayWidgetsContent.weekMark(day(2, isPast: true, planned: "a", cardio: true)), .missed)
        XCTAssertEqual(DayWidgetsContent.weekMark(day(3, isPast: true, cardio: true)), .cardio)
        XCTAssertEqual(DayWidgetsContent.weekMark(day(3, isPast: true, lifted: true)), .done,
                       "a session done on a day off still counts")
        XCTAssertEqual(DayWidgetsContent.weekMark(day(5)), .none)
    }

    func testTheSessionSectionFollowsTheResolverAndThePlan() {
        let today = date(4)
        let monday = Int(date(2, 18).timeIntervalSince1970)
        let row = LiftSessionRow(id: "s1", deviceId: "d", startTs: monday, endTs: monday + 3_000, sport: "lift",
                                 programId: "a", programName: "Full body A", sessionRpe: nil, note: nil)
        let run = WorkoutRow(startTs: Int(date(3, 7).timeIntervalSince1970),
                             endTs: Int(date(3, 7, 30).timeIntervalSince1970), sport: "Running", source: "manual",
                             durationS: 1_800, energyKcal: 300, avgHr: 140, maxHr: 170, strain: 40,
                             distanceM: nil, zonesJSON: nil, notes: nil, steps: nil)
        let plan = TrainingWeekPlan(programs: ["1": "a", "3": "a", "5": "a"], since: "2026-10-26")
        let resolution = TodaySessionResolution(
            session: TodaySynthesisLogic.Session(name: "Full body A", state: .next, supersets: 1, singles: 0,
                                                 typicalMinutes: 55),
            programId: "a",
            programItems: [
                LiftProgramItemRow(id: "1", deviceId: "d", programId: "a", ord: 0, exercise: "Squat",
                                   targetSets: 3, targetRepsLow: 8, targetRepsHigh: 10, targetRpe: nil,
                                   targetWeightKg: 80, restSec: nil, note: nil, supersetGroup: "A"),
                LiftProgramItemRow(id: "2", deviceId: "d", programId: "a", ord: 1, exercise: "Row",
                                   targetSets: 3, targetRepsLow: 8, targetRepsHigh: 10, targetRpe: nil,
                                   targetWeightKg: 60, restSec: 120, note: nil, supersetGroup: "A"),
            ],
            hasPrograms: true, performed: [(row: row, workingSets: 12)], liftWorkouts: [:], otherWorkouts: [run],
            plan: plan)
        let section = DayWidgetsContent.sessionSection(resolution, today: today, calendar: calendar)
        XCTAssertEqual(section.name, "Full body A")
        XCTAssertEqual(section.state, .next)
        XCTAssertEqual(section.line, TodaySynthesisLogic.sessionRow(resolution.session, route: nil).subtitle,
                       "the Synthèse's own line")
        XCTAssertNotEqual(section.lineMedium, section.line, "a session still to do says it is planned")
        XCTAssertEqual(section.blocks?.count, 1)
        XCTAssertEqual(section.week?.map(\.mark), [.done, .cardio, .planned, .none, .planned, .none, .none])
        XCTAssertEqual(section.week?.map(\.isToday), [false, false, true, false, false, false, false])
        XCTAssertEqual(section.tally, "1/3")
        XCTAssertNotNil(section.weekLine)

        var noPlan = resolution
        noPlan.plan = TrainingWeekPlan()
        let free = DayWidgetsContent.sessionSection(noPlan, today: today, calendar: calendar)
        XCTAssertNil(free.tally, "without a plan there is nothing to count against")
        XCTAssertNil(free.weekLine)
        XCTAssertEqual(free.week?.first?.mark, .done)
    }

    // MARK: Sleep

    func testTheNightsPhasesAreMergedAndClipped() {
        let start = 1_000_000
        let segments = [
            StageSegment(start: start - 600, end: start + 1_200, stage: "light"),
            StageSegment(start: start + 1_200, end: start + 2_400, stage: "light"),
            StageSegment(start: start + 2_400, end: start + 3_000, stage: "deep"),
            StageSegment(start: start + 3_000, end: start + 3_020, stage: "rem"),
            StageSegment(start: start + 3_020, end: start + 3_620, stage: "awake"),
            StageSegment(start: start + 3_620, end: start + 9_000, stage: "rem"),
        ]
        let phases = DayWidgetsContent.widgetPhases(segments, from: start, to: start + 4_820)
        XCTAssertEqual(phases.map(\.stage), ["light", "deep", "wake", "rem"],
                       "a stage under half a minute drops, any other stage reads as awake")
        XCTAssertEqual(phases.map(\.minutes), [40, 10, 10, 20], "clipped to the night")
    }

    func testTheWidgetDrawsTheLongestSleepOfTheLastDay() {
        let now = date(2, 12)
        let ts = { (d: Date) in Int(d.timeIntervalSince1970) }
        let night = CachedSleepSession(startTs: ts(date(1, 23, 52)), endTs: ts(date(2, 6, 40)), efficiency: 0.9,
                                       restingHr: 50, avgHrv: 60, stagesJSON: nil)
        let nap = CachedSleepSession(startTs: ts(date(2, 9)), endTs: ts(date(2, 9, 30)), efficiency: 0.9,
                                     restingHr: 55, avgHrv: 50, stagesJSON: nil)
        let older = CachedSleepSession(startTs: ts(date(1, 0)), endTs: ts(date(1, 9)), efficiency: 0.9,
                                       restingHr: 50, avgHrv: 60, stagesJSON: nil)
        XCTAssertEqual(DayWidgetsContent.widgetNight([older, night, nap], now: now)?.endTs, night.endTs)
        XCTAssertNil(DayWidgetsContent.widgetNight([older], now: now), "a night over a day old is not last night")
    }

    // MARK: Words and links

    func testAFigureIsSetApartWhereTheLanguagePutsIt() {
        XCTAssertEqual(DayWidgetsContent.emphasis("dette 1h 12m", value: "1h 12m"),
                       .init(before: "dette ", value: "1h 12m", after: ""))
        XCTAssertEqual(DayWidgetsContent.emphasis("昨晚 1h 少睡", value: "1h"),
                       .init(before: "昨晚 ", value: "1h", after: " 少睡"))
        XCTAssertEqual(DayWidgetsContent.emphasis("dette", value: "1h"), .init(before: "dette", value: "", after: ""))
    }

    func testEachWidgetOpensItsScreen() {
        for link in DayWidgetsSnapshot.Link.allCases {
            XCTAssertEqual(DayWidgetsSnapshot.Link(url: link.url), link)
        }
        XCTAssertEqual(DayWidgetsContent.widgetRoute(.session), .liftLog)
        XCTAssertEqual(DayWidgetsContent.widgetRoute(.nutrition), .nutrition)
        XCTAssertEqual(DayWidgetsContent.widgetRoute(.sleep), .sleep)
        XCTAssertNil(DayWidgetsSnapshot.Link(url: URL(string: "noop://import-health?v=1") ?? URL(fileURLWithPath: "/")))
        XCTAssertNil(DayWidgetsSnapshot.Link(url: URL(string: "noop://widget/other") ?? URL(fileURLWithPath: "/")))
    }
}
