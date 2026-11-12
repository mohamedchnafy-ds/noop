import Foundation
import WhoopStore

// Exercises added to today's program from the Training screen (fork chantier 18, lot B « + Exercice »): the
// day card's « + Exercise » adds what the lifter wants to today's session without leaving the screen.
//
// FOR TODAY ONLY. The program is not touched: the additions are kept on the device for the day they were made,
// and the session that starts the program that day takes them in as lines added during the session
// (`LiftPlanItem.addedInSession`), so finishing asks, as it always does, whether the program keeps them. Every
// start of a program goes through `beginProgramSession`, which is where they are taken in, then cleared: they
// are the session's from then on. Another day's additions are never read.
//
// The same day list also holds the program's own lines LEFT OUT today (the day card's list of every exercise,
// « − » on a line): kept by the program line's id, they are skipped by the session that starts the program
// that day and forgotten with the additions. The program itself still has them.

struct LiftDayAddition: Codable, Equatable, Identifiable {
    var id: String
    var exercise: String
    var primaryMuscle: LiftMuscle?
    var secondaryMuscles: [LiftMuscle]
}

enum LiftDayAdditions {
    static let defaultsKey = "lift.dayAdditions.v1"
    /// Bumped by every change, so the Training screen reloads its day card.
    static let revisionKey = "lift.dayAdditions.revision"
    /// The most exercises one day may add to one program.
    static let maxPerProgram = 20
    /// The working sets an added exercise starts with when it was never done before.
    static let defaultSets = 3

    private struct Stored: Codable, Equatable {
        var day: String
        var programId: String
        var lines: [LiftDayAddition]
        /// The program's own lines left out today, by program line id. Optional, so a list written before
        /// it existed still reads.
        var removed: [String]?

        var isEmpty: Bool { lines.isEmpty && (removed ?? []).isEmpty }
    }

    /// The exercises added to `programId` on `day`, in the order they were added.
    static func additions(day: String, programId: String, defaults: UserDefaults = .standard) -> [LiftDayAddition] {
        stored(defaults).first { $0.day == day && $0.programId == programId }?.lines ?? []
    }

    /// Every program's additions for `day`, by program id.
    static func additionsByProgram(day: String, defaults: UserDefaults = .standard) -> [String: [LiftDayAddition]] {
        var out: [String: [LiftDayAddition]] = [:]
        for entry in stored(defaults) where entry.day == day && !entry.lines.isEmpty {
            out[entry.programId] = entry.lines
        }
        return out
    }

    /// The ids of `programId`'s own lines left out on `day`.
    static func removedLineIds(day: String, programId: String, defaults: UserDefaults = .standard) -> Set<String> {
        Set(stored(defaults).first { $0.day == day && $0.programId == programId }?.removed ?? [])
    }

    /// Every program's lines left out on `day`, by program id.
    static func removedLinesByProgram(day: String, defaults: UserDefaults = .standard) -> [String: Set<String>] {
        var out: [String: Set<String>] = [:]
        for entry in stored(defaults) where entry.day == day {
            let removed = Set(entry.removed ?? [])
            if !removed.isEmpty { out[entry.programId] = removed }
        }
        return out
    }

    /// Leave one of the program's own lines out of `day`'s session (`left` true), or put it back.
    static func setLineLeftOut(_ lineId: String, left: Bool, day: String, programId: String,
                               defaults: UserDefaults = .standard) {
        var all = stored(defaults).filter { $0.day == day }
        var entry = all.first { $0.programId == programId } ?? Stored(day: day, programId: programId, lines: [])
        var removed = entry.removed ?? []
        removed.removeAll { $0 == lineId }
        if left { removed.append(lineId) }
        entry.removed = removed
        all.removeAll { $0.programId == programId }
        all.append(entry)
        write(all, defaults)
    }

    /// Add one exercise to `programId` for `day`. False when that day's list is full.
    @discardableResult
    static func add(_ addition: LiftDayAddition, day: String, programId: String,
                    defaults: UserDefaults = .standard) -> Bool {
        var all = stored(defaults).filter { $0.day == day }
        var entry = all.first { $0.programId == programId } ?? Stored(day: day, programId: programId, lines: [])
        guard entry.lines.count < maxPerProgram else { return false }
        entry.lines.append(addition)
        all.removeAll { $0.programId == programId }
        all.append(entry)
        write(all, defaults)
        return true
    }

    /// Take one addition back out.
    static func remove(id: String, day: String, programId: String, defaults: UserDefaults = .standard) {
        let all = stored(defaults).filter { $0.day == day }.map { entry -> Stored in
            guard entry.programId == programId else { return entry }
            var kept = entry
            kept.lines.removeAll { $0.id == id }
            return kept
        }
        write(all, defaults)
    }

    /// The additions of `programId` for `day`, handed over and forgotten with the lines left out that day:
    /// the session that starts takes them.
    @discardableResult
    static func takeAdditions(day: String, programId: String, defaults: UserDefaults = .standard) -> [LiftDayAddition] {
        let all = stored(defaults)
        guard let entry = all.first(where: { $0.day == day && $0.programId == programId }) else { return [] }
        write(all.filter { $0.day == day && $0.programId != programId }, defaults)
        return entry.lines
    }

    /// The program's lines a session of `day` runs: all of them but the ones left out that day. Every line
    /// is kept when nothing would be left, so a start never runs an empty session.
    static func keptProgramLines(_ items: [LiftProgramItemRow], removed: Set<String>) -> [LiftProgramItemRow] {
        let kept = items.filter { !removed.contains($0.id) }
        return kept.isEmpty ? items : kept
    }

    /// An addition as a line of the session: added during the session (finishing asks whether the program
    /// keeps it), with the working sets the exercise had last time, else `defaultSets`. Its numbers are the
    /// grey ones every added line shows: last session's, when it was done before.
    static func planItem(_ addition: LiftDayAddition, lastSets: [LiftSetRow]) -> LiftPlanItem {
        let working = lastSets.filter { !$0.isWarmup }
        return LiftPlanItem(exercise: addition.exercise,
                            primaryMuscle: addition.primaryMuscle,
                            secondaryMuscles: addition.secondaryMuscles.filter { $0 != addition.primaryMuscle },
                            targetSets: working.isEmpty ? defaultSets : min(working.count, LiftSessionEngine.maxSetsPerExercise),
                            programItemId: addition.id,
                            addedInSession: true)
    }

    private static func stored(_ defaults: UserDefaults) -> [Stored] {
        guard let data = defaults.data(forKey: defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([Stored].self, from: data)) ?? []
    }

    private static func write(_ entries: [Stored], _ defaults: UserDefaults) {
        let kept = entries.filter { !$0.isEmpty }
        if kept.isEmpty {
            defaults.removeObject(forKey: defaultsKey)
        } else if let data = try? JSONEncoder().encode(kept) {
            defaults.set(data, forKey: defaultsKey)
        }
        defaults.set(defaults.integer(forKey: revisionKey) + 1, forKey: revisionKey)
    }
}
