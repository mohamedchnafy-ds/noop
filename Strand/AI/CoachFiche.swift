import Foundation
import StrandAnalytics
import WhoopStore

/// The part of the coach's context that describes the user as the app sees them right now (personal
/// fork): body profile, today's readings, the personal normals, the sleep figures and the Lift Log
/// statuses. Sent with every question, ahead of the day-by-day summary `AICoachEngine.buildContext` writes.
///
/// Pure: `AICoachEngine.ficheInputs()` resolves every value with the helpers the Today, Sleep and Lift
/// Log screens use (`TodayVitalRange`, `TodayEnergy`, `SleepModel`, `HabitualWake`, `LiftProgress`), so
/// the coach is handed the figures those screens show rather than a second computation of them. The
/// context is English, like the rest of what the coach reads; a dash or an explicit "not measured" means
/// the value is absent, never zero.
enum CoachFiche {

    /// The body profile (`ProfileStore`), with which fields were actually entered by the user.
    struct Body: Equatable {
        var age: Int
        var sex: String
        var sexStored: Bool
        var heightCm: Double
        var heightStored: Bool
        var weightKg: Double
        var weightStored: Bool
        var hrMax: Int
        var hrMaxSetByUser: Bool
    }

    /// A reading and the local day it belongs to: the Today screen carries the latest night forward when
    /// today has none yet, and the coach is told which night it is.
    struct Reading: Equatable {
        var value: Double
        var day: String
    }

    struct Today: Equatable {
        var day: String
        var charge: Double?
        var effort: Double?
        var restMin: Double?
        var deepMin: Double?
        var remMin: Double?
        var lightMin: Double?
        var efficiency: Double?
        var restingHR: Reading?
        var hrv: Reading?
        var spo2: Reading?
        var respiration: Reading?
        var skinTempDev: Reading?
        var steps: Int?
        var restingKcal: Double?
        var activityKcal: Double?
    }

    struct Sleep: Equatable {
        var needMin: Double?
        var debtMin: Double?
        var isDebt = false
        var lastShortfallMin: Double?
        var usualWakeMin: Int?
        var lastNightMin: Double?
        var average30Min: Double?
    }

    struct Inputs: Equatable {
        var body: Body?
        var today: Today?
        var restingHRGauge: TodayVitalRange.Gauge?
        /// The personal normal band as the Charge score uses it (`TodayVitalRange.normalBand`), before the
        /// gauge clamps it to the 30-night range for drawing. Nil while it calibrates.
        var restingHRNormal: ClosedRange<Double>?
        var hrvGauge: TodayVitalRange.Gauge?
        var hrvNormal: ClosedRange<Double>?
        var sleep: Sleep?
        var exercises: [LiftProgress.Exercise] = []
        var priorities: [LiftProgress.Priority] = []
        var unitSystem: UnitSystem = .metric
    }

    /// Exercise lines past this are dropped (the attention-first ones stay).
    static let maxExercises = 20

    /// The head of the context, in reading order: the body profile, what the user told the coach
    /// (`told`, `CoachProfile.contextBlock`), today, the normals and the sleep figures. The Lift Log
    /// statuses (`progression`) go after the LIFT LOG block they qualify.
    static func head(_ inputs: Inputs, told: String) -> String {
        var blocks: [String] = []
        if let body = inputs.body { blocks.append(bodyBlock(body)) }
        blocks.append(told)
        if let today = inputs.today { blocks.append(todayBlock(today)) }
        let normals = normalsBlock(restingHR: inputs.restingHRGauge, restingHRNormal: inputs.restingHRNormal,
                                   hrv: inputs.hrvGauge, hrvNormal: inputs.hrvNormal, sleep: inputs.sleep)
        if !normals.isEmpty { blocks.append(normals) }
        if let sleep = inputs.sleep { blocks.append(sleepBlock(sleep)) }
        return blocks.joined(separator: "\n\n")
    }

    /// The LIFT PROGRESSION block for `inputs`, "" when nothing is logged.
    static func progression(_ inputs: Inputs) -> String {
        progressionBlock(exercises: inputs.exercises, priorities: inputs.priorities, system: inputs.unitSystem)
    }

    // MARK: Blocks

    static func bodyBlock(_ b: Body) -> String {
        func stored(_ text: String, _ isStored: Bool) -> String {
            isStored ? text : text + " (not entered: app default)"
        }
        let parts = [
            "age \(b.age)",
            stored("sex \(b.sex)", b.sexStored),
            stored("height \(Int(b.heightCm.rounded())) cm", b.heightStored),
            stored("weight \(one(b.weightKg)) kg", b.weightStored),
            "HR max \(b.hrMax) bpm (" + (b.hrMaxSetByUser ? "set by the user" : "estimated from age") + ")",
        ]
        return "USER PROFILE (from the app's Profile):\n  " + parts.joined(separator: ", ")
    }

    static func todayBlock(_ t: Today) -> String {
        let missing = "not measured"
        var lines = ["TODAY (\(t.day); the figures the Today screen shows; \"not measured\" means no value, not zero):"]
        let charge = t.charge.map { "\(Int($0.rounded()))" } ?? missing
        let effort = t.effort.map { one($0) } ?? missing
        lines.append("  charge \(charge), effort so far \(effort)")
        var night = "  last night: rest " + (t.restMin.map(hours) ?? missing)
        if t.restMin != nil {
            let stages: [String] = [
                "deep " + (t.deepMin.map(hours) ?? "—"),
                "REM " + (t.remMin.map(hours) ?? "—"),
                "light " + (t.lightMin.map(hours) ?? "—"),
                "efficiency " + (efficiencyPercent(t.efficiency) ?? "—"),
            ]
            night += " (" + stages.joined(separator: ", ") + ")"
        }
        lines.append(night)
        let vitals: [String] = [
            "RHR " + reading(t.restingHR, today: t.day, bpm),
            "HRV " + reading(t.hrv, today: t.day, milliseconds),
            "SpO2 " + reading(t.spo2, today: t.day, percent),
            "respiration " + reading(t.respiration, today: t.day, perMinute),
            "skin-temp deviation " + reading(t.skinTempDev, today: t.day, degrees),
        ]
        lines.append("  " + vitals.joined(separator: ", "))
        var energy = "  steps " + (t.steps.map { "\($0)" } ?? missing)
        if let rest = t.restingKcal, let act = t.activityKcal {
            energy += ", calories so far \(Int((rest + act).rounded())) kcal (resting \(Int(rest.rounded())), "
                + "activity \(Int(act.rounded())); estimated from heart rate)"
        } else {
            energy += ", calories not measured"
        }
        lines.append(energy)
        return lines.joined(separator: "\n")
    }

    /// Last night against the user's own normal: the band the Charge score is scored against (absent
    /// while it calibrates) and the range of the last 30 nights, the two things the Today half-gauges draw.
    static func normalsBlock(restingHR: TodayVitalRange.Gauge?, restingHRNormal: ClosedRange<Double>?,
                             hrv: TodayVitalRange.Gauge?, hrvNormal: ClosedRange<Double>?,
                             sleep: Sleep?) -> String {
        var lines: [String] = []
        if let g = restingHR { lines.append("  RHR: " + gaugeLine(g, normal: restingHRNormal, unit: "bpm")) }
        if let g = hrv { lines.append("  HRV: " + gaugeLine(g, normal: hrvNormal, unit: "ms")) }
        if let sleep, let last = sleep.lastNightMin {
            var line = "  sleep: last night " + hours(last)
            if let avg = sleep.average30Min { line += ", 30-night average " + hours(avg) }
            lines.append(line)
        }
        guard !lines.isEmpty else { return "" }
        return (["YOUR NORMALS (compare with these, not with population norms):"] + lines).joined(separator: "\n")
    }

    static func sleepBlock(_ s: Sleep) -> String {
        var parts: [String] = []
        if let need = s.needMin { parts.append("sleep need " + duration(need)) }
        if let debt = s.debtMin {
            parts.append("sleep debt " + (s.isDebt ? duration(debt) : "none"))
        }
        if let short = s.lastShortfallMin, short >= 1 { parts.append("last night short by " + duration(short)) }
        var second: [String] = []
        if let wake = s.usualWakeMin {
            second.append("usual wake-up " + clockText(wake) + " (median of the last 14 nights)")
            if let need = s.needMin {
                second.append("suggested bedtime " + clockText(HabitualWake.bedtime(wakeMinutes: wake, needMinutes: need)))
            }
        } else {
            second.append("usual wake-up not known yet (needs 3 nights)")
        }
        var lines = ["SLEEP (the Sleep tab's figures):"]
        if !parts.isEmpty { lines.append("  " + parts.joined(separator: ", ")) }
        lines.append("  " + second.joined(separator: ", "))
        return lines.joined(separator: "\n")
    }

    /// The Lift Log's own verdict per exercise (`LiftProgress`), attention first, and the muscles it
    /// would prioritise. "" when nothing has been logged.
    static func progressionBlock(exercises: [LiftProgress.Exercise], priorities: [LiftProgress.Priority],
                                 system: UnitSystem) -> String {
        guard !exercises.isEmpty else { return "" }
        let unit = LiftFormat.weightUnit(system)
        let sorted = exercises.sorted {
            $0.status.rank != $1.status.rank ? $0.status.rank < $1.status.rank
                : $0.name.localizedCompare($1.name) == .orderedAscending
        }
        var lines = ["LIFT PROGRESSION (the app's own rules, per exercise; a record is a heavier load or more reps at a load):"]
        for exercise in sorted.prefix(maxExercises) {
            lines.append("  \(exercise.name): " + statusText(exercise.status, unit: unit, system: system))
        }
        if sorted.count > maxExercises { lines.append("  … \(sorted.count - maxExercises) more") }
        if !priorities.isEmpty {
            let named = priorities.map { p -> String in
                var reasons: [String] = []
                if p.belowReference { reasons.append("\(one(p.setsPerWeek)) sets/week, under 4") }
                if !p.stuckExercises.isEmpty {
                    reasons.append("stalled or declining: " + p.stuckExercises.joined(separator: ", "))
                }
                let name = CoachLiftContext.muscleName(p.muscle)
                return reasons.isEmpty ? name : name + " (" + reasons.joined(separator: "; ") + ")"
            }
            lines.append("  muscles to prioritise (last 4 weeks): " + named.joined(separator: "; "))
        }
        return lines.joined(separator: "\n")
    }

    static func statusText(_ status: LiftProgress.Status, unit: String, system: UnitSystem) -> String {
        switch status {
        case .notEnough(let n):
            return "not enough sessions yet (\(n)/\(LiftProgress.minimumSessions))"
        case .ready(let from, let to):
            return "ready to go up (\(CoachLiftContext.weight(from, system: system)) → "
                + "\(CoachLiftContext.weight(to, system: system)) \(unit))"
        case .declining(let percent):
            return "declining (last e1RM \(Int(abs(percent).rounded()))% under its best)"
        case .stalled(let n):
            return "stalled (\(n) session\(n == 1 ? "" : "s") without a record)"
        case .progressing:
            return "progressing (a record in the last \(LiftProgress.minimumSessions) sessions)"
        }
    }

    // MARK: Formatting

    /// Last night, the normal band (unclamped) and where last night sits in it, then the 30-night range.
    static func gaugeLine(_ g: TodayVitalRange.Gauge, normal: ClosedRange<Double>?, unit: String) -> String {
        var line = "last night \(Int(g.value.rounded())) \(unit)"
        if let band = normal {
            line += ", your normal \(Int(band.lowerBound.rounded()))–\(Int(band.upperBound.rounded()))"
            if g.value < band.lowerBound { line += " (below it)" }
            else if g.value > band.upperBound { line += " (above it)" }
            else { line += " (within it)" }
        } else {
            line += ", normal not formed yet (calibrating)"
        }
        line += ", last 30 nights \(Int(g.low.rounded()))–\(Int(g.high.rounded()))"
        return line
    }

    private static func bpm(_ v: Double) -> String { "\(Int(v.rounded())) bpm" }
    private static func milliseconds(_ v: Double) -> String { "\(Int(v.rounded())) ms" }
    private static func percent(_ v: Double) -> String { "\(Int(v.rounded()))%" }
    private static func perMinute(_ v: Double) -> String { one(v) + "/min" }
    private static func degrees(_ v: Double) -> String { signed(v) + "°C" }

    private static func reading(_ r: Reading?, today: String, _ format: (Double) -> String) -> String {
        guard let r else { return "not measured" }
        return r.day == today ? format(r.value) : format(r.value) + " (from \(r.day))"
    }

    /// Efficiency as a percentage; the stored value is a fraction on some paths and a percentage on
    /// others (the same `> 1.5` guard `AICoachEngine.efficiencyPercentOrDash` applies).
    static func efficiencyPercent(_ raw: Double?) -> String? {
        guard var e = raw, e > 0 else { return nil }
        if e > 1.5 { e /= 100 }
        guard e <= 1 else { return nil }
        return "\(Int((e * 100).rounded()))%"
    }

    static func hours(_ minutes: Double) -> String { String(format: "%.1fh", minutes / 60) }

    /// "2h 23m", "45m".
    static func duration(_ minutes: Double) -> String {
        let total = max(0, Int(minutes.rounded()))
        let h = total / 60, m = total % 60
        return h > 0 ? "\(h)h \(String(format: "%02d", m))m" : "\(m)m"
    }

    /// "07:05" for minutes after midnight, always 24-hour: the coach reads it, not the user.
    static func clockText(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    static func one(_ value: Double) -> String { String(format: "%.1f", value) }

    static func signed(_ value: Double) -> String { String(format: "%+.1f", value) }
}
