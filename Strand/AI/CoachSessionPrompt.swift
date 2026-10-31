import Foundation
import StrandAnalytics
import WhoopStore

// MARK: - "Analyse my session" (personal fork)
//
// The question the finish sheet hands to the Coach once a session is saved: the session set by set,
// then a localised ask. The Coach's context already carries the Lift Log, so the prompt repeats only
// what it is about — the session just filed — so the reply is about THIS one.

enum CoachSessionPrompt {
    /// - Parameters:
    ///   - sets: the session's sets in completion order (what `LiftSessionView.save` filed).
    ///   - exerciseName: how to name a set's exercise (the plan line's name).
    static func prompt(programName: String?, startTs: Int, endTs: Int, sessionRpe: Double?,
                       sets: [LiftSetRow], system: UnitSystem) -> String {
        let unit = LiftFormat.weightUnit(system)
        var lines: [String] = []
        var header = [programName ?? String(localized: "Freehand session")]
        if endTs > startTs { header.append("\(Int((Double(endTs - startTs) / 60).rounded())) min") }
        if let rpe = sessionRpe { header.append("RPE \(LiftFormat.trim(rpe))") }
        lines.append(header.joined(separator: ", "))

        // Working sets grouped by exercise, in the order the exercises were first done.
        var order: [String] = []
        var byExercise: [String: [LiftSetRow]] = [:]
        for set in sets where !set.isWarmup && LiftMetrics.isPerformed(reps: set.reps) {
            if byExercise[set.exercise] == nil { order.append(set.exercise) }
            byExercise[set.exercise, default: []].append(set)
        }
        for exercise in order {
            let parts = (byExercise[exercise] ?? []).map { set -> String in
                var s = ""
                if let kg = set.weightKg { s += LiftFormat.trim(LiftFormat.display(fromKilograms: kg, system: system)) }
                if let reps = set.reps { s += (s.isEmpty ? "" : "×") + "\(reps)" }
                if let rpe = set.rpe { s += " @\(LiftFormat.trim(rpe))" }
                return s
            }
            lines.append("- \(exercise): " + parts.joined(separator: ", ") + " (\(unit))")
        }

        let ask = String(localized: "Analyse the strength session I just finished (above): what went well, what to change next time, and which loads to raise or hold.")
        return lines.joined(separator: "\n") + "\n\n" + ask
    }
}
