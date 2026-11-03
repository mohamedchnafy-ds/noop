import Foundation
import WhoopStore

/// A change to the user's own records that the Coach proposes as a card (personal fork, chantier 8): a nap
/// they mention, a correction to a workout entered by hand, a correction to the sets of a finished Lift Log
/// session, or a lasting fact to remember. The card shows what would change; nothing is written until
/// "Confirm" is tapped, and "Undo" puts back what was there. The proposal travels with the reply
/// (`CoachReplyMeta.action`), like the session and meal cards.
///
/// PURE: the tool input is read and bounded here against rows the engine fetched, and every line the card
/// shows is written here by the app, so the rules are tested without a store. A correction is the user's
/// declaration, never a measurement: the card says so, and the engine logs each Confirm and Undo
/// (`AICoachEngine.coachActionLog`).
struct CoachActionProposal: Codable, Equatable {

    enum Kind: String, Codable, CaseIterable {
        case nap, workout, liftSets, remember

        /// The tool that proposes this kind of card.
        var toolName: String {
            switch self {
            case .nap: return "log_nap"
            case .workout: return "correct_workout"
            case .liftSets: return "correct_lift_session"
            case .remember: return "remember"
            }
        }

        init?(toolName: String) {
            guard let kind = Kind.allCases.first(where: { $0.toolName == toolName }) else { return nil }
            self = kind
        }

        /// Whether the tool needs "Use my data": a correction names a record it has read.
        var readsData: Bool { self == .workout || self == .liftSets }
    }

    enum State: String, Codable {
        case proposed, applied, undone
    }

    struct Nap: Codable, Equatable {
        var startTs: Int
        var endTs: Int
    }

    struct WorkoutFix: Codable, Equatable {
        var before: WorkoutRow
        var after: WorkoutRow
    }

    struct LiftFix: Codable, Equatable {
        var sessionId: String
        var sessionStartTs: Int
        var programName: String?
        /// The session's rows as they were, put back by Undo.
        var before: [LiftSetRow]
        /// The rows Confirm writes: changed and added.
        var upserts: [LiftSetRow]
        /// The rows Confirm removes.
        var deletedIds: [String]
    }

    struct Fact: Codable, Equatable {
        var text: String
        /// True for a pain, an injury or a constraint ("pain or constraints"), false for anything else.
        var isConstraint: Bool
    }

    var kind: Kind
    /// What the card lists, written by the app in the user's language when the card is made.
    var lines: [String]
    var nap: Nap?
    var workout: WorkoutFix?
    var lift: LiftFix?
    var fact: Fact?
    var state: State = .proposed
    /// Unix seconds of the Confirm tap.
    var appliedAt: Int?

    // MARK: Limits

    static let napMinutes = 10...240
    static let maxDaysBack = 7
    static let maxChanges = 30
    static let weightKgRange = 0.0...500.0
    static let repsRange = 0...100
    static let maxFactCharacters = 300

    // MARK: The tools

    static var napDefinition: [String: Any] {
        cardDefinition(.nap,
                   "Show the user a nap they told you about as a card with “Confirm”. Nothing is saved until they "
                   + "tap, and they can undo it. Use the times they gave; never invent a nap.",
                   properties: [
                    "date": ["type": "string", "description": "YYYY-MM-DD; leave out for today."],
                    "start": ["type": "string", "description": "HH:MM, when the nap started."],
                    "end": ["type": "string", "description": "HH:MM, when it ended."],
                   ],
                   required: ["start", "end"])
    }

    static var workoutDefinition: [String: Any] {
        cardDefinition(.workout,
                   "Show the user a correction to a workout they entered by hand (marked “entered by hand” in "
                   + "get_workouts) as a card with “Confirm”; nothing changes until they tap, and they can undo it. "
                   + "Name the workout by its date and start time as get_workouts lists them, then give only the "
                   + "fields to change. A workout recorded by the strap or imported cannot be corrected here.",
                   properties: [
                    "date": ["type": "string", "description": "YYYY-MM-DD of the workout."],
                    "start": ["type": "string", "description": "HH:MM, its start as get_workouts lists it."],
                    "sport": ["type": "string", "description": "Its sport as get_workouts lists it."],
                    "new_sport": ["type": "string"],
                    "new_start": ["type": "string", "description": "HH:MM, same day."],
                    "new_end": ["type": "string", "description": "HH:MM, same day."],
                    "duration_min": ["type": "integer", "minimum": 1, "maximum": 600],
                    "distance_km": ["type": "number", "minimum": 0, "maximum": 1000],
                    "avg_hr": ["type": "integer", "minimum": 30, "maximum": 250],
                    "calories": ["type": "integer", "minimum": 0, "maximum": 10000],
                   ],
                   required: ["date", "start"])
    }

    static var liftDefinition: [String: Any] {
        let change: [String: Any] = [
            "type": "object",
            "properties": [
                "exercise": ["type": "string", "description": "As the Lift Log names it in that session."],
                "set": ["type": "integer", "minimum": 1,
                        "description": "The set number within the exercise; leave out to add a set."],
                "weight": ["type": "number", "description": "In the unit get_exercise_history uses."],
                "reps": ["type": "integer", "minimum": repsRange.lowerBound, "maximum": repsRange.upperBound],
                "remove": ["type": "boolean", "description": "True to remove that set."],
            ] as [String: Any],
            "required": ["exercise"],
        ]
        return cardDefinition(.liftSets,
                          "Show the user a correction to the sets of a finished Lift Log session (a weight or reps "
                          + "mistyped, a set added or removed) as a card with “Confirm”; nothing changes until they tap, "
                          + "and they can undo it. Only that session changes, never its program.",
                          properties: [
                            "date": ["type": "string", "description": "YYYY-MM-DD of the session."],
                            "program": ["type": "string", "description": "Its program, when that day had two sessions."],
                            "changes": ["type": "array", "items": change, "minItems": 1, "maxItems": maxChanges],
                          ],
                          required: ["date", "changes"])
    }

    static var rememberDefinition: [String: Any] {
        cardDefinition(.remember,
                   "When the user states a lasting fact the coach should keep for later conversations (an injury, "
                   + "a pain, a schedule, equipment, a preference), show it as a card that adds it to “What the coach "
                   + "should know about you” on “Confirm”. One short sentence in the user's language. Never for "
                   + "something that only matters today.",
                   properties: [
                    "fact": ["type": "string", "description": "One sentence, at most \(maxFactCharacters) characters."],
                    "kind": ["type": "string", "enum": ["constraint", "other"],
                             "description": "constraint for a pain, an injury or a limit; other for the rest."],
                   ],
                   required: ["fact", "kind"])
    }

    private static func cardDefinition(_ kind: Kind, _ description: String, properties: [String: Any],
                                   required: [String]) -> [String: Any] {
        ["name": kind.toolName,
         "description": description,
         "input_schema": ["type": "object", "properties": properties, "required": required] as [String: Any]]
    }

    /// What the model is told once the card is shown.
    static let shownResult = "Shown to the user as a card with “Confirm”. Nothing is saved until they tap, and they "
        + "can undo it. Do not repeat the card and add nothing after it."

    // MARK: Reading the input

    /// A problem the model can act on, or the card.
    typealias Parsed = (proposal: CoachActionProposal?, problem: String?)

    /// `log_nap`: the day (today when left out, at most `maxDaysBack` back), a start and an end on that day,
    /// `napMinutes` long, ended by `now`.
    static func nap(from input: [String: Any], now: Date, calendar: Calendar = .current) -> Parsed {
        guard let day = actionDay(input["date"] as? String, now: now, calendar: calendar) else {
            return (nil, "Give the date as YYYY-MM-DD, today or in the last \(maxDaysBack) days.")
        }
        guard let start = actionTime(input["start"] as? String, on: day, calendar: calendar),
              let end = actionTime(input["end"] as? String, on: day, calendar: calendar) else {
            return (nil, "Give the start and the end as HH:MM.")
        }
        let minutes = Int(end.timeIntervalSince(start) / 60)
        guard napMinutes.contains(minutes) else {
            return (nil, "A nap lasts \(napMinutes.lowerBound) to \(napMinutes.upperBound) minutes, on one day.")
        }
        guard end <= now.addingTimeInterval(300) else { return (nil, "That nap has not ended yet.") }
        let startTs = Int(start.timeIntervalSince1970), endTs = Int(end.timeIntervalSince1970)
        let lines = [dayLine(day, now: now, calendar: calendar),
                     "\(actionClock(start, calendar)) – \(actionClock(end, calendar)) · " + SleepDurationText.format(Double(minutes))]
        return (CoachActionProposal(kind: .nap, lines: lines, nap: Nap(startTs: startTs, endTs: endTs)), nil)
    }

    /// `correct_workout`: the one hand-entered workout at that date and start (and sport, when given), with
    /// the fields to change applied through the Workouts sheet's own rules (`WorkoutSource`).
    static func workoutFix(from input: [String: Any], rows: [WorkoutRow], now: Date, calendar: Calendar = .current,
                           distance: (Double) -> String) -> Parsed {
        guard let dayText = input["date"] as? String,
              let day = actionDay(dayText, now: now, calendar: calendar, maxBack: 60),
              let asked = actionTime(input["start"] as? String, on: day, calendar: calendar) else {
            return (nil, "Name the workout by its date (YYYY-MM-DD) and start (HH:MM) as get_workouts lists them.")
        }
        let askedTs = Int(asked.timeIntervalSince1970)
        let sport = actionText(input, "sport")
        let matches = rows.filter { row in
            abs(row.startTs - askedTs) < 60
                && (sport.map { CoachTools.sameExercise(WorkoutSource.displaySport(row.sport), $0)
                                || CoachTools.sameExercise(row.sport, $0) } ?? true)
        }
        guard matches.count == 1, let old = matches.first else {
            return (nil, matches.isEmpty ? "No workout starts at that time that day: check get_workouts."
                                         : "Several workouts start then: give the sport too.")
        }
        guard WorkoutSource.classify(old.source) == .manual else {
            return (nil, "That workout was recorded by the strap or imported, so it cannot be corrected here. "
                    + "The user can edit it in Workouts.")
        }
        let oldStart = Date(timeIntervalSince1970: TimeInterval(old.startTs))
        let start: Date
        if let raw = input["new_start"] as? String {
            guard let parsed = actionTime(raw, on: day, calendar: calendar) else { return (nil, "Give new_start as HH:MM.") }
            start = parsed
        } else {
            start = oldStart
        }
        var end = Date(timeIntervalSince1970: TimeInterval(old.endTs)).addingTimeInterval(start.timeIntervalSince(oldStart))
        if input["new_start"] == nil { end = Date(timeIntervalSince1970: TimeInterval(old.endTs)) }
        if let raw = input["new_end"] as? String {
            guard let parsed = actionTime(raw, on: day, calendar: calendar) else { return (nil, "Give new_end as HH:MM.") }
            end = parsed
        } else if let minutes = actionNumber(input, "duration_min") {
            end = start.addingTimeInterval(min(max(minutes, 1), 600) * 60)
        }
        let newSport = actionText(input, "new_sport") ?? old.sport
        let avgHr = actionNumber(input, "avg_hr").map { Int(min(max($0, 30), 250).rounded()) } ?? old.avgHr
        let kcal = actionNumber(input, "calories").map { min(max($0, 0), 10_000) } ?? old.energyKcal
        let meters = actionNumber(input, "distance_km").map { (min(max($0, 0), 1000) * 1000).rounded() } ?? old.distanceM
        guard let base = WorkoutSource.buildManualRowFromSpan(start: start, end: end, sport: newSport, avgHr: avgHr,
                                                              energyKcal: kcal, distanceM: meters, now: now) else {
            return (nil, "That correction is not a valid workout: the end must be after the start and not in the future.")
        }
        let new = WorkoutSource.preservingCaptured(base, from: old)
        var lines: [String] = [dayLine(day, now: now, calendar: calendar) + " · " + WorkoutSource.displaySport(old.sport)]
        if new.sport != old.sport {
            lines.append(String(localized: "Sport") + ": " + WorkoutSource.displaySport(old.sport) + " → "
                         + WorkoutSource.displaySport(new.sport))
        }
        if new.startTs != old.startTs || new.endTs != old.endTs {
            lines.append(String(localized: "Time") + ": " + span(old, calendar) + " → " + span(new, calendar))
        }
        if new.distanceM != old.distanceM {
            lines.append(String(localized: "Distance") + ": " + (old.distanceM.map(distance) ?? "—") + " → "
                         + (new.distanceM.map(distance) ?? "—"))
        }
        if new.avgHr != old.avgHr {
            lines.append(String(localized: "Avg HR") + ": " + (old.avgHr.map { "\($0)" } ?? "—") + " → "
                         + (new.avgHr.map { "\($0)" } ?? "—"))
        }
        if new.energyKcal != old.energyKcal {
            lines.append(String(localized: "Calories") + ": " + (old.energyKcal.map { "\(Int($0.rounded()))" } ?? "—")
                         + " → " + (new.energyKcal.map { "\(Int($0.rounded()))" } ?? "—"))
        }
        guard lines.count > 1 else { return (nil, "That changes nothing in the workout.") }
        return (CoachActionProposal(kind: .workout, lines: lines, workout: WorkoutFix(before: old, after: new)), nil)
    }

    /// One finished Lift Log session with its sets, as `correct_lift_session` reads it.
    struct LiftSession {
        var row: LiftSessionRow
        var sets: [LiftSetRow]
    }

    /// `correct_lift_session`: the finished session of that date (and program), with each change applied in
    /// order. Sets are numbered 1… per exercise in set order, as the session's edit sheet numbers them, and
    /// renumbered after a removal; an added set copies the exercise's muscles and goes after every set.
    static func liftFix(from input: [String: Any], sessions: [LiftSession], system: UnitSystem, now: Date,
                        calendar: Calendar = .current, newId: () -> String = { UUID().uuidString }) -> Parsed {
        guard let dayText = input["date"] as? String,
              let day = actionDay(dayText, now: now, calendar: calendar, maxBack: 365) else {
            return (nil, "Give the session's date as YYYY-MM-DD.")
        }
        let program = actionText(input, "program")
        let onDay = sessions.filter {
            $0.row.endTs != nil
                && calendar.isDate(Date(timeIntervalSince1970: TimeInterval($0.row.startTs)), inSameDayAs: day)
        }
        let matching = program.map { name in onDay.filter { CoachTools.sameExercise($0.row.programName ?? "", name) } } ?? onDay
        guard matching.count == 1, let session = matching.first else {
            if matching.isEmpty { return (nil, "No finished Lift Log session that day.") }
            return (nil, "Several sessions that day: give the program.")
        }
        guard let changes = input["changes"] as? [[String: Any]], !changes.isEmpty else {
            return (nil, "Give at least one change.")
        }
        guard changes.count <= maxChanges else { return (nil, "At most \(maxChanges) changes at once.") }

        let unit = LiftFormat.weightUnit(system)
        func setText(_ kg: Double?, _ reps: Int?) -> String {
            let weight = kg.map { LiftFormat.trim(LiftFormat.display(fromKilograms: $0, system: system)) + " " + unit }
            switch (weight, reps) {
            case let (w?, r?): return "\(w) × \(r)"
            case let (w?, nil): return w
            case let (nil, r?): return "× \(r)"
            case (nil, nil): return "—"
            }
        }
        var rows = session.sets.sorted { $0.ord < $1.ord }
        var lines: [String] = [dayLine(day, now: now, calendar: calendar)
                               + (session.row.programName.map { " · " + $0 } ?? "")]
        var nextOrd = (rows.map(\.ord).max() ?? -1) + 1
        for change in changes {
            guard let name = actionText(change, "exercise"),
                  let exercise = rows.first(where: { CoachTools.sameExercise($0.exercise, name) })?.exercise else {
                var known: [String] = []
                for row in rows where !known.contains(row.exercise) { known.append(row.exercise) }
                return (nil, "That session has no such exercise. Its exercises: " + known.joined(separator: ", ") + ".")
            }
            var weightKg: Double?
            if let w = actionNumber(change, "weight") {
                let kg = LiftFormat.kilograms(fromDisplay: w, system: system)
                guard weightKgRange.contains(kg) else { return (nil, "A weight must be between 0 and 500 kg.") }
                weightKg = kg
            }
            var reps: Int?
            if let r = actionNumber(change, "reps") {
                guard repsRange.contains(Int(r.rounded())) else { return (nil, "Reps must be between 0 and 100.") }
                reps = Int(r.rounded())
            }
            let ofExercise = rows.enumerated().filter { $0.element.exercise == exercise }
                .sorted { $0.element.setIndex < $1.element.setIndex }
            if let setNumber = actionNumber(change, "set").map({ Int($0.rounded()) }) {
                guard setNumber >= 1, setNumber <= ofExercise.count else {
                    return (nil, "\(exercise) has \(ofExercise.count) set(s) in that session.")
                }
                let index = ofExercise[setNumber - 1].offset
                let old = rows[index]
                if change["remove"] as? Bool == true {
                    rows.remove(at: index)
                    lines.append(String(localized: "\(exercise), set \(setNumber) removed (\(setText(old.weightKg, old.reps)))"))
                    continue
                }
                guard weightKg != nil || reps != nil else { return (nil, "Give a weight or reps for \(exercise) set \(setNumber).") }
                if let weightKg { rows[index].weightKg = weightKg }
                if let reps { rows[index].reps = reps }
                lines.append(String(localized: "\(exercise), set \(setNumber): \(setText(old.weightKg, old.reps)) → \(setText(rows[index].weightKg, rows[index].reps))"))
            } else {
                guard let reps else { return (nil, "An added set needs its reps.") }
                guard let template = ofExercise.last?.element else { continue }
                rows.append(LiftSetRow(id: newId(), deviceId: template.deviceId, sessionId: template.sessionId,
                                       ord: nextOrd, exercise: exercise, primaryMuscle: template.primaryMuscle,
                                       secondaryMuscles: template.secondaryMuscles, setIndex: ofExercise.count + 1,
                                       weightKg: weightKg ?? template.weightKg, reps: reps, rpe: nil, isWarmup: false,
                                       startTs: nil, endTs: nil, restSec: nil, note: nil))
                nextOrd += 1
                lines.append(String(localized: "\(exercise), set \(ofExercise.count + 1) added: \(setText(weightKg ?? template.weightKg, reps))"))
            }
        }
        // Renumber each exercise 1… in set order, as the edit sheet does after a removal.
        var position: [String: Int] = [:]
        for index in rows.indices.sorted(by: { (rows[$0].setIndex, rows[$0].ord) < (rows[$1].setIndex, rows[$1].ord) }) {
            let next = (position[rows[index].exercise] ?? 0) + 1
            position[rows[index].exercise] = next
            rows[index].setIndex = next
        }
        let before = Dictionary(uniqueKeysWithValues: session.sets.map { ($0.id, $0) })
        let upserts = rows.filter { before[$0.id] != $0 }
        let kept = Set(rows.map(\.id))
        let deleted = session.sets.map(\.id).filter { !kept.contains($0) }
        guard !upserts.isEmpty || !deleted.isEmpty else { return (nil, "That changes nothing in the session.") }
        let fix = LiftFix(sessionId: session.row.id, sessionStartTs: session.row.startTs,
                          programName: session.row.programName, before: session.sets, upserts: upserts,
                          deletedIds: deleted)
        return (CoachActionProposal(kind: .liftSets, lines: lines, lift: fix), nil)
    }

    /// `remember`: one sentence, not already in what the user told the coach.
    static func rememberCard(from input: [String: Any], profile: CoachProfile) -> Parsed {
        guard let raw = actionText(input, "fact") else { return (nil, "Give the fact in one sentence.") }
        let fact = CoachProfile.clean(raw)
        guard fact.count <= maxFactCharacters else { return (nil, "Keep it under \(maxFactCharacters) characters.") }
        let isConstraint = (input["kind"] as? String) == "constraint"
        let existing = isConstraint ? profile.constraints : profile.other
        guard !existing.localizedCaseInsensitiveContains(fact) else {
            return (nil, "Already in what the user told the coach.")
        }
        return (CoachActionProposal(kind: .remember, lines: [fact], fact: Fact(text: fact, isConstraint: isConstraint)), nil)
    }

    // MARK: Applying a fact

    /// The profile with the fact added on its own line of the matching field.
    static func profileAdding(_ fact: Fact, to profile: CoachProfile) -> CoachProfile {
        var next = profile
        if fact.isConstraint {
            next.constraints = joinedLine(next.constraints, fact.text)
        } else {
            next.other = joinedLine(next.other, fact.text)
        }
        return next
    }

    /// The profile with the fact's line taken out again (Undo); unchanged when the user already removed it.
    static func profileRemoving(_ fact: Fact, from profile: CoachProfile) -> CoachProfile {
        var next = profile
        func without(_ field: String) -> String {
            field.split(whereSeparator: \.isNewline)
                .filter { $0.trimmingCharacters(in: .whitespaces) != fact.text }
                .joined(separator: "\n")
        }
        if fact.isConstraint { next.constraints = without(next.constraints) } else { next.other = without(next.other) }
        return next
    }

    private static func joinedLine(_ field: String, _ line: String) -> String {
        let trimmed = field.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? line : trimmed + "\n" + line
    }

    // MARK: Read back by the model

    /// The card as the model reads it in a later turn, so "undo that" or "make it 40 minutes" knows what it was.
    func wireText() -> String {
        let status: String
        switch state {
        case .proposed: status = "not confirmed yet"
        case .applied: status = "confirmed by the user"
        case .undone: status = "confirmed, then undone by the user"
        }
        return "[\(kind.toolName) card, \(status): " + lines.joined(separator: "; ") + "]"
    }

    // MARK: Helpers

    private static func actionText(_ input: [String: Any], _ key: String) -> String? {
        guard let value = (input[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private static func actionNumber(_ input: [String: Any], _ key: String) -> Double? {
        if let n = input[key] as? NSNumber { return n.doubleValue }
        if let s = input[key] as? String { return Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) }
        return nil
    }

    /// The local midnight of `text` (today when nil), not after today and at most `maxBack` days back.
    static func actionDay(_ text: String?, now: Date, calendar: Calendar, maxBack: Int = maxDaysBack) -> Date? {
        let today = calendar.startOfDay(for: now)
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return today }
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return nil }
        let back = calendar.dateComponents([.day], from: date, to: today).day ?? 0
        return (0...maxBack).contains(back) ? date : nil
    }

    /// "HH:MM" on `day`, in `calendar`'s time zone.
    static func actionTime(_ text: String?, on day: Date, calendar: Calendar) -> Date? {
        guard let parts = text?.trimmingCharacters(in: .whitespaces).split(separator: ":").compactMap({ Int($0) }),
              parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
    }

    private static func actionClock(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private static func span(_ row: WorkoutRow, _ calendar: Calendar) -> String {
        actionClock(Date(timeIntervalSince1970: TimeInterval(row.startTs)), calendar) + "–"
            + actionClock(Date(timeIntervalSince1970: TimeInterval(row.endTs)), calendar)
    }

    /// "Today", "Yesterday", or the day as "Mon 2 Nov".
    private static func dayLine(_ day: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return String(localized: "Today") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
           calendar.isDate(day, inSameDayAs: yesterday) { return String(localized: "Yesterday") }
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
        style.timeZone = calendar.timeZone
        return day.formatted(style)
    }
}
