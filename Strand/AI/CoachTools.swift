import Foundation
import StrandAnalytics
import WhoopStore

/// The Coach's read tools (personal fork, Anthropic only): what the model may ask for when the fiche
/// does not carry enough, how its input is read, how each answer is written, and the short label the
/// screen shows under the reply ("Looked at: HRV since 3 Sept").
///
/// PURE: no store, no network. The engine fetches the rows (`AICoachEngine.runTool`) and hands them
/// here, so the wording and the limits are tested without a strap. Every tool only READS: nothing a
/// tool does is stored, and the model never receives more than the user's own summarised figures,
/// the same kind of text the fiche already sends.
enum CoachTools {

    enum Name: String, CaseIterable {
        case metricHistory = "get_metric_history"
        case night = "get_night"
        case workouts = "get_workouts"
        case exerciseHistory = "get_exercise_history"
        case programs = "get_programs"
        case journal = "get_journal"
        case labBook = "get_lab_book"
    }

    /// The metrics `get_metric_history` can return, by the names the fiche uses.
    enum Metric: String, CaseIterable {
        case charge, effort, sleep, hrv, rhr, spo2, respiration
        case skinTemp = "skin_temp"
        case steps, calories

        /// The value of this metric on one day, nil when it was not measured.
        func value(_ day: DailyMetric) -> Double? {
            switch self {
            case .charge: return day.recovery
            case .effort: return day.strain
            case .sleep: return day.totalSleepMin
            case .hrv: return day.avgHrv
            case .rhr: return day.restingHr.map(Double.init)
            case .spo2: return day.spo2Pct
            case .respiration: return day.respRateBpm
            case .skinTemp: return day.skinTempDevC
            case .steps: return day.steps.map(Double.init)
            case .calories: return day.activeKcalEst
            }
        }

        /// How the result names the metric and its unit, in English like the rest of the fiche.
        var wireTitle: String {
            switch self {
            case .charge: return "Charge (recovery, 0-100)"
            case .effort: return "Effort (day strain, 0-100)"
            case .sleep: return "Sleep (main night, hours)"
            case .hrv: return "HRV (ms)"
            case .rhr: return "Resting HR (bpm)"
            case .spo2: return "SpO2 during sleep (%)"
            case .respiration: return "Respiration during sleep (breaths/min)"
            case .skinTemp: return "Skin-temperature deviation (°C from baseline)"
            case .steps: return "Steps"
            case .calories: return "Active calories (kcal, estimate)"
            }
        }

        /// One value as the result writes it.
        func wireValue(_ value: Double) -> String {
            switch self {
            case .charge, .hrv, .rhr, .steps, .calories: return "\(Int(value.rounded()))"
            case .effort, .respiration: return String(format: "%.1f", value)
            case .sleep: return String(format: "%.1f", value / 60)
            case .spo2: return String(format: "%.1f", value)
            case .skinTemp: return String(format: "%+.1f", value)
            }
        }

        /// The metric's name on screen, under the reply.
        var title: String {
            switch self {
            case .charge: return String(localized: "Charge")
            case .effort: return String(localized: "Effort")
            case .sleep: return String(localized: "Sleep")
            case .hrv: return String(localized: "HRV")
            case .rhr: return String(localized: "Resting HR")
            case .spo2: return String(localized: "SpO2")
            case .respiration: return String(localized: "Respiration")
            case .skinTemp: return String(localized: "Skin temperature")
            case .steps: return String(localized: "Steps")
            case .calories: return String(localized: "Calories")
            }
        }
    }

    // MARK: Limits

    /// Most tool rounds in one answer. The round after the last one is asked with tools off, so the
    /// reply always ends in text.
    static let maxRounds = 4
    /// Longest result handed back, so one wide question cannot fill the model's window.
    static let maxResultCharacters = 6000
    static let dayRange = 7...180
    static let journalDayRange = 7...90
    static let sessionRange = 1...20
    /// How far back `get_exercise_history` looks for sessions.
    static let exerciseLookbackDays = 365

    // MARK: Definitions

    /// The tools sent with a question: `create_program` always (it reads nothing and saves nothing);
    /// the read tools only with "Use my data", and the Lab Book only with the second opt-in ("Patterns
    /// and Lab Book"), the same switch that gates its summary in the fiche.
    static func definitions(dataConsent: Bool, labBook: Bool) -> [[String: Any]] {
        guard dataConsent else { return [CoachSessionProposal.definition] }
        var tools: [[String: Any]] = [
            tool(.metricHistory,
                 "Daily values of one metric over the last N days (oldest first), with how many days were "
                 + "measured, the average, the lowest and the highest. Use it when the question needs more "
                 + "than the 14 days the fiche carries.",
                 properties: [
                    "metric": ["type": "string", "enum": Metric.allCases.map(\.rawValue)],
                    "days": ["type": "integer", "minimum": dayRange.lowerBound, "maximum": dayRange.upperBound],
                 ],
                 required: ["metric", "days"]),
            tool(.night,
                 "Detail of one night: duration, stages, efficiency, disturbances, HRV, resting HR, SpO2, "
                 + "respiration, skin temperature and each sleep period with its times.",
                 properties: ["date": ["type": "string",
                                       "description": "YYYY-MM-DD, the day the night ended (the morning)."]],
                 required: ["date"]),
            tool(.workouts,
                 "Every workout of the last N days, newest first: sport, duration, effort, average and "
                 + "maximum heart rate, calories, distance.",
                 properties: ["days": ["type": "integer",
                                       "minimum": dayRange.lowerBound, "maximum": dayRange.upperBound]],
                 required: ["days"]),
            tool(.exerciseHistory,
                 "Every working set of one Lift Log exercise over its last sessions, newest first, with the "
                 + "best estimated one-rep max of each session. Name the exercise as the Lift Log does.",
                 properties: [
                    "exercise": ["type": "string"],
                    "sessions": ["type": "integer",
                                 "minimum": sessionRange.lowerBound, "maximum": sessionRange.upperBound],
                 ],
                 required: ["exercise"]),
            tool(.programs,
                 "Every saved Lift Log program with all its lines: sets, reps, planned weight, rest and "
                 + "supersets (A1, A2…).",
                 properties: [:], required: []),
            tool(.journal,
                 "The user's Journal answers over the last N days: each question, yes or no, value and note.",
                 properties: ["days": ["type": "integer", "minimum": journalDayRange.lowerBound,
                                       "maximum": journalDayRange.upperBound]],
                 required: ["days"]),
        ]
        if labBook {
            tools.append(tool(.labBook,
                              "The user's own Lab Book markers (blood tests and the like): the latest values of "
                              + "each, with their dates. Logged by the user, not medical findings.",
                              properties: [:], required: []))
        }
        return tools + [CoachSessionProposal.definition]
    }

    private static func tool(_ name: Name, _ description: String, properties: [String: Any],
                             required: [String]) -> [String: Any] {
        ["name": name.rawValue,
         "description": description,
         "input_schema": ["type": "object", "properties": properties, "required": required] as [String: Any]]
    }

    // MARK: Input

    /// A tool's input as the model sent it: a JSON object, or empty when it is anything else.
    static func input(fromJSON json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    /// An integer input, clamped to `range`; `fallback` when it is missing or not a number.
    static func integer(_ input: [String: Any], _ key: String, fallback: Int, in range: ClosedRange<Int>) -> Int {
        let raw: Int?
        if let number = input[key] as? NSNumber { raw = number.intValue }
        else if let text = input[key] as? String { raw = Int(text.trimmingCharacters(in: .whitespaces)) }
        else { raw = nil }
        return min(max(raw ?? fallback, range.lowerBound), range.upperBound)
    }

    /// A text input, trimmed; nil when missing or blank.
    static func text(_ input: [String: Any], _ key: String) -> String? {
        guard let value = (input[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    /// A result cut to `maxResultCharacters`, saying so when it is cut.
    static func capped(_ result: String) -> String {
        guard result.count > maxResultCharacters else { return result }
        return String(result.prefix(maxResultCharacters)) + "\n… (cut: ask for a shorter period)"
    }

    // MARK: Results

    /// `get_metric_history`: one line per calendar day in `dayKeys` (oldest first), a dash for a day
    /// with no value, then the count, average, lowest and highest of the measured days.
    static func metricHistory(_ metric: Metric, dayKeys: [String], byDay: [String: DailyMetric]) -> String {
        guard let first = dayKeys.first, let last = dayKeys.last else { return "No days asked for." }
        var lines = ["\(metric.wireTitle), \(first) to \(last). A dash means NOT MEASURED, not zero:"]
        var values: [Double] = []
        for key in dayKeys {
            if let value = byDay[key].flatMap(metric.value) {
                values.append(value)
                lines.append("\(key) \(metric.wireValue(value))")
            } else {
                lines.append("\(key) —")
            }
        }
        if values.isEmpty {
            lines.append("Not measured on any of these \(dayKeys.count) days.")
        } else {
            let average = values.reduce(0, +) / Double(values.count)
            lines.append("Measured on \(values.count) of \(dayKeys.count) days: average \(metric.wireValue(average)), "
                         + "lowest \(metric.wireValue(values.min() ?? average)), "
                         + "highest \(metric.wireValue(values.max() ?? average)).")
        }
        return lines.joined(separator: "\n")
    }

    /// `get_night`: the night ending on `day`, from its daily row and its sleep periods.
    static func night(day: String, metric: DailyMetric?, periods: [(start: Int, end: Int)],
                      timeZone: TimeZone) -> String {
        guard metric != nil || !periods.isEmpty else {
            return "No night recorded ending on \(day)."
        }
        var lines = ["Night ending \(day). A dash means NOT MEASURED, not zero:"]
        if let d = metric {
            lines.append("asleep \(hours(d.totalSleepMin)) (deep \(hours(d.deepMin)), REM \(hours(d.remMin)), "
                         + "light \(hours(d.lightMin))), efficiency \(efficiency(d.efficiency)), "
                         + "disturbances \(d.disturbances.map(String.init) ?? "—")")
            lines.append("HRV \(d.avgHrv.map { "\(Int($0.rounded())) ms" } ?? "—"), "
                         + "RHR \(d.restingHr.map { "\($0) bpm" } ?? "—"), "
                         + "SpO2 \(d.spo2Pct.map { String(format: "%.1f%%", $0) } ?? "—"), "
                         + "respiration \(d.respRateBpm.map { String(format: "%.1f/min", $0) } ?? "—"), "
                         + "skin-temp deviation \(d.skinTempDevC.map { String(format: "%+.1f°C", $0) } ?? "—")")
        }
        if !periods.isEmpty {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = "HH:mm"
            let parts = periods.sorted { $0.start < $1.start }.map { period -> String in
                let start = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(period.start)))
                let end = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(period.end)))
                return "\(start)–\(end) (\(hours(Double(period.end - period.start) / 60)))"
            }
            lines.append("sleep periods: " + parts.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    /// One workout as `get_workouts` lists it.
    struct Workout: Equatable {
        var day: String
        var sport: String
        var durationMin: Int?
        var effort: Double?
        var avgHr: Int?
        var maxHr: Int?
        var kcal: Int?
        var distance: String?
    }

    /// `get_workouts`: newest first, one line each.
    static func workouts(_ rows: [Workout], days: Int) -> String {
        guard !rows.isEmpty else { return "No workout recorded in the last \(days) days." }
        var lines = ["Workouts of the last \(days) days (newest first):"]
        for w in rows {
            var parts = ["\(w.day) \(w.sport)"]
            if let m = w.durationMin { parts.append("\(m) min") }
            if let e = w.effort { parts.append("effort \(String(format: "%.1f", e))") }
            if let hr = w.avgHr { parts.append("avg HR \(hr)") }
            if let hr = w.maxHr { parts.append("max HR \(hr)") }
            if let k = w.kcal { parts.append("\(k) kcal") }
            if let d = w.distance { parts.append(d) }
            lines.append(parts.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    /// One Lift Log session as `get_exercise_history` reads it.
    struct LiftSession {
        var startTs: Int
        var programName: String?
        var sets: [LiftSetRow]
    }

    /// `get_exercise_history`: the sessions with working sets of the exercise named `query` (case and
    /// accents ignored), newest first, at most `limit`. When no set matches, the exercises that were
    /// logged, so the model can ask again with the Lift Log's own name.
    static func exerciseHistory(query: String, sessions: [LiftSession], limit: Int, system: UnitSystem,
                                dayKey: (Int) -> String) -> String {
        let unit = LiftFormat.weightUnit(system)
        let matching = sessions
            .map { session -> (LiftSession, [LiftSetRow]) in
                (session, session.sets.filter {
                    sameExercise($0.exercise, query) && !$0.isWarmup && LiftMetrics.isPerformed(reps: $0.reps)
                })
            }
            .filter { !$0.1.isEmpty }
            .sorted { $0.0.startTs > $1.0.startTs }
            .prefix(limit)
        guard !matching.isEmpty else {
            let known = Set(sessions.flatMap { $0.sets.map(\.exercise) }).sorted()
            if known.isEmpty { return "No set of “\(query)” in the Lift Log, which has no session yet." }
            return "No set of “\(query)” in the Lift Log. Exercises logged: " + known.prefix(40).joined(separator: ", ")
        }
        let name = matching.first?.1.first?.exercise ?? query
        var lines = ["\(name): working sets of its last \(matching.count) session(s), newest first "
                     + "(weight × reps, \(unit); warm-ups left out):"]
        for (session, sets) in matching {
            let parts = sets.map { set -> String in
                var s = ""
                if let kg = set.weightKg { s += LiftFormat.trim(LiftFormat.display(fromKilograms: kg, system: system)) }
                if let reps = set.reps { s += (s.isEmpty ? "" : "×") + "\(reps)" }
                return s
            }
            var line = dayKey(session.startTs)
            if let program = session.programName, !program.isEmpty { line += " (\(program))" }
            line += ": " + parts.joined(separator: ", ")
            let best = sets.compactMap { LiftMetrics.estimatedOneRepMaxKg(weightKg: $0.weightKg, reps: $0.reps) }.max()
            if let best {
                line += " · best e1RM " + LiftFormat.trim(LiftFormat.display(fromKilograms: best, system: system))
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    /// Whether two exercise names are the same one, ignoring case, accents and outer spaces.
    static func sameExercise(_ a: String, _ b: String) -> Bool {
        let fold: (String) -> String = {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        }
        return fold(a) == fold(b)
    }

    /// One saved program as `get_programs` lists it.
    struct Program {
        var row: LiftProgramRow
        var items: [LiftProgramItemRow]
    }

    /// `get_programs`: every program with all its lines, supersets written A1, A2… as on paper, with
    /// the rest after the last line of a superset.
    static func programs(_ programs: [Program], system: UnitSystem) -> String {
        guard !programs.isEmpty else { return "No program saved in the Lift Log." }
        let unit = LiftFormat.weightUnit(system)
        var lines = ["Saved Lift Log programs (\(unit)):"]
        for program in programs {
            var head = program.row.name
            if let note = program.row.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                head += " — \(note)"
            }
            lines.append(head + ":")
            let items = program.items.sorted { $0.ord < $1.ord }
            let groups = LiftSuperset.groups(items.map(\.supersetGroup))
            for (index, item) in items.enumerated() {
                var line = "  "
                if let group = groups.first(where: { $0.contains(index) }),
                   let label = LiftSuperset.normalizedLabel(item.supersetGroup) {
                    line += "\(label)\(index - group.lowerBound + 1) "
                }
                line += item.exercise
                var target: [String] = []
                if let sets = item.targetSets { target.append("\(sets) ×") }
                switch (item.targetRepsLow, item.targetRepsHigh) {
                case let (low?, high?) where high != low: target.append("\(low)-\(high)")
                case let (low?, _): target.append("\(low)")
                case let (nil, high?): target.append("\(high)")
                default: break
                }
                if !target.isEmpty { line += " — " + target.joined(separator: " ") }
                if let kg = item.targetWeightKg {
                    line += " · " + LiftFormat.trim(LiftFormat.display(fromKilograms: kg, system: system))
                }
                if let rest = item.restSec { line += " · rest \(restClock(rest))" }
                if let note = item.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                    line += " · \(note)"
                }
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// `get_journal`: one line per answer, oldest first.
    static func journal(_ entries: [JournalEntry], days: Int) -> String {
        guard !entries.isEmpty else { return "No Journal answer in the last \(days) days." }
        var lines = ["Journal answers of the last \(days) days (oldest first):"]
        for e in entries.sorted(by: { ($0.day, $0.question) < ($1.day, $1.question) }).suffix(300) {
            var line = "\(e.day) \(e.question): \(e.answeredYes ? "yes" : "no")"
            if let value = e.numericValue { line += " (\(LiftFormat.trim(value)))" }
            if let note = e.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                line += " — " + note.replacingOccurrences(of: "\n", with: " ")
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    /// One Lab Book value as `get_lab_book` lists it, already named and formatted by the app.
    struct LabValue: Equatable {
        var marker: String
        var day: String
        var value: String
    }

    /// `get_lab_book`: per marker, its latest values (newest first, at most `perMarker`).
    static func labBook(_ values: [LabValue], perMarker: Int = 5) -> String {
        guard !values.isEmpty else { return "No marker logged in the Lab Book." }
        var lines = ["Lab Book (the user's own logged numbers; not medical findings, do not diagnose):"]
        let byMarker = Dictionary(grouping: values, by: \.marker)
        for marker in byMarker.keys.sorted() {
            let latest = (byMarker[marker] ?? []).sorted { $0.day > $1.day }.prefix(perMarker)
            lines.append("\(marker): " + latest.map { "\($0.value) (\($0.day))" }.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Labels (on screen)

    /// What the screen says the coach looked at for one call, in the app's language.
    static func label(_ name: Name, input: [String: Any], now: Date, calendar: Calendar = .current) -> String {
        func since(days: Int) -> String {
            let start = calendar.date(byAdding: .day, value: -(days - 1), to: now) ?? now
            return start.formatted(.dateTime.day().month(.abbreviated))
        }
        switch name {
        case .metricHistory:
            let metric = text(input, "metric").flatMap(Metric.init(rawValue:))
            let days = integer(input, "days", fallback: 30, in: dayRange)
            let title = metric?.title ?? String(localized: "Your data")
            return String(localized: "\(title) since \(since(days: days))")
        case .night:
            if let day = text(input, "date"), let date = dayFormatter(calendar).date(from: day) {
                return String(localized: "Night of \(date.formatted(.dateTime.day().month(.abbreviated)))")
            }
            return String(localized: "A night")
        case .workouts:
            return String(localized: "Workouts since \(since(days: integer(input, "days", fallback: 30, in: dayRange)))")
        case .exerciseHistory:
            return text(input, "exercise") ?? String(localized: "Lift Log")
        case .programs:
            return String(localized: "Lift Log programs")
        case .journal:
            let days = integer(input, "days", fallback: 30, in: journalDayRange)
            return String(localized: "Journal since \(since(days: days))")
        case .labBook:
            return String(localized: "Lab Book")
        }
    }

    /// The `yyyy-MM-dd` day keys from `days - 1` days before `now` to `now`, oldest first.
    static func dayKeys(days: Int, endingAt now: Date, calendar: Calendar = .current) -> [String] {
        let formatter = dayFormatter(calendar)
        return (0..<days).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: now).map(formatter.string(from:))
        }
    }

    private static func dayFormatter(_ calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func hours(_ minutes: Double?) -> String {
        minutes.map { String(format: "%.1fh", $0 / 60) } ?? "—"
    }

    /// Efficiency as a percentage; a stored value above 1.5 is already one (some imports store it so).
    private static func efficiency(_ raw: Double?) -> String {
        guard var e = raw, e > 0 else { return "—" }
        if e > 1.5 { e /= 100 }
        guard e <= 1 else { return "—" }
        return "\(Int((e * 100).rounded()))%"
    }

    /// Seconds as m:ss.
    private static func restClock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
