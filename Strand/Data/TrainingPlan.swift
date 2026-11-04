import Foundation
import WhoopStore

// MARK: - Training week plan and calendar (personal fork)
//
// The Training screen (the former Lift Log front door) plans the week on FIXED days: up to three items per
// weekday (Lift Log programs or cardio, chantier 8), the other days rest. The plan is kept on the iPhone
// (UserDefaults JSON, outside the `.noopbak`, no database migration); the calendar and Today's Synthesis read it, and the Synthesis keeps the
// rotation (`LiftRotation`) when no plan is set. Everything below is pure: dates, the plan, the programs
// and what was done go in; day models and counts come out, so the rules are pinned by tests.

/// One thing planned on a day (fork chantier 8, lot 4): a Lift Log program, or cardio — a sport (its stored
/// English name, `WorkoutCatalog`) and a target length in minutes.
enum TrainingPlanItem: Equatable, Hashable, Codable {
    case program(String)
    case cardio(sport: String, minutes: Int)

    /// The program's id, nil for cardio.
    var programId: String? {
        if case .program(let id) = self { return id }
        return nil
    }

    var isCardio: Bool { programId == nil }

    // A plain object in the stored JSON: {"program": id} or {"sport": name, "minutes": n}.
    private enum CodingKeys: String, CodingKey { case program, sport, minutes }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try container.decodeIfPresent(String.self, forKey: .program) {
            self = .program(id)
        } else {
            self = .cardio(sport: try container.decode(String.self, forKey: .sport),
                           minutes: try container.decodeIfPresent(Int.self, forKey: .minutes) ?? 0)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .program(let id):
            try container.encode(id, forKey: .program)
        case .cardio(let sport, let minutes):
            try container.encode(sport, forKey: .sport)
            try container.encode(minutes, forKey: .minutes)
        }
    }
}

/// The week plan: what is planned on each ISO weekday (1 = Monday … 7 = Sunday), in order, up to
/// `maxItemsPerDay` (fork chantier 8, lot 4: several sessions a day, cardio included). A day not listed is rest.
struct TrainingWeekPlan: Codable, Equatable {
    /// ISO weekday ("1"…"7") → the day's items. String keys keep the stored JSON a plain object.
    var days: [String: [TrainingPlanItem]] = [:]
    /// The first day ("yyyy-MM-dd", local) the plan applies to. Days before it show only what was done,
    /// so saving a plan never marks the weeks before it as missed.
    var since: String?

    /// UserDefaults key of the stored JSON (v2: a list of items per day).
    static let storageKey = "training.weekPlan.v2"
    /// The v1 key (one program per day). Read when no v2 plan is stored, never written nor removed, so
    /// nothing of it is lost.
    static let legacyStorageKey = "training.weekPlan.v1"
    /// At most three items on a day (Mohamed's choice, 3 Nov.).
    static let maxItemsPerDay = 3

    init(days: [String: [TrainingPlanItem]] = [:], since: String? = nil) {
        self.days = days.filter { !$0.value.isEmpty }
        self.since = since
    }

    /// The v1 shape: one program per weekday.
    init(programs: [String: String], since: String? = nil) {
        self.init(days: programs.mapValues { [.program($0)] }, since: since)
    }

    var isEmpty: Bool { days.values.allSatisfy(\.isEmpty) }

    /// What is planned on an ISO weekday, in order; empty for rest.
    func plannedItems(weekday: Int) -> [TrainingPlanItem] { days[String(weekday)] ?? [] }

    /// Adds `item` at the end of `weekday`, unless the day is full.
    mutating func addItem(_ item: TrainingPlanItem, weekday: Int) {
        guard (1...7).contains(weekday) else { return }
        var items = plannedItems(weekday: weekday)
        guard items.count < Self.maxItemsPerDay else { return }
        if case .program(let id) = item, id.isEmpty { return }
        items.append(item)
        days[String(weekday)] = items
    }

    /// Removes the item at `index` of `weekday`; the day becomes rest when nothing is left.
    mutating func removeItem(at index: Int, weekday: Int) {
        var items = plannedItems(weekday: weekday)
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
        days[String(weekday)] = items.isEmpty ? nil : items
    }

    /// The weekdays `programId` is planned on, Monday first.
    func plannedWeekdays(of programId: String) -> [Int] {
        (1...7).filter { plannedItems(weekday: $0).contains(.program(programId)) }
    }

    /// The plan without the programs that no longer exist: a deleted program frees its place; cardio stays.
    func keepingPrograms(_ existing: Set<String>) -> TrainingWeekPlan {
        TrainingWeekPlan(days: days.mapValues { items in
            items.filter { item in item.programId.map { existing.contains($0) } ?? true }
        }, since: since)
    }

    /// What the plan says for `date`: the day's items, or rest; nil when the plan does not decide (no plan,
    /// or a day before it applies), so the rotation decides. The one resolver the calendar, Today's
    /// Synthesis, the widget, the meal reminders and the Coach read.
    func planDecision(for date: Date, calendar: Calendar) -> TrainingPlanDecision? {
        guard !isEmpty else { return nil }
        guard appliesToDay(TrainingCalendar.trainingDayKey(date, calendar: calendar)) else { return nil }
        let items = plannedItems(weekday: TrainingCalendar.isoWeekday(date, calendar: calendar))
        return items.isEmpty ? .rest : .planned(items)
    }

    /// True when the plan applies to the day `key` ("yyyy-MM-dd").
    func appliesToDay(_ key: String) -> Bool {
        guard let since else { return true }
        return key >= since
    }

    /// The v1 stored form, read once to carry an older plan over without loss.
    private struct LegacyWeekPlan: Decodable {
        var programs: [String: String]
        var since: String?
    }

    /// Reads a stored plan, v2 or v1 (each v1 program becomes that day's only item); anything unreadable
    /// is an empty plan.
    static func decodeWeekPlan(_ raw: String?) -> TrainingWeekPlan {
        guard let raw, let data = raw.data(using: .utf8) else { return TrainingWeekPlan() }
        if let plan = try? JSONDecoder().decode(TrainingWeekPlan.self, from: data) {
            return TrainingWeekPlan(days: plan.days, since: plan.since)
        }
        if let legacy = try? JSONDecoder().decode(LegacyWeekPlan.self, from: data) {
            return TrainingWeekPlan(programs: legacy.programs, since: legacy.since)
        }
        return TrainingWeekPlan()
    }

    /// The stored form: sorted keys, so the same plan always writes the same text.
    func encodedWeekPlan() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    /// The stored plan: v2 when one was saved, else the v1 plan carried over.
    static func loadWeekPlan(_ defaults: UserDefaults = .standard) -> TrainingWeekPlan {
        decodeWeekPlan(defaults.string(forKey: storageKey) ?? defaults.string(forKey: legacyStorageKey))
    }

    func storeWeekPlan(_ defaults: UserDefaults = .standard) {
        defaults.set(encodedWeekPlan(), forKey: Self.storageKey)
    }
}

/// What the week plan says for one day.
enum TrainingPlanDecision: Equatable {
    case rest
    /// One to `TrainingWeekPlan.maxItemsPerDay` items, in order.
    case planned([TrainingPlanItem])

    var items: [TrainingPlanItem] {
        if case .planned(let items) = self { return items }
        return []
    }
}

/// Monday-first calendar arithmetic for the week strip and the month grid.
enum TrainingCalendar {
    /// ISO weekday of `date`: 1 = Monday … 7 = Sunday, whatever the calendar's first weekday.
    static func isoWeekday(_ date: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: date)  // 1 = Sunday
        return (weekday + 5) % 7 + 1
    }

    /// Midnight of the Monday of the week holding `date`.
    static func mondayOf(_ date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: -(isoWeekday(day, calendar: calendar) - 1), to: day) ?? day
    }

    /// The seven days (at midnight) from `monday`.
    static func weekDates(from monday: Date, calendar: Calendar) -> [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: monday)) }
    }

    /// Midnight of the first day of the month holding `date`.
    static func monthStart(_ date: Date, calendar: Calendar) -> Date {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: parts) ?? calendar.startOfDay(for: date)
    }

    /// The month as grid cells, Monday first: blanks (nil) before the 1st, every day, then blanks to
    /// complete the last row of seven.
    static func monthCells(containing date: Date, calendar: Calendar) -> [Date?] {
        let first = monthStart(date, calendar: calendar)
        let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        var cells: [Date?] = Array(repeating: nil, count: isoWeekday(first, calendar: calendar) - 1)
        for offset in 0..<count {
            cells.append(calendar.date(byAdding: .day, value: offset, to: first))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    /// "yyyy-MM-dd" of `date` in `calendar` (no formatter: stable whatever the locale).
    static func trainingDayKey(_ date: Date, calendar: Calendar) -> String {
        let p = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", p.year ?? 0, p.month ?? 0, p.day ?? 0)
    }
}

/// A Lift Log session that was done: finished, with at least one working set.
struct TrainingLiftDone: Equatable {
    var sessionId: String
    var programId: String?
    var name: String
    var startTs: Int
    var endTs: Int
    var workingSets: Int
    /// The Effort of the session's own workout row, already in the wearer's scale, when it has one.
    var effort: String?
    /// How long the session was run for, pauses left out (`TrainingDays.liftSessionSeconds`). Nil reads as
    /// end − start.
    var activeSeconds: Int? = nil

    var minutes: Int { (activeSeconds ?? max(0, endTs - startTs)) / 60 }
}

/// Any other workout of the day: run, ride, intervals, a detected bout, an import.
struct TrainingActivityDone: Equatable {
    /// The stored sport name (`WorkoutRow.sport`): planned cardio is matched on it; the screens show it
    /// through `WorkoutSource.displaySport`.
    var sport: String
    /// Where it comes from, already worded ("detected", "recorded", "Apple Health"…).
    var source: String
    var startTs: Int
    var endTs: Int
    var kcal: Int?

    var minutes: Int { max(0, endTs - startTs) / 60 }
}

/// A planned item of a day and whether it was done (`TrainingDays.matchPlanned`).
struct TrainingPlannedItem: Equatable {
    var item: TrainingPlanItem
    var isDone: Bool
}

/// One day of the calendar: what was planned and what was done.
struct TrainingDay: Equatable, Identifiable {
    var date: Date
    var key: String
    var isToday: Bool
    /// Before today (the day is over).
    var isPast: Bool
    /// The plan's items for the day, in order, each matched against what was done.
    var planned: [TrainingPlannedItem]
    var lifts: [TrainingLiftDone]
    var activities: [TrainingActivityDone]

    var id: String { key }
    var hasLift: Bool { !lifts.isEmpty }
    var hasActivity: Bool { !activities.isEmpty }
    /// The planned items not done yet, in order.
    var openItems: [TrainingPlanItem] { planned.filter { !$0.isDone }.map(\.item) }
    /// The programs planned and not done yet, in order.
    var openProgramIds: [String] { openItems.compactMap(\.programId) }
    /// Something planned was not done, and the day is over.
    var isMissed: Bool { !openItems.isEmpty && isPast }
    /// Something planned is still to do (today or later).
    var isPlannedOpen: Bool { !openItems.isEmpty && !isPast }
    /// A program planned and not done (the outlined blue mark), cardio likewise (the outlined pink one).
    var hasOpenLift: Bool { openItems.contains { !$0.isCardio } }
    var hasOpenCardio: Bool { openItems.contains(where: \.isCardio) }
}

/// A block of a program for the planned card: "A1 Squat · A2 Row" and the sets of its first line.
struct TrainingBlockPreview: Equatable {
    var text: String
    var sets: Int?
}

/// What the Training screen shows of a program: its shape, its usual length, when it was last done and
/// its first blocks.
struct TrainingProgramSummary: Equatable, Identifiable {
    var id: String
    var name: String
    var supersets: Int
    var singles: Int
    var totalSets: Int
    var typicalMinutes: Int?
    var lastDoneTs: Int?
    /// The first blocks only (the planned card's preview).
    var blocks: [TrainingBlockPreview]
    /// Every block of the program, previewed or not.
    var blockCount: Int
    /// The loads to raise next time this program is run (fork chantier 9: the day card's « ↑ » lines),
    /// filled once the Progression data is read (`TrainingDays.programRaises`).
    var raises: [TrainingRaise] = []
}

/// One load to raise: an exercise of a program whose last session earned a step up (`LiftProgression`).
struct TrainingRaise: Equatable {
    var exercise: String
    var fromKg: Double
    var toKg: Double
}

/// The most recent day something was done, for the « All history » row: a lift that day, the sports of
/// the other activities (stored names, in order, once each), and when the last of them started.
struct TrainingLatestDone: Equatable {
    var hasLift: Bool
    var sports: [String]
    var startTs: Int
}

enum TrainingDays {
    /// One model per date. A day gets the plan's items when the plan applies to it, its finished Lift Log
    /// sessions and its other activities (by start, local day), and each item is matched against them.
    static func buildTrainingDays(_ dates: [Date], plan: TrainingWeekPlan, lifts: [TrainingLiftDone],
                                  activities: [TrainingActivityDone], now: Date,
                                  calendar: Calendar) -> [TrainingDay] {
        let todayKey = TrainingCalendar.trainingDayKey(now, calendar: calendar)
        func dayKey(_ ts: Int) -> String {
            TrainingCalendar.trainingDayKey(Date(timeIntervalSince1970: TimeInterval(ts)), calendar: calendar)
        }
        let liftsByDay = Dictionary(grouping: lifts) { dayKey($0.startTs) }
        let activitiesByDay = Dictionary(grouping: activities) { dayKey($0.startTs) }
        return dates.map { date in
            let key = TrainingCalendar.trainingDayKey(date, calendar: calendar)
            let dayLifts = (liftsByDay[key] ?? []).sorted { $0.startTs < $1.startTs }
            let dayActivities = (activitiesByDay[key] ?? []).sorted { $0.startTs < $1.startTs }
            let items = plan.planDecision(for: date, calendar: calendar)?.items ?? []
            return TrainingDay(date: calendar.startOfDay(for: date), key: key, isToday: key == todayKey,
                               isPast: key < todayKey,
                               planned: matchPlanned(items, lifts: dayLifts, activities: dayActivities),
                               lifts: dayLifts, activities: dayActivities)
        }
    }

    /// Which of a day's planned items were done. A program is done by a session of that program, else by
    /// any other session of the day left over (a swapped session still counts); cardio is done by an
    /// activity of the same sport that day, whatever its length (the target is a guide). Each session or
    /// activity is used once.
    static func matchPlanned(_ items: [TrainingPlanItem], lifts: [TrainingLiftDone],
                             activities: [TrainingActivityDone]) -> [TrainingPlannedItem] {
        var done = Array(repeating: false, count: items.count)
        var liftsLeft = lifts
        for (index, item) in items.enumerated() {
            guard let id = item.programId, let hit = liftsLeft.firstIndex(where: { $0.programId == id }) else { continue }
            done[index] = true
            liftsLeft.remove(at: hit)
        }
        for (index, item) in items.enumerated() where !item.isCardio && !done[index] && !liftsLeft.isEmpty {
            done[index] = true
            liftsLeft.removeFirst()
        }
        var activitiesLeft = activities
        for (index, item) in items.enumerated() {
            guard case .cardio(let sport, _) = item,
                  let hit = activitiesLeft.firstIndex(where: { isSameSport($0.sport, sport) }) else { continue }
            done[index] = true
            activitiesLeft.remove(at: hit)
        }
        return zip(items, done).map { TrainingPlannedItem(item: $0, isDone: $1) }
    }

    /// Two stored sport names name the same sport: compared in their locale-stable form
    /// (`WorkoutSource.editableSport`, "TraditionalStrengthTraining" = "Traditional Strength Training"),
    /// trimmed, case-insensitively.
    static func isSameSport(_ stored: String, _ planned: String) -> Bool {
        let a = WorkoutSource.editableSport(stored).trimmingCharacters(in: .whitespaces)
        let b = WorkoutSource.editableSport(planned).trimmingCharacters(in: .whitespaces)
        return !a.isEmpty && a.caseInsensitiveCompare(b) == .orderedSame
    }

    /// Sessions done and planned over a period (a week, a month). Every Lift Log session done counts, on
    /// whatever day it was done (a session moved to another day of the week still counts for the week),
    /// plus the planned cardio done; planned = every item of the plan over the period.
    static func sessionTally(_ days: [TrainingDay]) -> (done: Int, planned: Int) {
        let lifts = days.reduce(0) { $0 + $1.lifts.count }
        let cardio = days.reduce(0) { total, day in total + day.planned.filter { $0.isDone && $0.item.isCardio }.count }
        return (lifts + cardio, days.reduce(0) { $0 + $1.planned.count })
    }

    /// The other activities of a period and the minutes of everything done (lifts and activities).
    static func periodTotals(_ days: [TrainingDay]) -> (activities: Int, minutes: Int) {
        let activities = days.reduce(0) { $0 + $1.activities.count }
        let minutes = days.reduce(0) { total, day in
            total + day.lifts.reduce(0) { $0 + $1.minutes } + day.activities.reduce(0) { $0 + $1.minutes }
        }
        return (activities, minutes)
    }

    /// How long a finished Lift Log session was run for, in seconds: its own workout row's duration — which
    /// leaves the session's pauses out (personal fork) — else end − start. The one rule every surface that
    /// states a session's length reads (the calendar, the Synthèse, a program's usual length), so none of
    /// them can disagree with the Workouts list, which shows that same row.
    static func liftSessionSeconds(startTs: Int, endTs: Int, workout: WorkoutRow?) -> Int {
        if let duration = workout?.durationS, duration > 0 { return Int(duration.rounded()) }
        return max(0, endTs - startTs)
    }

    /// Splits workout rows into the rows of Lift Log sessions (each session writes one, at the same
    /// start) and every other activity, so a session is never counted twice.
    static func splitLiftWorkouts(_ rows: [WorkoutRow], liftStarts: [Int],
                                  tolerance: Int = 60) -> (lift: [Int: WorkoutRow], others: [WorkoutRow]) {
        var lift: [Int: WorkoutRow] = [:]
        var others: [WorkoutRow] = []
        for row in rows {
            if let start = liftStarts.first(where: { abs($0 - row.startTs) <= tolerance }), lift[start] == nil {
                lift[start] = row
            } else {
                others.append(row)
            }
        }
        return (lift, others)
    }

    /// The loads to raise in a program, in its order, one per exercise: each exercise's FIRST line judged
    /// against the sets of the last session it was done in, by `LiftProgression.suggest` — the rule the
    /// session sheet applies when it opens (`LiftSessionView.loadLastTime`, judged against the plan's first
    /// line for the exercise, which is this one), so the day card and the session's grey numbers agree.
    /// `lastSets` gives an exercise's working sets from its last session, nil when it was never done.
    static func programRaises(items: [LiftProgramItemRow], lastSets: (String) -> [LiftSetRow]?,
                              stepKg: Double) -> [TrainingRaise] {
        var seen: Set<String> = []
        var raises: [TrainingRaise] = []
        for line in items.sorted(by: { $0.ord < $1.ord }) where !seen.contains(line.exercise) {
            seen.insert(line.exercise)
            guard let sets = lastSets(line.exercise) else { continue }
            let item = LiftPlanItem(exercise: line.exercise, targetSets: line.targetSets,
                                    targetRepsLow: line.targetRepsLow, targetRepsHigh: line.targetRepsHigh,
                                    targetRpe: line.targetRpe, targetWeightKg: line.targetWeightKg)
            if let step = LiftProgression.suggest(lastSets: sets, item: item, stepKg: stepKg) {
                raises.append(TrainingRaise(exercise: line.exercise, fromKg: step.fromKg, toKg: step.toKg))
            }
        }
        return raises
    }

    /// The last day (local, by start) with a Lift Log session or another activity, nil when nothing was
    /// ever done.
    static func latestDone(lifts: [TrainingLiftDone], activities: [TrainingActivityDone],
                           calendar: Calendar) -> TrainingLatestDone? {
        func dayKey(_ ts: Int) -> String {
            TrainingCalendar.trainingDayKey(Date(timeIntervalSince1970: TimeInterval(ts)), calendar: calendar)
        }
        let starts = lifts.map(\.startTs) + activities.map(\.startTs)
        guard let last = starts.max() else { return nil }
        let key = dayKey(last)
        var sports: [String] = []
        for activity in activities.sorted(by: { $0.startTs < $1.startTs }) where dayKey(activity.startTs) == key {
            if !sports.contains(where: { isSameSport($0, activity.sport) }) { sports.append(activity.sport) }
        }
        return TrainingLatestDone(hasLift: lifts.contains { dayKey($0.startTs) == key }, sports: sports,
                                  startTs: last)
    }

    /// A program as the Training screen shows it. `items` in any order; `finished` = its sessions done.
    static func programSummary(id: String, name: String, items: [LiftProgramItemRow],
                               finished: [(startTs: Int, endTs: Int)], previewBlocks: Int = 2) -> TrainingProgramSummary {
        let lines = items.sorted { $0.ord < $1.ord }
        let labels = lines.map(\.supersetGroup)
        let shape = LiftRotation.shape(labels: labels)
        // A superset reads "A1 Squat · A2 Row" with the tags the session screens use (`LiftSuperset.tag`:
        // the superset's position among the program's supersets, whatever its stored label).
        let blocks = LiftSuperset.blocks(labels).map { range -> TrainingBlockPreview in
            let text = range.map { index in
                [LiftSuperset.tag(of: index, in: labels), lines[index].exercise]
                    .compactMap { $0 }.joined(separator: " ")
            }.joined(separator: " · ")
            return TrainingBlockPreview(text: text, sets: lines[range.lowerBound].targetSets)
        }
        return TrainingProgramSummary(
            id: id, name: name, supersets: shape.supersets, singles: shape.singles,
            totalSets: lines.reduce(0) { $0 + ($1.targetSets ?? 0) },
            typicalMinutes: LiftRotation.typicalMinutes(finished),
            lastDoneTs: finished.map { $0.startTs }.max(),
            blocks: Array(blocks.prefix(previewBlocks)),
            blockCount: blocks.count)
    }
}
