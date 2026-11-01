import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// The Lift Log's Progression data, read once per Lift Log load and shared by the card and the screens it
// opens (personal fork). The rules live in `LiftProgress`; this file reads the store and dresses statuses
// for display.

/// Everything the Progression card and screens draw from.
struct LiftProgressData: Equatable {
    var sessions: [LiftProgress.Session] = []
    var lines: [String: LiftProgress.ProgramLine] = [:]
    var exercises: [LiftProgress.Exercise] = []
    /// The morning Charge (0–100) of each local day, `yyyy-MM-dd`.
    var charge: [String: Double] = [:]
    /// Minutes asleep the night that ended on each local day.
    var sleep: [String: Double] = [:]
    var now: Int = 0

    var isEmpty: Bool { sessions.isEmpty }

    /// Exercises with a verdict, attention first, then alphabetically.
    func group(_ rank: Int) -> [LiftProgress.Exercise] {
        exercises.filter { $0.status.rank == rank }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    func count(_ rank: Int) -> Int { exercises.filter { $0.status.rank == rank }.count }

    var readyExercises: [LiftProgress.Exercise] { group(LiftProgress.Status.ready(fromKg: 0, toKg: 0).rank) }

    var targeted: Set<LiftMuscle> { LiftProgress.targetedMuscles(lines: lines, exercises: exercises) }

    func weekly(_ period: LiftProgress.Period) -> [LiftMuscle: Double] {
        LiftProgress.weeklySets(sessions, period: period, now: now)
    }

    func priorities(_ period: LiftProgress.Period) -> [LiftProgress.Priority] {
        LiftProgress.priorities(weekly: weekly(period), exercises: exercises, targeted: targeted)
    }

    func exercise(named name: String) -> LiftProgress.Exercise? { exercises.first { $0.name == name } }

    /// Reads every finished session with its sets, the programs' lines, and the daily Charge and sleep.
    @MainActor
    static func load(repo: Repository, stepKg: Double) async -> LiftProgressData? {
        guard let store = await repo.storeHandle() else { return nil }
        let now = Int(Date().timeIntervalSince1970)
        let rows = ((try? await store.liftSessions(deviceId: repo.deviceId, fromTs: 0, toTs: now)) ?? [])
            .filter { $0.endTs != nil }                 // an abandoned session is not history
        var sessions: [LiftProgress.Session] = []
        for row in rows {
            let sets = (try? await store.liftSets(sessionId: row.id)) ?? []
            sessions.append(LiftProgress.Session(row: row, sets: sets))
        }

        // The first program (most recently touched) that names an exercise sets its target.
        let programs = (try? await store.liftPrograms(deviceId: repo.deviceId)) ?? []
        let vocabulary = (try? await store.liftExercises(deviceId: repo.deviceId)) ?? []
        var lines: [String: LiftProgress.ProgramLine] = [:]
        for program in programs {
            let items = (try? await store.liftProgramItems(programId: program.id)) ?? []
            for item in items where lines[item.exercise] == nil {
                let known = vocabulary.first { $0.name == item.exercise }
                let plan = LiftPlanItem(exercise: item.exercise,
                                        primaryMuscle: known?.primaryMuscle,
                                        secondaryMuscles: known?.secondaryMuscles ?? [],
                                        targetSets: item.targetSets,
                                        restSec: item.restSec,
                                        targetRepsLow: item.targetRepsLow,
                                        targetRepsHigh: item.targetRepsHigh,
                                        targetRpe: item.targetRpe,
                                        targetWeightKg: item.targetWeightKg)
                lines[item.exercise] = LiftProgress.ProgramLine(item: plan, programName: program.name)
            }
        }

        var charge: [String: Double] = [:]
        var sleep: [String: Double] = [:]
        for day in repo.days {
            if let value = day.recovery { charge[day.day] = value }
            if let minutes = day.totalSleepMin, minutes > 0 { sleep[day.day] = minutes }
        }

        return LiftProgressData(sessions: sessions, lines: lines,
                                exercises: LiftProgress.exercises(sessions: sessions, lines: lines, stepKg: stepKg),
                                charge: charge, sleep: sleep, now: now)
    }
}

// MARK: - Display

extension LiftProgress.Status {
    var tint: Color {
        switch self {
        case .progressing: return StrandPalette.statusPositive
        case .ready: return StrandPalette.effortBright
        case .stalled: return StrandPalette.statusWarning
        case .declining: return StrandPalette.statusCritical
        case .notEnough: return StrandPalette.textTertiary
        }
    }

    var symbol: String {
        switch self {
        case .progressing: return "arrow.up.right"
        case .ready: return "arrow.up.to.line"
        case .stalled: return "arrow.right"
        case .declining: return "arrow.down.right"
        case .notEnough: return "clock"
        }
    }

    /// The short label beside an exercise: "stalled", "ready to go up".
    var label: String {
        switch self {
        case .progressing: return String(localized: "progressing")
        case .ready: return String(localized: "ready to go up")
        case .stalled: return String(localized: "stalled")
        case .declining: return String(localized: "declining")
        case .notEnough: return String(localized: "not enough sessions")
        }
    }
}

/// Group titles and counter labels, by `LiftProgress.Status.rank`.
enum LiftProgressText {
    static let ranks = [0, 1, 2, 3]

    static func groupTitle(_ rank: Int) -> String {
        switch rank {
        case 0: return String(localized: "Stalled")
        case 1: return String(localized: "Declining")
        case 2: return String(localized: "Ready to go up")
        case 3: return String(localized: "Progressing")
        default: return String(localized: "Not enough sessions yet")
        }
    }

    static func counterLabel(_ rank: Int) -> String {
        switch rank {
        case 0: return String(localized: "stalling")
        case 1: return String(localized: "declining")
        case 2: return String(localized: "ready to raise")
        default: return String(localized: "progressing")
        }
    }

    /// The status a rank stands for, for its tint and symbol.
    static func sample(_ rank: Int) -> LiftProgress.Status {
        switch rank {
        case 0: return .stalled(sessions: 0)
        case 1: return .declining(percent: 0)
        case 2: return .ready(fromKg: 0, toKg: 0)
        case 3: return .progressing
        default: return .notEnough(sessions: 0)
        }
    }

    /// "+6 %", "−5 %": a signed whole percentage in the user's locale.
    static func percent(_ value: Double) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always()))
    }

    /// "24 kg × 11", or "× 12" for a set with no weight typed.
    static func set(_ kg: Double?, _ reps: Int?, system: UnitSystem) -> String {
        let r = reps.map(String.init) ?? "—"
        guard let kg, kg > 0 else { return "× \(r)" }
        return "\(LiftFormat.weight(kg, system: system)) × \(r)"
    }

    /// "40 kg × 12 · 12 · 11": one weight, every set's reps; the full list when the weights differ.
    static func sets(_ sets: [LiftSetRow], system: UnitSystem) -> String {
        guard let first = sets.first else { return "" }
        let weights = sets.map { $0.weightKg ?? 0 }
        if weights.allSatisfy({ abs($0 - weights[0]) < 0.001 }) {
            let reps = sets.map { $0.reps.map(String.init) ?? "—" }.joined(separator: " · ")
            guard let kg = first.weightKg, kg > 0 else { return "× \(reps)" }
            return "\(LiftFormat.weight(kg, system: system)) × \(reps)"
        }
        return sets.map { set($0.weightKg, $0.reps, system: system) }.joined(separator: " · ")
    }

    /// "28 Oct."
    static func day(_ ts: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(ts)).formatted(.dateTime.day().month(.abbreviated))
    }

    /// A count of sets with up to one decimal: "3", "3.5".
    static func setCount(_ value: Double) -> String { LiftFormat.trim((value * 10).rounded() / 10) }

    /// "Quads · Full body A".
    static func subtitle(_ exercise: LiftProgress.Exercise) -> String {
        [exercise.primaryMuscle?.displayName, exercise.line?.programName].compactMap { $0 }.joined(separator: " · ")
    }
}

/// The small arrow-in-a-colour that marks a status.
struct LiftStatusIcon: View {
    let status: LiftProgress.Status
    var size: CGFloat = 13

    var body: some View {
        Image(systemName: status.symbol)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(status.tint)
            .accessibilityHidden(true)
    }
}
