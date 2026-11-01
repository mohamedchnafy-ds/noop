import Foundation
import StrandAnalytics
import WhoopStore

// MARK: - Strength progression (personal fork)
//
// The figures behind the Lift Log's Progression screen: per exercise, whether it is still moving; per
// muscle, how many sets it gets and whether it needs more attention; and, once enough sessions exist, how
// the day's Charge and the night before line up with how a session went.
//
// EVERYTHING HERE IS A RULE, NOT A VERDICT FROM A MODEL. Each status is arithmetic the user can redo from
// their own logged sets: a record is a weight never lifted before, or more reps at a weight already
// lifted; an exercise stalls after three sessions without one. No score is invented, no tonnage is added
// up across exercises (100 kg on the leg press is not 100 kg of squat), and nothing warns about injury —
// the same exclusions `LiftMetrics` documents.
//
// NOTHING IS STORED. Every figure is derived on read from the sets already in the database, so this adds
// no migration and nothing for Android to mirror (iPhone only, by the fork owner's choice).
//
// PURE: rows in, values out, no store and no clock, so `LiftProgressTests` pins every rule.

enum LiftProgress {

    // MARK: - Tunables

    /// Sessions an exercise needs before it gets a status. The first one is the baseline every later
    /// session is compared with, so three sessions are the fewest that can show two comparisons.
    static let minimumSessions = 3

    /// How far under the best estimated 1RM before them the last two sessions must both fall to count
    /// as a decline. Five per cent clears the day-to-day noise of a rep more or less.
    static let declineFraction = 0.05

    /// Sessions before the Form view is shown at all: with fewer, a gap between good and bad days is
    /// mostly chance.
    static let formMinimumSessions = 20

    /// Earlier sessions of the same exercise a session is compared with in the Form view.
    static let formLookback = 4

    // MARK: - Input

    /// One finished session with its sets, as the store holds them.
    struct Session: Equatable {
        let row: LiftSessionRow
        let sets: [LiftSetRow]
    }

    /// The program line an exercise is judged against (its rep target), and the program it belongs to.
    struct ProgramLine: Equatable {
        let item: LiftPlanItem
        let programName: String
    }

    // MARK: - Per exercise

    /// One session of one exercise.
    struct Point: Equatable {
        let sessionId: String
        let startTs: Int
        /// The working sets, in the order they were done (warm-ups and sets never performed are left out).
        let sets: [LiftSetRow]
        /// The session's best set, ranked by estimated 1RM as `LiftMetrics.perExercise` ranks it.
        let bestWeightKg: Double?
        let bestReps: Int?
        let estimatedOneRepMaxKg: Double?
        /// A weight never lifted before, or more reps at a weight already lifted. Never true for the
        /// first session, which is the baseline.
        let isRecord: Bool

        /// What the curve plots: the estimated 1RM, or the weight when no set supports an estimate
        /// (more than `LiftMetrics.oneRepMaxRepCeiling` reps).
        var value: Double? { estimatedOneRepMaxKg ?? bestWeightKg }
    }

    /// Where an exercise stands, from its latest sessions.
    enum Status: Equatable {
        /// Fewer than `minimumSessions` sessions: no verdict yet.
        case notEnough(sessions: Int)
        /// The double-progression rule says the load goes up next time (`LiftProgression.suggest`).
        case ready(fromKg: Double, toKg: Double)
        /// The last two sessions both fell clearly under the best estimate before them, without a record.
        case declining(percent: Double)
        /// No record in the last `minimumSessions` sessions; `sessions` counts those since the last one.
        case stalled(sessions: Int)
        /// At least one record in the last `minimumSessions` sessions.
        case progressing

        /// Display and sort order: what needs attention first.
        var rank: Int {
            switch self {
            case .stalled: return 0
            case .declining: return 1
            case .ready: return 2
            case .progressing: return 3
            case .notEnough: return 4
            }
        }

        var needsAttention: Bool {
            switch self {
            case .stalled, .declining: return true
            default: return false
            }
        }

        /// False until the exercise has `minimumSessions` sessions.
        var hasVerdict: Bool {
            if case .notEnough = self { return false }
            return true
        }
    }

    /// One exercise's history and status.
    struct Exercise: Equatable {
        let name: String
        let primaryMuscle: LiftMuscle?
        let secondaryMuscles: [LiftMuscle]
        let line: ProgramLine?
        /// Oldest first.
        let points: [Point]
        let status: Status
    }

    /// Whether each session (oldest first, working sets only) holds a record. The first is the baseline.
    static func recordFlags(_ sessions: [[LiftSetRow]]) -> [Bool] {
        var heaviest: Double?
        var mostReps: [Int: Int] = [:]
        var flags: [Bool] = []
        for (index, sets) in sessions.enumerated() {
            var record = false
            if index > 0 {
                for set in sets {
                    guard let reps = set.reps, reps > 0 else { continue }
                    let kg = set.weightKg ?? 0
                    if let heaviest, kg > heaviest + 0.001 { record = true }
                    if let best = mostReps[weightKey(kg)], reps > best { record = true }
                }
            }
            for set in sets {
                guard let reps = set.reps, reps > 0 else { continue }
                let kg = set.weightKg ?? 0
                heaviest = max(heaviest ?? kg, kg)
                mostReps[weightKey(kg), default: 0] = max(mostReps[weightKey(kg)] ?? 0, reps)
            }
            flags.append(record)
        }
        return flags
    }

    /// A weight as a dictionary key, to the hundredth of a kilogram, so 42.5 and 42.50000001 are one weight.
    private static func weightKey(_ kg: Double) -> Int { Int((kg * 100).rounded()) }

    /// The status from an exercise's points (oldest first) and the sets of its latest session.
    static func status(points: [Point], line: ProgramLine?, stepKg: Double) -> Status {
        let n = points.count
        guard n >= minimumSessions, let last = points.last else { return .notEnough(sessions: n) }

        if let line, let step = LiftProgression.suggest(lastSets: last.sets, item: line.item, stepKg: stepKg) {
            return .ready(fromKg: step.fromKg, toKg: step.toKg)
        }

        let lastTwo = points.suffix(2)
        if !lastTwo.contains(where: \.isRecord),
           let best = points.dropLast(2).compactMap(\.estimatedOneRepMaxKg).max(), best > 0 {
            let recent = lastTwo.compactMap(\.estimatedOneRepMaxKg)
            if recent.count == 2, recent.allSatisfy({ $0 < best * (1 - declineFraction) }), let latest = recent.last {
                return .declining(percent: (latest / best - 1) * 100)
            }
        }

        if points.suffix(minimumSessions).contains(where: \.isRecord) { return .progressing }
        let lastRecord = points.lastIndex(where: \.isRecord) ?? 0
        return .stalled(sessions: n - 1 - lastRecord)
    }

    /// Every exercise in the sessions, each with its points and status.
    ///
    /// `lines` maps an exercise name to the program line that sets its target; an exercise in no program
    /// can still progress, stall or decline, it just never reads "ready".
    static func exercises(sessions: [Session], lines: [String: ProgramLine], stepKg: Double) -> [Exercise] {
        let ordered = sessions.sorted { $0.row.startTs < $1.row.startTs }
        var names: [String] = []
        var perExercise: [String: [Session]] = [:]
        for session in ordered {
            var bySession: [String: [LiftSetRow]] = [:]
            var order: [String] = []
            for set in session.sets.sorted(by: { $0.ord < $1.ord })
            where !set.isWarmup && LiftMetrics.isPerformed(reps: set.reps) {
                if bySession[set.exercise] == nil { order.append(set.exercise) }
                bySession[set.exercise, default: []].append(set)
            }
            for name in order {
                if perExercise[name] == nil { names.append(name) }
                perExercise[name, default: []].append(Session(row: session.row, sets: bySession[name] ?? []))
            }
        }

        return names.map { name in
            let history = perExercise[name] ?? []
            let flags = recordFlags(history.map { $0.sets })
            let points: [Point] = history.enumerated().map { index, entry in
                let best = LiftMetrics.perExercise(entry.sets).first
                return Point(sessionId: entry.row.id, startTs: entry.row.startTs, sets: entry.sets,
                             bestWeightKg: best?.bestWeightKg, bestReps: best?.bestReps,
                             estimatedOneRepMaxKg: best?.bestEstimatedOneRepMaxKg, isRecord: flags[index])
            }
            let latestSet = history.last?.sets.last
            let line = lines[name]
            return Exercise(name: name,
                            primaryMuscle: latestSet?.primaryMuscle ?? line?.item.primaryMuscle,
                            secondaryMuscles: latestSet?.secondaryMuscles ?? line?.item.secondaryMuscles ?? [],
                            line: line,
                            points: points,
                            status: status(points: points, line: line, stepKg: stepKg))
        }
    }

    // MARK: - Periods

    /// The window the Progression screen looks at.
    enum Period: String, CaseIterable, Hashable {
        case fourWeeks, twelveWeeks, all

        /// Whole weeks in the window; nil for everything.
        var weeks: Int? {
            switch self {
            case .fourWeeks: return 4
            case .twelveWeeks: return 12
            case .all: return nil
            }
        }

        /// The window's first instant, or nil for everything.
        func start(now: Int) -> Int? { weeks.map { now - $0 * 7 * 86_400 } }
    }

    /// The points inside the period, oldest first.
    static func points(_ exercise: Exercise, in period: Period, now: Int) -> [Point] {
        guard let start = period.start(now: now) else { return exercise.points }
        return exercise.points.filter { $0.startTs >= start }
    }

    /// Change of the plotted value across the period's points, in per cent; nil under two points.
    static func change(_ points: [Point]) -> Double? {
        let values = points.compactMap(\.value)
        guard values.count >= 2, let first = values.first, let last = values.last, first > 0 else { return nil }
        return (last / first - 1) * 100
    }

    /// Records set inside the period, across every exercise.
    static func recordCount(_ exercises: [Exercise], in period: Period, now: Int) -> Int {
        exercises.reduce(0) { total, exercise in
            total + points(exercise, in: period, now: now).filter(\.isRecord).count
        }
    }

    // MARK: - The double-progression ladder

    /// One session on the ladder: the reps of every working set at the ladder's weight.
    struct LadderRow: Equatable {
        let startTs: Int
        let reps: [Int]
    }

    /// The sessions done at the current weight, as the ladder card shows them.
    struct Ladder: Equatable {
        let weightKg: Double
        /// Oldest first.
        let rows: [LadderRow]
        let targetSets: Int
        let topReps: Int

        var targetTotal: Int { targetSets * topReps }
    }

    /// The latest sessions at the weight the last session used, up to `limit`. Nil without a rep target
    /// or when the last session mixed weights (a pyramid is its own plan).
    static func ladder(_ exercise: Exercise, limit: Int = 4) -> Ladder? {
        guard let item = exercise.line?.item, let top = item.targetRepsHigh ?? item.targetRepsLow, top > 0,
              let weight = singleWeight(exercise.points.last?.sets ?? []) else { return nil }
        var rows: [LadderRow] = []
        for point in exercise.points.reversed() {
            guard let w = singleWeight(point.sets), abs(w - weight) < 0.001 else { break }
            rows.insert(LadderRow(startTs: point.startTs, reps: point.sets.compactMap { $0.reps }), at: 0)
            if rows.count == limit { break }
        }
        return rows.isEmpty ? nil : Ladder(weightKg: weight, rows: rows, targetSets: item.targetSets, topReps: top)
    }

    /// The one weight every set was done at, or nil when they differ or none is typed.
    private static func singleWeight(_ sets: [LiftSetRow]) -> Double? {
        let weights = sets.compactMap(\.weightKg)
        guard let first = weights.first, weights.count == sets.count,
              weights.allSatisfy({ abs($0 - first) < 0.001 }) else { return nil }
        return first
    }

    // MARK: - Per muscle

    /// Every set in the sessions that started inside `[from, to)`.
    private static func sets(_ sessions: [Session], from: Int, to: Int) -> [LiftSetRow] {
        sessions.filter { $0.row.startTs >= from && $0.row.startTs < to }.flatMap(\.sets)
    }

    /// Weeks the average is taken over: the period, but no more weeks than there is history, so someone
    /// who started two weeks ago is not divided by four.
    static func weeksCovered(_ sessions: [Session], period: Period, now: Int) -> Int {
        guard let first = sessions.map(\.row.startTs).min() else { return 1 }
        let history = Int((Double(now - first) / (7 * 86_400)).rounded(.up))
        return max(1, min(period.weeks ?? history, history))
    }

    /// Fractional sets per week for each muscle over the period (direct 1, indirect ½), the same credit
    /// as `LiftMetrics.muscleCounts`.
    static func weeklySets(_ sessions: [Session], period: Period, now: Int) -> [LiftMuscle: Double] {
        let from = period.start(now: now) ?? Int.min
        let counts = LiftMetrics.muscleCounts(sets(sessions, from: from, to: now + 1)).fractional
        let weeks = Double(weeksCovered(sessions, period: period, now: now))
        return counts.mapValues { $0 / weeks }
    }

    /// One muscle's fractional sets in each of the last `weeks` weeks, oldest first.
    static func weekly(_ muscle: LiftMuscle, sessions: [Session], weeks: Int, now: Int) -> [Double] {
        (0..<weeks).map { index in
            let to = now + 1 - (weeks - 1 - index) * 7 * 86_400
            let from = to - 7 * 86_400
            return LiftMetrics.muscleCounts(sets(sessions, from: from, to: to)).fractional[muscle] ?? 0
        }
    }

    /// One exercise's share of a muscle's weekly sets.
    struct Contribution: Equatable {
        let exercise: String
        let direct: Bool
        let setsPerWeek: Double
    }

    /// The exercises that worked a muscle over the period, biggest share first.
    static func contributions(_ muscle: LiftMuscle, sessions: [Session], period: Period, now: Int) -> [Contribution] {
        let from = period.start(now: now) ?? Int.min
        var direct: [String: Double] = [:]
        var indirect: [String: Double] = [:]
        for set in sets(sessions, from: from, to: now + 1) where !set.isWarmup && LiftMetrics.isPerformed(reps: set.reps) {
            if set.primaryMuscle == muscle {
                direct[set.exercise, default: 0] += LiftMuscle.directSetCredit
            } else if set.secondaryMuscles.contains(muscle) {
                indirect[set.exercise, default: 0] += LiftMuscle.indirectSetCredit
            }
        }
        let weeks = Double(weeksCovered(sessions, period: period, now: now))
        let all = direct.map { Contribution(exercise: $0.key, direct: true, setsPerWeek: $0.value / weeks) }
            + indirect.map { Contribution(exercise: $0.key, direct: false, setsPerWeek: $0.value / weeks) }
        return all.sorted { $0.setsPerWeek != $1.setsPerWeek ? $0.setsPerWeek > $1.setsPerWeek : $0.exercise < $1.exercise }
    }

    /// A muscle that needs more attention, and why.
    struct Priority: Equatable {
        let muscle: LiftMuscle
        let setsPerWeek: Double
        /// Under the research reference of `ReferenceDose.hypertrophyMinimumSetsPerWeek` a week.
        let belowReference: Bool
        /// Its direct exercises, when every one of them is stalled or declining; empty otherwise.
        let stuckExercises: [String]
    }

    /// The muscles the program works directly that are under the reference, or whose every direct
    /// exercise is stalled or declining. Both reasons first, then the fewest sets.
    ///
    /// A muscle no program line targets is never a priority: it only gets indirect sets by design, and
    /// flagging it would ask for something the user never planned.
    static func priorities(weekly: [LiftMuscle: Double], exercises: [Exercise], targeted: Set<LiftMuscle>) -> [Priority] {
        let reference = LiftMetrics.ReferenceDose.hypertrophyMinimumSetsPerWeek
        let found: [Priority] = LiftMuscle.allCases.filter { targeted.contains($0) }.compactMap { muscle in
            let sets = weekly[muscle] ?? 0
            let judged = exercises.filter { $0.primaryMuscle == muscle && $0.status.hasVerdict }
            let stuck = judged.filter(\.status.needsAttention).map(\.name)
            let allStuck = !judged.isEmpty && stuck.count == judged.count
            let below = sets < reference
            guard below || allStuck else { return nil }
            return Priority(muscle: muscle, setsPerWeek: sets, belowReference: below,
                            stuckExercises: allStuck ? stuck : [])
        }
        return found.sorted { a, b in
            let aBoth = a.belowReference && !a.stuckExercises.isEmpty
            let bBoth = b.belowReference && !b.stuckExercises.isEmpty
            if aBoth != bBoth { return aBoth }
            return a.setsPerWeek < b.setsPerWeek
        }
    }

    /// The muscles the programs work directly: each line's primary muscle. Without any program, the
    /// primary muscles of what was logged stand in.
    static func targetedMuscles(lines: [String: ProgramLine], exercises: [Exercise]) -> Set<LiftMuscle> {
        let fromLines = Set(lines.values.compactMap(\.item.primaryMuscle))
        return fromLines.isEmpty ? Set(exercises.compactMap(\.primaryMuscle)) : fromLines
    }

    /// Two groups of muscles set side by side.
    enum BalancePair: CaseIterable {
        case pushPull, quadsHamstrings, frontRearDelts

        var sides: (left: [LiftMuscle], right: [LiftMuscle]) {
            switch self {
            case .pushPull:
                return ([.chest, .frontDelts, .sideDelts, .triceps], [.lats, .upperBack, .traps, .rearDelts, .biceps])
            case .quadsHamstrings:
                return ([.quads], [.hamstrings])
            case .frontRearDelts:
                return ([.frontDelts], [.rearDelts])
            }
        }

        /// The two weekly totals; nil when either side has no sets, since a ratio to nothing says nothing.
        func totals(_ weekly: [LiftMuscle: Double]) -> (left: Double, right: Double)? {
            let left = sides.left.reduce(0) { $0 + (weekly[$1] ?? 0) }
            let right = sides.right.reduce(0) { $0 + (weekly[$1] ?? 0) }
            return left > 0 && right > 0 ? (left, right) : nil
        }
    }

    // MARK: - Form of the day

    /// How one session went against the sessions before it, in per cent.
    struct FormSession: Equatable {
        let startTs: Int
        let percent: Double
    }

    /// Each session's median gap, over its exercises, between the best estimated 1RM and the mean of that
    /// exercise's previous `formLookback` estimates. Exercises with no estimate (past
    /// `LiftMetrics.oneRepMaxRepCeiling` reps) or too short a history are left out.
    static func formSessions(_ exercises: [Exercise]) -> [FormSession] {
        var starts: [String: Int] = [:]
        var gaps: [String: [Double]] = [:]
        for exercise in exercises {
            let points = exercise.points
            guard points.count > formLookback else { continue }
            for index in formLookback..<points.count {
                guard let value = points[index].estimatedOneRepMaxKg else { continue }
                let previous = points[(index - formLookback)..<index].compactMap(\.estimatedOneRepMaxKg)
                guard previous.count == formLookback else { continue }
                let mean = previous.reduce(0, +) / Double(previous.count)
                guard mean > 0 else { continue }
                let id = points[index].sessionId
                starts[id] = points[index].startTs
                gaps[id, default: []].append((value / mean - 1) * 100)
            }
        }
        return gaps.compactMap { id, values in
            guard let start = starts[id], let middle = median(values) else { return nil }
            return FormSession(startTs: start, percent: middle)
        }.sorted { $0.startTs < $1.startTs }
    }

    /// The three bands a session is grouped into, best day first.
    enum FormBand: Int, CaseIterable {
        case high, middle, low
    }

    /// The Charge band of a morning's score (0–100), on the app's usual 67 / 34 cut points.
    static func chargeBand(_ charge: Double) -> FormBand {
        charge >= 67 ? .high : charge >= 34 ? .middle : .low
    }

    /// The sleep band of the night before, in minutes asleep: 7 h or more, 6 to 7 h, under 6 h.
    static func sleepBand(_ minutes: Double) -> FormBand {
        minutes >= 420 ? .high : minutes >= 360 ? .middle : .low
    }

    /// The sessions' percentages split into bands. A session with no value for the day is left out.
    static func group(_ sessions: [FormSession], band: (FormSession) -> FormBand?) -> [FormBand: [Double]] {
        var out: [FormBand: [Double]] = [:]
        for session in sessions {
            guard let b = band(session) else { continue }
            out[b, default: []].append(session.percent)
        }
        return out
    }

    /// The middle value; the mean of the two middle ones for an even count. Nil when empty.
    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
