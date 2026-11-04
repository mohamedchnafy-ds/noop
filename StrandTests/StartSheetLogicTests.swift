import XCTest
@testable import Strand

/// The « Start » sheet opened by Today's « + » (personal fork): what it lists as planned today, which
/// programs it offers, which five live sports it shows, and the week's session count.
final class StartSheetLogicTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_793_800_000)
    private var nowTs: Int { Int(now.timeIntervalSince1970) }

    private func program(_ id: String, blocks: Int = 3) -> TrainingProgramSummary {
        TrainingProgramSummary(id: id, name: "Program \(id)", supersets: 0, singles: blocks, totalSets: blocks * 3,
                               typicalMinutes: nil, lastDoneTs: nil, blocks: [], blockCount: blocks)
    }

    private func day(isToday: Bool = true, planned: [TrainingPlannedItem], lifts: [TrainingLiftDone] = [],
                     activities: [TrainingActivityDone] = []) -> TrainingDay {
        TrainingDay(date: now, key: "2026-11-04", isToday: isToday, isPast: !isToday, planned: planned,
                    lifts: lifts, activities: activities)
    }

    private func activity(_ sport: String, daysAgo: Int) -> TrainingActivityDone {
        let start = nowTs - daysAgo * 86_400
        return TrainingActivityDone(sport: sport, source: "recorded", startTs: start, endTs: start + 1_800, kcal: nil)
    }

    // MARK: - Planned today

    func testPlannedRowsListOpenProgramsThenCardioInPlanOrder() {
        let today = day(planned: [
            TrainingPlannedItem(item: .cardio(sport: "Elliptical", minutes: 30), isDone: false),
            TrainingPlannedItem(item: .program("b"), isDone: false),
            TrainingPlannedItem(item: .program("a"), isDone: true),
            TrainingPlannedItem(item: .program("gone"), isDone: false),
        ])
        let rows = StartSheetLogic.startPlannedRows(day: today, programs: [program("a"), program("b")])
        XCTAssertEqual(rows, [.program(program("b")), .cardio(sport: "Elliptical", minutes: 30)])
    }

    func testPlannedRowsAreEmptyOnAnotherDayOrWithoutADay() {
        let planned = [TrainingPlannedItem(item: .program("a"), isDone: false)]
        XCTAssertEqual(StartSheetLogic.startPlannedRows(day: day(isToday: false, planned: planned),
                                                        programs: [program("a")]), [])
        XCTAssertEqual(StartSheetLogic.startPlannedRows(day: nil, programs: [program("a")]), [])
    }

    func testOnlyProgramsWithLinesCanStart() {
        let ids = StartSheetLogic.startablePrograms([program("a"), program("empty", blocks: 0), program("b")]).map(\.id)
        XCTAssertEqual(ids, ["a", "b"])
    }

    // MARK: - Sport grid

    func testSportGridRanksByCountThenRecencyAndLeavesStrengthOut() {
        let activities = [
            activity("Running", daysAgo: 10), activity("Running", daysAgo: 20),
            activity("Elliptical", daysAgo: 1), activity("Elliptical", daysAgo: 5),
            activity("Rowing", daysAgo: 3),
            activity("Weightlifting", daysAgo: 1), activity("Weightlifting", daysAgo: 2),
            activity("Weightlifting", daysAgo: 4),
            activity("Other", daysAgo: 1),
            activity("Free text sport", daysAgo: 1),
            // Outside the 90-day window.
            activity("Yoga", daysAgo: 120), activity("Yoga", daysAgo: 121), activity("Yoga", daysAgo: 122),
        ]
        let grid = StartSheetLogic.startSportGrid(activities: activities, recent: [], now: now)
        XCTAssertEqual(Array(grid.prefix(3)), ["Elliptical", "Running", "Rowing"])
        XCTAssertEqual(grid.count, StartSheetLogic.sportGridCount)
        XCTAssertFalse(grid.contains("Weightlifting"))
        XCTAssertFalse(grid.contains("Other"))
        XCTAssertFalse(grid.contains("Yoga"))
    }

    func testSportGridFillsWithRecentsThenDefaultsOnce() {
        let grid = StartSheetLogic.startSportGrid(activities: [activity("Walking", daysAgo: 2)],
                                                  recent: ["Pilates", "Walking", "Strength"], now: now)
        XCTAssertEqual(grid, ["Walking", "Pilates", "Running", "Cycling", "Elliptical"])
    }

    func testSportGridMatchesTheCatalogueWhateverTheStoredSpelling() {
        let grid = StartSheetLogic.startSportGrid(activities: [activity("treadmill walk", daysAgo: 1)],
                                                  recent: [], now: now, count: 1)
        XCTAssertEqual(grid, ["Treadmill walk"])
    }

    // MARK: - Week count

    func testSessionsThisWeekCountsLiftsAndActivities() {
        let lift = TrainingLiftDone(sessionId: "s", programId: "a", name: "A", startTs: nowTs, endTs: nowTs + 3_000,
                                    workingSets: 9, effort: nil)
        let days = [
            day(planned: [], lifts: [lift], activities: [activity("Running", daysAgo: 0)]),
            day(isToday: false, planned: [], activities: [activity("Walking", daysAgo: 1)]),
        ]
        XCTAssertEqual(StartSheetLogic.sessionsThisWeek(days), 3)
    }
}
