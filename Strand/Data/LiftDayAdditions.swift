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

    /// Add one exercise to `programId` for `day`. False when that day's list is full.
    @discardableResult
    static func add(_ addition: LiftDayAddition, day: String, programId: String,
                    defaults: UserDefaults = .standard) -> Bool {
        var all = stored(defaults).filter { $0.day == day }
        var lines = all.first { $0.programId == programId }?.lines ?? []
        guard lines.count < maxPerProgram else { return false }
        lines.append(addition)
        all.removeAll { $0.programId == programId }
        all.append(Stored(day: day, programId: programId, lines: lines))
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

    /// The additions of `programId` for `day`, handed over and forgotten: the session that starts takes them.
    @discardableResult
    static func takeAdditions(day: String, programId: String, defaults: UserDefaults = .standard) -> [LiftDayAddition] {
        let lines = additions(day: day, programId: programId, defaults: defaults)
        guard !lines.isEmpty else { return [] }
        write(stored(defaults).filter { $0.day == day && $0.programId != programId }, defaults)
        return lines
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
        let kept = entries.filter { !$0.lines.isEmpty }
        if kept.isEmpty {
            defaults.removeObject(forKey: defaultsKey)
        } else if let data = try? JSONEncoder().encode(kept) {
            defaults.set(data, forKey: defaultsKey)
        }
        defaults.set(defaults.integer(forKey: revisionKey) + 1, forKey: revisionKey)
    }
}
