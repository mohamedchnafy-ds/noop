import Foundation
import WhoopStore

// MARK: - Training week plan and calendar (personal fork)
//
// The Training screen (the former Lift Log front door) plans the week on FIXED days: one Lift Log program
// per weekday, the other days rest. The plan is kept on the iPhone (UserDefaults JSON, outside the
// `.noopbak`, no migration); the calendar and Today's Synthesis read it, and the Synthesis keeps the
// rotation (`LiftRotation`) when no plan is set. Everything below is pure: dates, the plan, the programs
// and what was done go in; day models and counts come out, so the rules are pinned by tests.

/// The week plan: a program id per ISO weekday (1 = Monday … 7 = Sunday). A day not listed is rest.
struct TrainingWeekPlan: Codable, Equatable {
    /// ISO weekday ("1"…"7") → program id. String keys keep the stored JSON a plain object.
    var programs: [String: String] = [:]
    /// The first day ("yyyy-MM-dd", local) the plan applies to. Days before it show only what was done,
    /// so saving a plan never marks the weeks before it as missed.
    var since: String?

    /// UserDefaults key of the stored JSON.
    static let storageKey = "training.weekPlan.v1"

    var isEmpty: Bool { programs.isEmpty }

    /// The program planned on an ISO weekday, nil for rest.
    func plannedProgramId(weekday: Int) -> String? { programs[String(weekday)] }

    /// Plans `programId` on `weekday`, or rest when nil.
    mutating func assignProgram(_ programId: String?, weekday: Int) {
        guard (1...7).contains(weekday) else { return }
        if let programId, !programId.isEmpty {
            programs[String(weekday)] = programId
        } else {
            programs.removeValue(forKey: String(weekday))
        }
    }

    /// The weekdays `programId` is planned on, Monday first.
    func plannedWeekdays(of programId: String) -> [Int] {
        (1...7).filter { programs[String($0)] == programId }
    }

    /// The plan without the programs that no longer exist: a deleted program frees its day.
    func keepingPrograms(_ existing: Set<String>) -> TrainingWeekPlan {
        var copy = self
        copy.programs = programs.filter { existing.contains($0.value) }
        return copy
    }

    /// True when the plan applies to the day `key` ("yyyy-MM-dd").
    func appliesToDay(_ key: String) -> Bool {
        guard let since else { return true }
        return key >= since
    }

    /// Reads a stored plan; anything unreadable is an empty plan.
    static func decodeWeekPlan(_ raw: String?) -> TrainingWeekPlan {
        guard let raw, let data = raw.data(using: .utf8),
              let plan = try? JSONDecoder().decode(TrainingWeekPlan.self, from: data) else {
            return TrainingWeekPlan()
        }
        return plan
    }

    /// The stored form: sorted keys, so the same plan always writes the same text.
    func encodedWeekPlan() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    static func loadWeekPlan(_ defaults: UserDefaults = .standard) -> TrainingWeekPlan {
        decodeWeekPlan(defaults.string(forKey: storageKey))
    }

    func storeWeekPlan(_ defaults: UserDefaults = .standard) {
        defaults.set(encodedWeekPlan(), forKey: Self.storageKey)
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

    var minutes: Int { max(0, endTs - startTs) / 60 }
}

/// Any other workout of the day: run, ride, intervals, a detected bout, an import.
struct TrainingActivityDone: Equatable {
    var sport: String
    /// Where it comes from, already worded ("detected", "recorded", "Apple Health"…).
    var source: String
    var startTs: Int
    var endTs: Int
    var kcal: Int?

    var minutes: Int { max(0, endTs - startTs) / 60 }
}

/// One day of the calendar: what was planned and what was done.
struct TrainingDay: Equatable, Identifiable {
    var date: Date
    var key: String
    var isToday: Bool
    /// Before today (the day is over).
    var isPast: Bool
    var plannedProgramId: String?
    var lifts: [TrainingLiftDone]
    var activities: [TrainingActivityDone]

    var id: String { key }
    var hasLift: Bool { !lifts.isEmpty }
    var hasActivity: Bool { !activities.isEmpty }
    /// Planned, nothing lifted, and the day is over.
    var isMissed: Bool { plannedProgramId != nil && lifts.isEmpty && isPast }
    /// Planned and still to do (today or later): the outlined dot.
    var isPlannedOpen: Bool { plannedProgramId != nil && lifts.isEmpty && !isPast }
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
}

enum TrainingDays {
    /// One model per date. A day gets the plan's program when the plan applies to it, its finished
    /// Lift Log sessions and its other activities (by start, local day).
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
            let planned = plan.appliesToDay(key)
                ? plan.plannedProgramId(weekday: TrainingCalendar.isoWeekday(date, calendar: calendar)) : nil
            return TrainingDay(date: calendar.startOfDay(for: date), key: key, isToday: key == todayKey,
                               isPast: key < todayKey, plannedProgramId: planned,
                               lifts: (liftsByDay[key] ?? []).sorted { $0.startTs < $1.startTs },
                               activities: (activitiesByDay[key] ?? []).sorted { $0.startTs < $1.startTs })
        }
    }

    /// Lift sessions done and planned over a period (a week, a month). Every session done counts, on
    /// whatever day it was done: a session moved to another day of the week still counts for the week.
    static func sessionTally(_ days: [TrainingDay]) -> (done: Int, planned: Int) {
        (days.reduce(0) { $0 + $1.lifts.count }, days.filter { $0.plannedProgramId != nil }.count)
    }

    /// The other activities of a period and the minutes of everything done (lifts and activities).
    static func periodTotals(_ days: [TrainingDay]) -> (activities: Int, minutes: Int) {
        let activities = days.reduce(0) { $0 + $1.activities.count }
        let minutes = days.reduce(0) { total, day in
            total + day.lifts.reduce(0) { $0 + $1.minutes } + day.activities.reduce(0) { $0 + $1.minutes }
        }
        return (activities, minutes)
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
