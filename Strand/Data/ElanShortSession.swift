import Foundation
import WhoopStore

// Personal fork, chantier 10 (Élan), PR C: the SHORT SESSION Élan proposes the day after a missed session.
//
// Built by the app, not by the Coach (Mohamed's choice, 5 Nov.): the first two blocks of the program, in
// its order (`LiftSuperset.blocks`), each line with as many sets and the load of its last session
// (`lastLiftSets`), the program's reps when it states them. Accepted « for tonight », it becomes today's
// session through the week plan itself (`TrainingWeekPlan.extraByDay`, applied by `loadWeekPlan` from
// `ElanShortSessionChoice`), so the Synthèse, the « Start » sheet, the Training day card and the widget all
// name it the way they name a planned session, and starting it from any of them runs THIS plan
// (`LiftSessionController.beginTodayProgramSession`). The rules are pure (`ElanShortSessionTests`); the
// loader reads the store the way the program editor does.

/// One line of the short session: the exercise, its tag in the block, and the targets it runs with.
struct ElanShortLine: Equatable {
    /// The program line it comes from.
    var item: LiftProgramItemRow
    /// "A1", "A2"… inside a superset, nil for a line done on its own.
    var tag: String?
    /// Working sets to do: the last session's count when there was one, else the program's, else 3.
    var sets: Int
    /// The program's rep target (its low end), else the last session's heaviest set's reps.
    var reps: Int?
    /// The load of the last session's heaviest working set, else the program's planned load.
    var weightKg: Double?
    /// The rest after a set (a line on its own) or after a round (a superset).
    var restSec: Int

    var exercise: String { item.exercise }
}

/// A block of the short session: a superset's lines, or one line on its own.
struct ElanShortBlock: Equatable {
    var lines: [ElanShortLine]
    var isSuperset: Bool { lines.count > 1 }
    /// "A" for a superset, nil for a line on its own.
    var letter: String? { lines.first?.tag.map { String($0.prefix { $0.isLetter }) } }
    var restSec: Int { lines.first?.restSec ?? ElanShortSession.defaultRestSec }
    var sets: Int { lines.reduce(0) { $0 + $1.sets } }
}

/// The short session as built, the plan the sheet shows and the session runs.
struct ElanShortSessionPlan: Equatable {
    var programId: String
    var programName: String
    var blocks: [ElanShortBlock]

    var lines: [ElanShortLine] { blocks.flatMap(\.lines) }
    var supersets: Int { blocks.filter(\.isSuperset).count }
    var singles: Int { blocks.filter { !$0.isSuperset }.count }
    var totalSets: Int { blocks.reduce(0) { $0 + $1.sets } }
    /// « Full body B · version courte ».
    var title: String { ElanShortSession.elanShortTitle(programName) }
    var estimatedMinutes: Int { ElanShortSession.elanEstimatedMinutes(blocks) }
}

enum ElanShortSession {
    /// The blocks the short session keeps: the program's first two (the mockup's « 2 premiers supersets »).
    static let blockCount = 2
    /// The rest when a line states none: the mockup's 1:30, the rest a superset added from the body map takes.
    static let defaultRestSec = LiftProgramBlocks.supersetRestSec
    /// Seconds one set takes, for the length estimate.
    static let workSecondsPerSet = 45
    /// Fallbacks for an exercise never logged whose line states no targets.
    static let defaultSets = LiftProgramBlocks.defaultSets
    static let defaultReps = LiftProgramBlocks.defaultReps

    /// The program's first `count` blocks, each as its lines in order (`LiftSuperset.blocks` over the lines
    /// sorted by `ord`). Fewer when the program has fewer; empty for an empty program.
    static func elanShortLines(_ items: [LiftProgramItemRow], count: Int = blockCount) -> [[LiftProgramItemRow]] {
        let lines = items.sorted { $0.ord < $1.ord }
        let blocks = LiftSuperset.blocks(lines.map(\.supersetGroup))
        return blocks.prefix(max(0, count)).map { range in range.map { lines[$0] } }
    }

    /// The targets one line runs with. Sets and load come from the last session when there is one (as many
    /// sets as its working sets, the load of its heaviest working set: `LiftProgramBlocks.supersetDraftTargets`),
    /// else from the program line; reps are the program's low end when it states one, else the last
    /// session's heaviest set's reps; never logged and nothing stated: 3 × 10, no load.
    static func elanShortTargets(line: LiftProgramItemRow, lastSets: [LiftSetRow]) -> (sets: Int, reps: Int?, weightKg: Double?) {
        let working = lastSets.filter { !$0.isWarmup }
        if working.isEmpty {
            return (max(1, line.targetSets ?? defaultSets), line.targetRepsLow ?? defaultReps, line.targetWeightKg)
        }
        let last = LiftProgramBlocks.supersetDraftTargets(lastSets: lastSets)
        return (max(1, last.sets), line.targetRepsLow ?? last.reps, last.weightKg ?? line.targetWeightKg)
    }

    /// The short session of a program, from its lines and each exercise's last sets. Nil for a program
    /// without lines. The tags are the session's own (`LiftSuperset.tag` over the kept lines), so a short
    /// session that keeps the program's second superset still reads A1, A2.
    static func elanShortPlan(programId: String, name: String, items: [LiftProgramItemRow],
                              lastSets: (String) -> [LiftSetRow]) -> ElanShortSessionPlan? {
        let kept = elanShortLines(items)
        guard !kept.isEmpty else { return nil }
        let flat = kept.flatMap { $0 }
        let labels = LiftSuperset.relabeled(flat.map(\.supersetGroup))
        var index = 0
        let blocks = kept.map { lines -> ElanShortBlock in
            let shortLines = lines.map { item -> ElanShortLine in
                let targets = elanShortTargets(line: item, lastSets: lastSets(item.exercise))
                let line = ElanShortLine(item: item, tag: LiftSuperset.tag(of: index, in: labels), sets: targets.sets,
                                         reps: targets.reps, weightKg: targets.weightKg,
                                         restSec: max(0, item.restSec ?? defaultRestSec))
                index += 1
                return line
            }
            return ElanShortBlock(lines: shortLines)
        }
        return ElanShortSessionPlan(programId: programId, programName: name, blocks: blocks)
    }

    /// How long the short session takes, in whole minutes rounded up to five: each set's work, then one rest
    /// per round of a superset (its lines' sets are done in alternation) or per set of a line on its own.
    static func elanEstimatedMinutes(_ blocks: [ElanShortBlock]) -> Int {
        var seconds = 0
        for block in blocks {
            seconds += block.sets * workSecondsPerSet
            let rounds = block.isSuperset ? (block.lines.map(\.sets).max() ?? 0) : block.sets
            seconds += max(0, rounds - 1) * block.restSec
        }
        guard seconds > 0 else { return 0 }
        return ((seconds + 299) / 300) * 5
    }

    /// « Full body B · version courte »: the name the session is saved under and shown with.
    static func elanShortTitle(_ programName: String) -> String {
        programName + " · " + String(localized: "short version")
    }

    /// « 2 supersets · 12 sets · rest 1:30 » (the shape, then the sets, then the first block's rest).
    static func elanShapeLine(_ plan: ElanShortSessionPlan) -> String {
        var parts = [TrainingText.shapeLine(supersets: plan.supersets, singles: plan.singles)].filter { !$0.isEmpty }
        parts.append(plan.totalSets == 1 ? String(localized: "1 set") : String(localized: "\(plan.totalSets) sets"))
        if let rest = plan.blocks.first?.restSec, rest > 0 {
            parts.append(String(localized: "rest \(elanClock(rest))"))
        }
        return parts.joined(separator: " · ")
    }

    /// The short session as the Training day card shows a program: its two blocks as the previews (the sets
    /// the short session runs, not the program's), its estimated length, no load to raise (the short session
    /// runs the last session's loads).
    static func elanProgramSummary(_ plan: ElanShortSessionPlan) -> TrainingProgramSummary {
        let blocks = plan.blocks.map { block -> TrainingBlockPreview in
            let text = block.lines.map { line in [line.tag, line.exercise].compactMap { $0 }.joined(separator: " ") }
                .joined(separator: " · ")
            return TrainingBlockPreview(text: text, sets: block.lines.first?.sets)
        }
        return TrainingProgramSummary(id: plan.programId, name: plan.title, supersets: plan.supersets,
                                      singles: plan.singles, totalSets: plan.totalSets,
                                      typicalMinutes: plan.estimatedMinutes, lastDoneTs: nil, blocks: blocks,
                                      blockCount: plan.blocks.count, raises: [], elanShort: true)
    }

    /// « 2 supersets · ≈ 20 min »: the planned row's line in the « Start » sheet.
    static func elanPlannedLine(_ plan: ElanShortSessionPlan) -> String {
        var parts = [TrainingText.shapeLine(supersets: plan.supersets, singles: plan.singles)].filter { !$0.isEmpty }
        if plan.estimatedMinutes > 0 { parts.append(String(localized: "≈ \(plan.estimatedMinutes) min")) }
        return parts.joined(separator: " · ")
    }

    /// « 1:30 » for 90 seconds.
    static func elanClock(_ seconds: Int) -> String {
        String(format: "%d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
    }

    /// « 3 × 8 · 70 kg » for one line (the load in the wearer's units; left out when none is known).
    static func elanLineTargets(_ line: ElanShortLine, system: UnitSystem) -> (sets: String, load: String?) {
        let sets = line.reps.map { "\(line.sets) × \($0)" } ?? "\(line.sets) ×"
        return (sets, line.weightKg.map { UnitFormatter.massFromKilograms($0, system: system) })
    }

    /// The short session of `programId` from the store: its lines and each exercise's last sets, read as the
    /// program editor reads them. Nil when the store is closed or the program is gone or empty.
    @MainActor
    static func loadElanShortSession(repo: Repository, programId: String) async -> ElanShortSessionPlan? {
        guard let store = await repo.storeHandle() else { return nil }
        let programs = (try? await store.liftPrograms(deviceId: repo.deviceId, includeArchived: true)) ?? []
        guard let program = programs.first(where: { $0.id == programId }) else { return nil }
        let items = (try? await store.liftProgramItems(programId: programId)) ?? []
        var lastByExercise: [String: [LiftSetRow]] = [:]
        for line in elanShortLines(items).flatMap({ $0 }) where lastByExercise[line.exercise] == nil {
            lastByExercise[line.exercise] = (try? await store.lastLiftSets(deviceId: repo.deviceId, exercise: line.exercise)) ?? []
        }
        return elanShortPlan(programId: programId, name: program.name, items: items,
                             lastSets: { lastByExercise[$0] ?? [] })
    }
}

// MARK: - Starting it

extension LiftSessionController {
    /// Starts Élan's short session: its lines as the plan, snapshot at start like a program's. The lines
    /// carry no program line id, so finishing never offers to write the short counts or order back onto the
    /// program — a short session is not the program — while the session keeps the program's id, so the
    /// calendar ticks the planned item and the week counts it. A session already running is brought up instead.
    func beginElanShortSession(_ plan: ElanShortSessionPlan, repo: Repository) async {
        guard !isActive else {
            isPresented = true
            return
        }
        guard !plan.lines.isEmpty, let store = await repo.storeHandle() else { return }
        let vocabulary = (try? await store.liftExercises(deviceId: repo.deviceId)) ?? []
        let labels = LiftSuperset.relabeled(plan.lines.map(\.item.supersetGroup))
        let items = plan.lines.enumerated().map { index, line -> LiftPlanItem in
            let known = vocabulary.first { $0.name == line.exercise }
            return LiftPlanItem(exercise: line.exercise,
                                primaryMuscle: known?.primaryMuscle,
                                secondaryMuscles: known?.secondaryMuscles ?? [],
                                targetSets: line.sets,
                                restSec: line.restSec,
                                targetRepsLow: line.reps ?? line.item.targetRepsLow,
                                targetRepsHigh: line.item.targetRepsHigh ?? line.reps,
                                targetRpe: line.item.targetRpe,
                                targetWeightKg: line.weightKg,
                                note: line.item.note,
                                programItemId: nil,
                                supersetGroup: labels[index])
        }
        guard !isActive else {
            isPresented = true
            return
        }
        start(plan: items, programId: plan.programId, programName: plan.title)
    }

    /// The one start every « Start » of a planned program shares (the Training day card, the « Start »
    /// sheet, the session widget): Élan's short version when it was accepted for today, else the whole program.
    func beginTodayProgramSession(programId: String, programName: String, repo: Repository, now: Date = Date()) async {
        let today = TrainingCalendar.trainingDayKey(now, calendar: .current)
        if ElanShortSessionChoice.acceptedProgramId(day: today) == programId,
           let plan = await ElanShortSession.loadElanShortSession(repo: repo, programId: programId) {
            await beginElanShortSession(plan, repo: repo)
        } else {
            await beginProgramSession(programId: programId, programName: programName, repo: repo)
        }
    }
}
