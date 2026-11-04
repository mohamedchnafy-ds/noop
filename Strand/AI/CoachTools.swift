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
        /// The meal journal (personal fork, Nutrition).
        case meals = "get_meals"
        /// One day's heart rate, as the Today card's Day view draws it, with the time in each zone (chantier 8).
        case dayHeartRate = "get_day_heart_rate"
        /// The caffeine tracker: what was logged and the estimate still active (chantier 8).
        case caffeine = "get_caffeine"
    }

    /// The metrics `get_metric_history` can return, by the names the fiche uses.
    enum Metric: String, CaseIterable {
        case charge, effort, sleep, hrv, rhr, spo2, respiration
        case skinTemp = "skin_temp"
        case steps, calories
        /// Read from their own series rather than the daily row (chantier 8): the Apple Health weight, the
        /// water tracker's day totals and the Stress screen's daily history.
        case weight, water, stress

        /// Whether the value comes from the daily row (`value(_:)`); false for the series-backed metrics.
        var isDailyRow: Bool {
            switch self {
            case .weight, .water, .stress: return false
            default: return true
            }
        }

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
            case .weight, .water, .stress: return nil
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
            case .weight: return "Weight (kg, from Apple Health)"
            case .water: return "Water logged (ml, the water tracker; logged water is not all the water drunk)"
            case .stress: return "Stress (daily 0-3 proxy from resting HR and HRV, the Stress screen's history; "
                + "under 1 low, 1-2 moderate, 2 and over high)"
            }
        }

        /// One value as the result writes it.
        func wireValue(_ value: Double) -> String {
            switch self {
            case .charge, .hrv, .rhr, .steps, .calories, .water: return "\(Int(value.rounded()))"
            case .effort, .respiration, .weight, .stress: return String(format: "%.1f", value)
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
            case .weight: return String(localized: "Weight")
            case .water: return String(localized: "Hydration")
            case .stress: return String(localized: "Stress")
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
    static let mealDayRange = 1...30
    /// How far back `get_day_heart_rate` reads, in days before today.
    static let dayHeartRateLookbackDays = 60
    /// The slots `get_day_heart_rate` groups the 5-minute buckets into, so a whole day stays short.
    static let dayHeartRateSlotSeconds = 1800
    /// The slots the night curves of `get_night` are grouped into.
    static let nightCurveSlotSeconds = 1800

    // MARK: Definitions

    /// The tools sent with a question: `create_program` always (it reads nothing and saves nothing);
    /// the read tools only with "Use my data", and the Lab Book only with the second opt-in ("Patterns
    /// and Lab Book"), the same switch that gates its summary in the fiche.
    static func definitions(dataConsent: Bool, labBook: Bool) -> [[String: Any]] {
        // The cards: the session, the meal with the Ciqual search it needs, the menu of a day (chantier 8),
        // the nap and the fact to remember. None reads the user's data.
        let cards = [CoachSessionProposal.definition, CoachMealProposal.searchDefinition, CoachMealProposal.logDefinition,
                     CoachMealProposal.labelDefinition, CoachMenuProposal.definition, CoachActionProposal.napDefinition,
                     CoachActionProposal.rememberDefinition]
        guard dataConsent else { return cards }
        var tools: [[String: Any]] = [
            tool(.metricHistory,
                 "Daily values of one metric over the last N days (oldest first), with how many days were "
                 + "measured, the average, the lowest and the highest. Use it when the question needs more "
                 + "than the 14 days the fiche carries. weight is the Apple Health weight, water the water "
                 + "tracker's day totals, stress the Stress screen's daily history.",
                 properties: [
                    "metric": ["type": "string", "enum": Metric.allCases.map(\.rawValue)],
                    "days": ["type": "integer", "minimum": dayRange.lowerBound, "maximum": dayRange.upperBound],
                 ],
                 required: ["metric", "days"]),
            tool(.night,
                 "Detail of one night: duration, stages, efficiency, disturbances, HRV, resting HR, SpO2, "
                 + "respiration, skin temperature, each sleep period with its times, and the night's heart-rate "
                 + "and HRV curves (the Sleep screen's) every 30 minutes.",
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
            tool(.meals,
                 "The meal journal over the last N days, newest first: each day's totals, then each meal with its "
                 + "time, name, calories and macros (computed by the app). A day with no meal logged is not a "
                 + "day without food.",
                 properties: ["days": ["type": "integer", "minimum": mealDayRange.lowerBound,
                                       "maximum": mealDayRange.upperBound]],
                 required: ["days"]),
            tool(.dayHeartRate,
                 "One day's heart rate as the Today card draws it (5-minute averages from the strap), grouped "
                 + "every 30 minutes with the lowest and highest beat, the day's sleep, and the time spent in "
                 + "each heart-rate zone. Today when no date is given.",
                 properties: ["date": ["type": "string",
                                       "description": "YYYY-MM-DD, at most \(dayHeartRateLookbackDays) days ago."]],
                 required: []),
            tool(.caffeine,
                 "The caffeine tracker: each intake logged in the last 48 hours (the app keeps no more) and the "
                 + "estimate of what is still active now. Logged by the user, an estimate, not a measurement.",
                 properties: [:], required: []),
        ]
        if labBook {
            tools.append(tool(.labBook,
                              "The user's own Lab Book markers (blood tests and the like): the latest values of "
                              + "each, with their dates. Logged by the user, not medical findings.",
                              properties: [:], required: []))
        }
        // The corrections name a record the read tools listed, so they come with "Use my data" only.
        return tools + cards + [CoachActionProposal.workoutDefinition, CoachActionProposal.liftDefinition]
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
        metricHistory(metric, dayKeys: dayKeys, values: byDay.compactMapValues(metric.value))
    }

    /// `get_metric_history` from one value per day, the series-backed metrics' path (weight, water, stress).
    static func metricHistory(_ metric: Metric, dayKeys: [String], values valueByDay: [String: Double]) -> String {
        guard let first = dayKeys.first, let last = dayKeys.last else { return "No days asked for." }
        var lines = ["\(metric.wireTitle), \(first) to \(last). A dash means NOT MEASURED, not zero:"]
        var values: [Double] = []
        for key in dayKeys {
            if let value = valueByDay[key] {
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
                      timeZone: TimeZone, heartRate: [HRBucket] = [],
                      hrv: [(ts: Int, value: Double)] = []) -> String {
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
        let clock = clockFormatter(timeZone)
        func at(_ ts: Int) -> String { clock.string(from: Date(timeIntervalSince1970: TimeInterval(ts))) }
        let hrSlots = slots(heartRate.map { (ts: $0.ts, value: $0.bpm) }, seconds: nightCurveSlotSeconds)
        if !hrSlots.isEmpty {
            var line = "sleeping heart rate every 30 min (bpm): "
                + hrSlots.map { "\(at($0.ts)) \(Int($0.mean.rounded()))" }.joined(separator: ", ")
            if let low = heartRate.min(by: { $0.bpm < $1.bpm }) {
                line += "; lowest \(Int(low.bpm.rounded())) at \(at(low.ts))"
            }
            lines.append(line)
        }
        let hrvSlots = slots(hrv, seconds: nightCurveSlotSeconds)
        if !hrvSlots.isEmpty {
            lines.append("HRV (rMSSD) every 30 min (ms): "
                         + hrvSlots.map { "\(at($0.ts)) \(Int($0.mean.rounded()))" }.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    /// Values grouped into `seconds`-wide slots aligned on the clock (oldest first), each with its mean, lowest
    /// and highest. A slot with no value is left out, so a gap stays a gap.
    static func slots(_ values: [(ts: Int, value: Double)], seconds: Int)
        -> [(ts: Int, mean: Double, low: Double, high: Double)] {
        let width = max(seconds, 1)
        var grouped: [Int: [Double]] = [:]
        for v in values where v.value.isFinite { grouped[v.ts - ((v.ts % width) + width) % width, default: []].append(v.value) }
        return grouped.keys.sorted().compactMap { start in
            guard let group = grouped[start], let low = group.min(), let high = group.max() else { return nil }
            return (ts: start, mean: group.reduce(0, +) / Double(group.count), low: low, high: high)
        }
    }

    /// `get_day_heart_rate`: the day's 5-minute buckets (the Today card's own read) grouped every 30 minutes
    /// with the lowest and highest beat of each slot, the card's three figures, the sleep inside the day and the
    /// time in each zone of `zones` (nil when the day has no sample).
    static func dayHeartRate(day: String, buckets: [HRBucket], sleep: [ClosedRange<Int>], restingHR: Double?,
                             zones: TimeInZone?, hrMax: Int, timeZone: TimeZone) -> String {
        guard !buckets.isEmpty else {
            return "No heart rate recorded on \(day): the strap was not worn or not synced."
        }
        let clock = clockFormatter(timeZone)
        func at(_ ts: Int) -> String { clock.string(from: Date(timeIntervalSince1970: TimeInterval(ts))) }
        func bpm(_ v: Double) -> String { "\(Int(v.rounded()))" }
        let means = buckets.map(\.bpm)
        let average = means.reduce(0, +) / Double(means.count)
        var lines = ["Heart rate on \(day) (strap, 5-minute averages as the Today card draws them; a missing slot "
                     + "means NOT RECORDED):"]
        var summary = "lowest 5-min average \(bpm(means.min() ?? average)), average \(bpm(average)), "
            + "highest \(bpm(means.max() ?? average))"
        if let low = buckets.map(\.minBpm).min(), let high = buckets.map(\.maxBpm).max() {
            summary += "; lowest beat \(bpm(low)), highest beat \(bpm(high))"
        }
        if let rest = restingHR { summary += "; resting HR \(bpm(rest))" }
        lines.append(summary)
        if !sleep.isEmpty {
            lines.append("asleep: " + sleep.sorted { $0.lowerBound < $1.lowerBound }
                .map { "\(at($0.lowerBound))–\(at($0.upperBound))" }.joined(separator: ", "))
        }
        lines.append("every 30 min, average (lowest–highest beat):")
        var grouped: [Int: [HRBucket]] = [:]
        let width = dayHeartRateSlotSeconds
        for b in buckets { grouped[b.ts - ((b.ts % width) + width) % width, default: []].append(b) }
        for start in grouped.keys.sorted() {
            guard let group = grouped[start], let low = group.map(\.minBpm).min(),
                  let high = group.map(\.maxBpm).max() else { continue }
            let mean = group.map(\.bpm).reduce(0, +) / Double(group.count)
            lines.append("  \(at(start)) \(bpm(mean)) (\(bpm(low))–\(bpm(high)))")
        }
        if let zones, zones.total > 0 {
            var parts = ["below zone 1 \(minutesText(zones.belowZone1))"]
            for zone in 1...5 { parts.append("zone \(zone) \(minutesText(zones.seconds(inZone: zone)))") }
            lines.append("time in heart-rate zones (the app's zones, HR max \(hrMax)): " + parts.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    /// `get_caffeine`: the intakes the tracker still keeps (newest first) and the active estimate at `now`.
    static func caffeine(_ intakes: [CaffeineIntake], estimate: CaffeineActiveEstimate, now: Date,
                         timeZone: TimeZone) -> String {
        guard !intakes.isEmpty else {
            return "No caffeine logged in the last 48 hours. That says nothing about what was drunk."
        }
        let clock = clockFormatter(timeZone)
        var lines = ["Caffeine logged by the user in the last 48 hours (newest first; the app keeps no more):"]
        for intake in intakes.sorted(by: { $0.at > $1.at }) {
            let hoursAgo = max(0, now.timeIntervalSince(intake.at) / 3600)
            var line = "  \(clock.string(from: intake.at)) (\(String(format: "%.1f", hoursAgo)) h ago): "
                + (intake.mg.map { "\(Int($0.rounded())) mg" } ?? "amount not given")
            if intake.isImported { line += " (from Apple Health)" }
            lines.append(line)
        }
        if !estimate.hasActive {
            lines.append("Still active now: none (estimate, half-life \(String(format: "%.1f", CaffeineDecay.defaultHalfLifeHours)) h).")
        } else if let mg = estimate.totalRemainingMg {
            lines.append("Still active now: about \(Int(mg.rounded())) mg from \(estimate.activeIntakeCount) intake(s) "
                         + "(estimate, half-life \(String(format: "%.1f", CaffeineDecay.defaultHalfLifeHours)) h; "
                         + "intakes without an amount are not counted in the mg).")
        } else {
            lines.append("Still active now: \(estimate.activeIntakeCount) intake(s) without an amount, so no mg estimate.")
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
        /// "18:05", the start `correct_workout` names the workout by (chantier 8).
        var start: String? = nil
        /// True for a workout entered by hand, the only kind `correct_workout` can change.
        var enteredByHand = false
    }

    /// `get_workouts`: newest first, one line each.
    static func workouts(_ rows: [Workout], days: Int) -> String {
        guard !rows.isEmpty else { return "No workout recorded in the last \(days) days." }
        var lines = ["Workouts of the last \(days) days (newest first):"]
        for w in rows {
            var parts = [[w.day, w.start, w.sport].compactMap { $0 }.joined(separator: " ")]
            if let m = w.durationMin { parts.append("\(m) min") }
            if let e = w.effort { parts.append("effort \(String(format: "%.1f", e))") }
            if let hr = w.avgHr { parts.append("avg HR \(hr)") }
            if let hr = w.maxHr { parts.append("max HR \(hr)") }
            if let k = w.kcal { parts.append("\(k) kcal") }
            if let d = w.distance { parts.append(d) }
            if w.enteredByHand { parts.append("entered by hand") }
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

    /// One day of the meal journal as `get_meals` writes it.
    struct MealDay: Equatable {
        struct Meal: Equatable {
            var time: String
            var name: String
            var nutrients: MealNutrients
            /// Fork chantier 9: the moment of the day it is filed in (`MealSlot` raw value).
            var slot: String? = nil
            /// A meal of a menu the Coach proposed (still in the journal: maybe not eaten).
            var fromCoachMenu: Bool = false
        }
        var day: String
        var meals: [Meal]
    }

    /// `get_meals`: newest day first, each with its totals then its meals; days with no meal are left out.
    static func meals(_ days: [MealDay], from: String, to: String) -> String {
        func values(_ n: MealNutrients) -> String {
            "\(n.kcal) kcal, P \(CoachMealProposal.tenthText(n.proteinG)), C \(CoachMealProposal.tenthText(n.carbsG)), "
                + "F \(CoachMealProposal.tenthText(n.fatG))"
        }
        let logged = days.filter { !$0.meals.isEmpty }.sorted { $0.day > $1.day }
        guard !logged.isEmpty else {
            return "No meal logged from \(from) to \(to). That says nothing about what was eaten."
        }
        var lines = ["Meal journal, \(from) to \(to) (calories and macros computed by the app). "
                     + "A day with no meal logged is not a day without food:"]
        for day in logged {
            let total = MealMath.totals(day.meals.map(\.nutrients))
            lines.append("\(day.day): \(values(total)) · \(day.meals.count) meal\(day.meals.count == 1 ? "" : "s")")
            for meal in day.meals {
                var label = "  \(meal.time)" + (meal.slot.map { " \($0)" } ?? "") + " \(meal.name)"
                if meal.fromCoachMenu { label += " (from your menu)" }
                lines.append(label + ": " + values(meal.nutrients))
            }
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
        case .meals:
            let days = integer(input, "days", fallback: 7, in: mealDayRange)
            return String(localized: "Meals since \(since(days: days))")
        case .dayHeartRate:
            if let day = text(input, "date"), let date = dayFormatter(calendar).date(from: day),
               !calendar.isDate(date, inSameDayAs: now) {
                return String(localized: "Heart rate of \(date.formatted(.dateTime.day().month(.abbreviated)))")
            }
            return String(localized: "Today's heart rate")
        case .caffeine:
            return String(localized: "Caffeine")
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

    private static func clockFormatter(_ timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    /// Seconds as "1h 05m" or "12m".
    private static func minutesText(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes >= 60 ? String(format: "%dh %02dm", minutes / 60, minutes % 60) : "\(minutes)m"
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
