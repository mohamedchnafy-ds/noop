import Foundation
import WhoopStore
import StrandAnalytics

// The Lift Log, as the Coach reads it (personal fork).
//
// Until this existed a gym session reached the Coach only as a "Strength Training" workout row — its
// length, heart rate and effort — so it could not answer the questions a lifter actually asks: how did
// that session go, am I progressing, is my volume balanced, what should I aim for next time. This block
// gives it the sets themselves, summarised.
//
// SUMMARY, NOT A DUMP. Working sets as weight × reps per exercise, the best estimated 1RM per exercise
// per session, a weekly per-muscle set count, and the programs' targets. Warm-ups and sets discarded
// to zero (`LiftMetrics.isPerformed`) are left out, exactly as every Lift Log figure leaves them out.
// Everything is bounded (sessions, exercises, programs, lines), so a long history cannot blow up the
// prompt or its cost.
//
// PURE: the caller reads the store and hands the rows in, so the formatting is testable with no
// database (`CoachLiftContextTests`).

enum CoachLiftContext {

    /// How far back sessions are read. Long enough to show a progression trend over a few cycles of an
    /// A/B/C rotation, short enough to stay current.
    static let lookbackDays = 56
    /// Sessions shown set by set, newest first. Older ones still feed the progression line.
    static let detailedSessions = 6
    static let maxExercisesPerSession = 12
    static let maxPrograms = 6
    static let maxLinesPerProgram = 16
    /// Points kept per exercise in the progression line.
    static let maxProgressPoints = 6

    /// One session with its sets, as the store holds them.
    struct Session {
        var row: LiftSessionRow
        var sets: [LiftSetRow]
    }

    /// One program with its lines.
    struct Program {
        var row: LiftProgramRow
        var items: [LiftProgramItemRow]
    }

    /// The whole block, or "" when the Lift Log holds nothing at all — no session and no program — so
    /// a user who never lifts gets no empty heading in their prompt.
    static func summary(sessions: [Session], programs: [Program], now: Int,
                        system: UnitSystem = .metric) -> String {
        let performed = sessions
            .map { Session(row: $0.row, sets: $0.sets.filter(isWorking)) }
            .filter { !$0.sets.isEmpty }
            .sorted { $0.row.startTs > $1.row.startTs }     // newest first
        guard !performed.isEmpty || !programs.isEmpty else { return "" }

        let unit = LiftFormat.weightUnit(system)
        var lines: [String] = [
            "LIFT LOG (strength training the user logged set by set in NOOP; weights in \(unit)):",
            "How to use it: working sets are written weight×reps; warm-ups are excluded. e1RM is the Epley "
                + "estimated one-rep max of the best set (sets of 12 reps or fewer). For progression, compare "
                + "e1RM and the weight×reps of the same exercise across sessions. For the next session, apply "
                + "double progression: when every working set reached the planned reps at or under the max "
                + "RPE, suggest a small load increase (about 2.5 \(unit) for upper body, 5 \(unit) for lower "
                + "body) or one more rep; when sets fell short, keep the load. Lines tagged A1, A2… are a "
                + "superset: one set of each in turn, with the rest only after the last.",
        ]

        // 1. The latest sessions, set by set.
        if performed.isEmpty {
            lines.append("")
            lines.append("No strength session logged in the last \(lookbackDays) days.")
        } else {
            lines.append("")
            lines.append("Sessions (newest first):")
            for session in performed.prefix(detailedSessions) {
                lines.append("  " + sessionHeader(session.row))
                for line in exerciseLines(session.sets, system: system) {
                    lines.append("    " + line)
                }
            }
        }

        // 2. Weekly volume per muscle, against the research bands the Lift Log screen shows.
        let weekAgo = now - 7 * 86_400
        let lastWeek = performed.filter { $0.row.startTs >= weekAgo }.flatMap(\.sets)
        let counts = LiftMetrics.muscleCounts(lastWeek).fractional
            .filter { $0.value > 0 }
            .sorted { $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value }
        if !counts.isEmpty {
            lines.append("")
            lines.append("Working sets per muscle, last 7 days (a secondary muscle counts half). Research "
                         + "bands: about \(trim(LiftMetrics.ReferenceDose.hypertrophyMinimumSetsPerWeek)) "
                         + "sets/week is the least reliably linked to growth, more keeps helping with "
                         + "diminishing returns; strength improves from "
                         + "\(trim(LiftMetrics.ReferenceDose.strengthMinimumSetsPerWeek)) set/week and "
                         + "plateaus near \(trim(LiftMetrics.ReferenceDose.strengthPlateauSetsPerWeek)):")
            lines.append("  " + counts.map { "\(muscleName($0.key)) \(trim($0.value))" }.joined(separator: ", "))
        }

        // 3. Progression: best e1RM per exercise per session, oldest → newest.
        let progress = progressionLines(performed, system: system)
        if !progress.isEmpty {
            lines.append("")
            lines.append("Progression (best e1RM per session, oldest → newest, last \(lookbackDays) days):")
            lines.append(contentsOf: progress.map { "  " + $0 })
        }

        // 4. The programs and their targets — what "next session" means.
        let withItems = programs.filter { !$0.items.isEmpty }
        if !withItems.isEmpty {
            let lastDone = LiftRotation.lastDone(performed.map { (programId: $0.row.programId, startTs: $0.row.startTs) })
            lines.append("")
            lines.append("Programs (planned targets; the rest is per set, in seconds):")
            for program in withItems.prefix(maxPrograms) {
                let done = lastDone[program.row.id].map { "last done \(day($0))" } ?? "not done recently"
                lines.append("  \(program.row.name) (\(done)):")
                let labels = program.items.map(\.supersetGroup)
                for (i, item) in program.items.prefix(maxLinesPerProgram).enumerated() {
                    lines.append("    " + programLine(item, tag: LiftSuperset.tag(of: i, in: labels),
                                                      isSupersetLast: isLastOfSuperset(i, labels),
                                                      inSuperset: LiftSuperset.group(of: i, in: labels) != nil,
                                                      system: system))
                }
            }
            // A rotation's next day is the one done least recently; a program never done comes first.
            // `LiftRotation` owns the rule, so the Today synthesis names the same program.
            if withItems.count > 1,
               let nextId = LiftRotation.next(programIds: withItems.map(\.row.id), lastDone: lastDone),
               let next = withItems.first(where: { $0.row.id == nextId }) {
                lines.append("  Likely next in the rotation (done least recently): \(next.row.name)")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Pieces

    private static func isWorking(_ set: LiftSetRow) -> Bool {
        LiftRotation.isWorking(set)
    }

    /// `2026-10-30 Superset A, 52 min, session RPE 7`
    private static func sessionHeader(_ s: LiftSessionRow) -> String {
        var parts = [day(s.startTs) + " " + (s.programName ?? "Freehand session")]
        if let end = s.endTs, end > s.startTs { parts.append("\(Int((Double(end - s.startTs) / 60).rounded())) min") }
        if let rpe = s.sessionRpe { parts.append("session RPE \(trim(rpe))") }
        return parts.joined(separator: ", ") + ":"
    }

    /// One line per exercise in the order first performed:
    /// `Curl (biceps): 12×10, 12×10, 12×9 · RPE 8 · e1RM 15.6`
    static func exerciseLines(_ sets: [LiftSetRow], system: UnitSystem) -> [String] {
        let ordered = sets.sorted { $0.ord < $1.ord }
        var names: [String] = []
        for set in ordered where !names.contains(set.exercise) { names.append(set.exercise) }
        let summaries = Dictionary(LiftMetrics.perExercise(ordered).map { ($0.exercise, $0) },
                                   uniquingKeysWith: { first, _ in first })
        return names.prefix(maxExercisesPerSession).map { name in
            let mine = ordered.filter { $0.exercise == name }
            let muscle = mine.first?.primaryMuscle.map { " (\(muscleName($0)))" } ?? ""
            var parts = [mine.map { setText($0, system: system) }.joined(separator: ", ")]
            let rated = mine.compactMap(\.rpe)
            if !rated.isEmpty {
                parts.append("RPE " + trim((rated.reduce(0, +) / Double(rated.count) * 10).rounded() / 10))
            }
            if let e1rm = summaries[name]?.bestEstimatedOneRepMaxKg {
                parts.append("e1RM " + weight(e1rm, system: system))
            }
            return "\(name)\(muscle): " + parts.joined(separator: " · ")
        }
    }

    /// `12×10`, `×12` for a bodyweight set with no load typed.
    private static func setText(_ set: LiftSetRow, system: UnitSystem) -> String {
        let w = set.weightKg.map { weight($0, system: system) } ?? ""
        return "\(w)×\(set.reps ?? 0)"
    }

    /// `Curl: 14 → 15.2 → 15.6 (+11%)` for every exercise done in at least two sessions.
    static func progressionLines(_ sessions: [Session], system: UnitSystem) -> [String] {
        var series: [String: [Double]] = [:]
        var order: [String] = []
        for session in sessions.sorted(by: { $0.row.startTs < $1.row.startTs }) {   // oldest first
            for summary in LiftMetrics.perExercise(session.sets) {
                guard let e1rm = summary.bestEstimatedOneRepMaxKg else { continue }
                if series[summary.exercise] == nil { order.append(summary.exercise) }
                series[summary.exercise, default: []].append(e1rm)
            }
        }
        return order.compactMap { name in
            guard let points = series[name], points.count >= 2,
                  let first = points.first, let last = points.last, first > 0 else { return nil }
            let shown = points.suffix(maxProgressPoints).map { weight($0, system: system) }
            let change = Int(((last - first) / first * 100).rounded())
            return "\(name): " + shown.joined(separator: " → ") + " (\(change >= 0 ? "+" : "")\(change)%)"
        }
    }

    /// `A1 Curl: 3×10 @ 12, max RPE 8, no rest before A2` /
    /// `A2 Extension: 3×12 @ 20, rest 125 after the round`
    private static func programLine(_ item: LiftProgramItemRow, tag: String?, isSupersetLast: Bool,
                                    inSuperset: Bool, system: UnitSystem) -> String {
        var parts: [String] = []
        let sets = item.targetSets ?? 1
        if let reps = item.targetRepsLow {
            let high = item.targetRepsHigh.map { $0 > reps ? "-\($0)" : "" } ?? ""
            parts.append("\(sets)×\(reps)\(high)")
        } else {
            parts.append("\(sets) sets")
        }
        if let kg = item.targetWeightKg { parts[0] += " @ " + weight(kg, system: system) }
        if let rpe = item.targetRpe { parts.append("max RPE \(trim(rpe))") }
        if inSuperset {
            parts.append(isSupersetLast
                         ? "rest \(item.restSec ?? LiftPlanItem.defaultRestSec) after the round"
                         : "no rest, straight to the next exercise")
        } else if let rest = item.restSec {
            parts.append("rest \(rest)")
        }
        return (tag.map { "\($0) " } ?? "") + "\(item.exercise): " + parts.joined(separator: ", ")
    }

    private static func isLastOfSuperset(_ index: Int, _ labels: [String?]) -> Bool {
        LiftSuperset.group(of: index, in: labels)?.last == index
    }

    // MARK: - Formatting

    static func weight(_ kg: Double, system: UnitSystem) -> String {
        LiftFormat.trim((LiftFormat.display(fromKilograms: kg, system: system) * 10).rounded() / 10)
    }

    private static func trim(_ value: Double) -> String { LiftFormat.trim(value) }

    /// "frontDelts" → "front delts": the stored token, readable, and the same in every app language.
    static func muscleName(_ muscle: LiftMuscle) -> String {
        var out = ""
        for ch in muscle.rawValue {
            if ch.isUppercase { out += " " + ch.lowercased() } else { out.append(ch) }
        }
        return out
    }

    private static func day(_ ts: Int) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }
}
