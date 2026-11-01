import Foundation
import WhoopStore

/// A session the Coach proposes as a card (personal fork, step 6b): what `create_program` sends, read
/// and bounded here, then shown with "Add to Lift Log" and "Start". Nothing is stored until one of
/// those is tapped; the proposal itself travels with the reply (`CoachReplyMeta.session`).
///
/// Supersets follow the Lift Log's own rule (`LiftSuperset`): consecutive lines with the same label
/// are one superset, and its rest is the one planned on its last line.
struct CoachSessionProposal: Codable, Equatable {

    struct Line: Codable, Equatable {
        var exercise: String
        var sets: Int
        var repsLow: Int?
        var repsHigh: Int?
        var weightKg: Double?
        var restSec: Int?
        var superset: String?
        var note: String?
    }

    var name: String
    /// The coach's estimate of the session's length, in minutes.
    var minutes: Int?
    var lines: [Line]
    /// The Lift Log program it was added as, once "Add to Lift Log" was tapped.
    var programId: String?

    static let toolName = "create_program"
    static let maxLines = 20
    static let setRange = 1...10
    static let repRange = 1...50
    static let restRange = 0...600
    static let minuteRange = 5...240
    static let maxWeightKg = 500.0

    // MARK: The tool

    /// The `create_program` definition. Sent with every tool question, with or without data access:
    /// a session needs no figure to be written, and nothing is saved by the call.
    static var definition: [String: Any] {
        let line: [String: Any] = [
            "type": "object",
            "properties": [
                "exercise": ["type": "string", "description": "The Lift Log's own name when the exercise is there."],
                "sets": ["type": "integer", "minimum": setRange.lowerBound, "maximum": setRange.upperBound],
                "reps_low": ["type": "integer", "minimum": repRange.lowerBound, "maximum": repRange.upperBound],
                "reps_high": ["type": "integer", "minimum": repRange.lowerBound, "maximum": repRange.upperBound,
                              "description": "Top of the rep range; leave out for a single rep target."],
                "weight_kg": ["type": "number", "minimum": 0, "maximum": maxWeightKg],
                "rest_sec": ["type": "integer", "minimum": restRange.lowerBound, "maximum": restRange.upperBound,
                             "description": "Rest after each set. In a superset only the last line's rest is used: the rest after the round."],
                "superset": ["type": "string",
                             "description": "The same letter on consecutive lines makes one superset (A, B…). Leave out for an exercise done on its own."],
                "note": ["type": "string"],
            ] as [String: Any],
            "required": ["exercise", "sets"],
        ]
        return [
            "name": toolName,
            "description": "Show the user a session as a card with “Add to Lift Log” and “Start”. Nothing is saved "
                + "until they tap. Use it whenever you propose or change a session, with the WHOLE session, "
                + "instead of writing the session as text.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "name": ["type": "string"],
                    "estimated_minutes": ["type": "integer", "minimum": minuteRange.lowerBound,
                                          "maximum": minuteRange.upperBound],
                    "lines": ["type": "array", "items": line, "minItems": 1, "maxItems": maxLines],
                ] as [String: Any],
                "required": ["name", "lines"],
            ] as [String: Any],
        ]
    }

    /// What the model is told once the card is shown.
    static let shownResult = "Shown to the user as a card with “Add to Lift Log” and “Start”. Nothing is saved "
        + "until they tap. Do not repeat the session in text and add nothing after it."

    /// The proposal in a `create_program` input, bounded; nil when it has no usable line.
    static func fromToolInput(_ input: [String: Any]) -> CoachSessionProposal? {
        let rawLines = (input["lines"] as? [[String: Any]]) ?? []
        var lines: [Line] = []
        for raw in rawLines.prefix(maxLines) {
            guard let exercise = CoachTools.text(raw, "exercise") else { continue }
            var low = optionalInteger(raw, "reps_low", in: repRange)
            var high = optionalInteger(raw, "reps_high", in: repRange)
            if low == nil { low = high; high = nil }
            if let l = low, let h = high {
                if h < l { (low, high) = (h, l) } else if h == l { high = nil }
            }
            let weight = number(raw, "weight_kg").map { min(max(($0 * 4).rounded() / 4, 0), maxWeightKg) }
            lines.append(Line(exercise: exercise,
                              sets: CoachTools.integer(raw, "sets", fallback: 3, in: setRange),
                              repsLow: low, repsHigh: high,
                              weightKg: weight == 0 ? nil : weight,
                              restSec: optionalInteger(raw, "rest_sec", in: restRange),
                              superset: LiftSuperset.normalizedLabel(raw["superset"] as? String),
                              note: CoachTools.text(raw, "note")))
        }
        guard !lines.isEmpty else { return nil }
        let name = CoachTools.text(input, "name") ?? String(localized: "Coach session")
        return CoachSessionProposal(name: String(name.prefix(80)),
                                    minutes: optionalInteger(input, "estimated_minutes", in: minuteRange),
                                    lines: lines, programId: nil)
    }

    /// An integer input clamped to `range`, nil when it is missing or not a number.
    private static func optionalInteger(_ input: [String: Any], _ key: String, in range: ClosedRange<Int>) -> Int? {
        let raw: Int?
        if let number = input[key] as? NSNumber { raw = number.intValue }
        else if let text = input[key] as? String { raw = Int(text.trimmingCharacters(in: .whitespaces)) }
        else { raw = nil }
        return raw.map { min(max($0, range.lowerBound), range.upperBound) }
    }

    private static func number(_ input: [String: Any], _ key: String) -> Double? {
        if let n = input[key] as? NSNumber { return n.doubleValue }
        if let s = input[key] as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }

    // MARK: Structure

    /// The session as the card lays it out: lines done on their own, and supersets.
    enum Block: Equatable {
        case single(Int)
        case superset(label: String, lines: Range<Int>)
    }

    var blocks: [Block] {
        let groups = LiftSuperset.groups(lines.map(\.superset))
        var out: [Block] = []
        var index = 0
        while index < lines.count {
            if let group = groups.first(where: { $0.lowerBound == index }) {
                out.append(.superset(label: LiftSuperset.normalizedLabel(lines[index].superset) ?? "", lines: group))
                index = group.upperBound
            } else {
                out.append(.single(index))
                index += 1
            }
        }
        return out
    }

    /// How many lines are done on their own, how many supersets, and how many sets in all.
    var counts: (singles: Int, supersets: Int, sets: Int) {
        let blocks = self.blocks
        let singles = blocks.filter { if case .single = $0 { return true } else { return false } }.count
        return (singles, blocks.count - singles, lines.reduce(0) { $0 + $1.sets })
    }

    /// "A1" for the first line of superset A, nil for a line done on its own.
    func position(of index: Int) -> String? {
        for block in blocks {
            if case let .superset(label, range) = block, range.contains(index) {
                return "\(label)\(index - range.lowerBound + 1)"
            }
        }
        return nil
    }

    /// "4 × 6", "3 × 8-10".
    static func target(_ line: Line) -> String {
        switch (line.repsLow, line.repsHigh) {
        case let (low?, high?): return "\(line.sets) × \(low)-\(high)"
        case let (low?, nil): return "\(line.sets) × \(low)"
        default: return "\(line.sets) ×"
        }
    }

    /// Seconds as m:ss.
    static func restText(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: Text

    /// The session as text, in the coach's own format: one line per exercise, A1/A2 for a superset,
    /// and the rest after each block. `rest` writes a rest line from its seconds and, for a superset,
    /// the position it follows ("A2").
    func text(weight: (Double) -> String, rest: (_ seconds: Int, _ after: String?) -> String) -> String {
        var out = ["**\(name)**" + (minutes.map { " · ≈ \($0) min" } ?? "")]
        for block in blocks {
            switch block {
            case .single(let index):
                out.append(lineText(index, weight: weight))
                if let seconds = lines[index].restSec { out.append(rest(seconds, nil)) }
            case let .superset(_, range):
                for index in range { out.append(lineText(index, weight: weight)) }
                if let seconds = lines[range.upperBound - 1].restSec {
                    out.append(rest(seconds, position(of: range.upperBound - 1)))
                }
            }
        }
        return out.joined(separator: "\n")
    }

    private func lineText(_ index: Int, weight: (Double) -> String) -> String {
        let line = lines[index]
        var text = (position(of: index).map { $0 + " " } ?? "") + line.exercise + " — " + Self.target(line)
        if let kg = line.weightKg { text += " · " + weight(kg) }
        return text
    }

    /// The session as the model reads it back in a later turn, so "make it shorter" refers to it.
    func wireText(system: UnitSystem) -> String {
        let unit = LiftFormat.weightUnit(system)
        return "[Session shown to the user as a card" + (programId == nil ? "" : ", added to their Lift Log") + "]\n"
            + text(weight: { LiftFormat.trim(LiftFormat.display(fromKilograms: $0, system: system)) + " " + unit },
                   rest: { seconds, after in
                       "rest \(Self.restText(seconds))" + (after.map { " after \($0)" } ?? "")
                   })
    }

    // MARK: Lift Log

    /// The program lines to store for `programId`. `name` maps an exercise to the Lift Log's own
    /// spelling when it already knows it, so its history stays in one place.
    func programItems(programId: String, deviceId: String, name: (String) -> String) -> [LiftProgramItemRow] {
        lines.enumerated().map { index, line in
            LiftProgramItemRow(id: UUID().uuidString, deviceId: deviceId, programId: programId, ord: index,
                               exercise: name(line.exercise), targetSets: line.sets,
                               targetRepsLow: line.repsLow, targetRepsHigh: line.repsHigh, targetRpe: nil,
                               targetWeightKg: line.weightKg, restSec: line.restSec, note: line.note,
                               supersetGroup: line.superset)
        }
    }

    /// The Lift Log's spelling of `exercise` among `known`, else the name as written.
    static func liftLogName(_ exercise: String, known: [String]) -> String {
        known.first { CoachTools.sameExercise($0, exercise) } ?? exercise
    }
}
