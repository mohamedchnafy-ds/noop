import Foundation
import WhoopStore
import StrandImport

// MARK: - The Coach's read tools, run on the device (personal fork)
//
// What each `CoachTools.Name` reads. The rows come from the same sources the fiche and the screens use
// (`repo.days`, `repo.workoutRows`, the Lift Log store, the Journal, the Lab Book), so a tool and the
// screen it mirrors cannot disagree; the wording lives in `CoachTools`.

extension AICoachEngine {

    /// The answer to one tool call, as text for the model. Never throws: a missing store or a bad input
    /// becomes a sentence the model can act on.
    func runTool(_ name: CoachTools.Name, input: [String: Any], now: Date = Date()) async -> String {
        // Re-checked at the call: the switch can be turned off while an answer is on its way.
        guard dataConsent else {
            return "No data access: the user turned off “Use my data”. Answer without their figures."
        }
        let system = UnitSystem(
            rawValue: UserDefaults.standard.string(forKey: UnitPrefs.systemKey) ?? "") ?? .metric
        switch name {
        case .metricHistory:
            guard let metric = CoachTools.text(input, "metric").flatMap(CoachTools.Metric.init(rawValue:)) else {
                return "Unknown metric. Use one of: "
                    + CoachTools.Metric.allCases.map(\.rawValue).joined(separator: ", ") + "."
            }
            let days = CoachTools.integer(input, "days", fallback: 30, in: CoachTools.dayRange)
            let byDay = Dictionary(repo.days.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
            return CoachTools.metricHistory(metric, dayKeys: CoachTools.dayKeys(days: days, endingAt: now),
                                            byDay: byDay)

        case .night:
            guard let day = CoachTools.text(input, "date"), let date = Self.toolDayFormatter.date(from: day) else {
                return "Give the night as the date it ended, YYYY-MM-DD."
            }
            let back = max(Calendar.current.dateComponents([.day], from: date, to: now).day ?? 0, 0)
            guard back <= 400 else { return "That night is more than 400 days ago." }
            let sessions = await repo.allSleepSessions(days: back + 2)
            let periods = sessions
                .filter { Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0.endTs))) == day }
                .map { (start: $0.effectiveStartTs, end: $0.endTs) }
            return CoachTools.night(day: day, metric: repo.days.last { $0.day == day }, periods: periods,
                                    timeZone: .current)

        case .workouts:
            let days = CoachTools.integer(input, "days", fallback: 30, in: CoachTools.dayRange)
            let distanceSystem = UnitPrefs.resolveDistance(
                system: system, override: UserDefaults.standard.string(forKey: UnitPrefs.distanceSystemKey) ?? "")
            let rows = await repo.workoutRows(days: days).prefix(60).map { w in
                CoachTools.Workout(day: Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(w.startTs))),
                                   sport: w.sport,
                                   durationMin: w.durationS.map { Int(($0 / 60).rounded()) },
                                   effort: w.strain, avgHr: w.avgHr, maxHr: w.maxHr,
                                   kcal: w.energyKcal.map { Int($0.rounded()) },
                                   distance: w.distanceM.map { UnitFormatter.distanceFromMeters($0, system: distanceSystem) })
            }
            return CoachTools.workouts(Array(rows), days: days)

        case .exerciseHistory:
            guard let query = CoachTools.text(input, "exercise") else { return "Name the exercise." }
            guard let store = await repo.storeHandle() else { return "The Lift Log cannot be read right now." }
            let limit = CoachTools.integer(input, "sessions", fallback: 8, in: CoachTools.sessionRange)
            let to = Int(now.timeIntervalSince1970)
            let from = to - CoachTools.exerciseLookbackDays * 86_400
            var sessions: [CoachTools.LiftSession] = []
            for row in (try? await store.liftSessions(deviceId: repo.deviceId, fromTs: from, toTs: to)) ?? [] {
                sessions.append(.init(startTs: row.startTs, programName: row.programName,
                                      sets: (try? await store.liftSets(sessionId: row.id)) ?? []))
            }
            return CoachTools.exerciseHistory(query: query, sessions: sessions, limit: limit, system: system) {
                Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0)))
            }

        case .programs:
            guard let store = await repo.storeHandle() else { return "The Lift Log cannot be read right now." }
            var programs: [CoachTools.Program] = []
            for row in (try? await store.liftPrograms(deviceId: repo.deviceId)) ?? [] {
                programs.append(.init(row: row, items: (try? await store.liftProgramItems(programId: row.id)) ?? []))
            }
            return CoachTools.programs(programs, system: system)

        case .journal:
            let days = CoachTools.integer(input, "days", fallback: 30, in: CoachTools.journalDayRange)
            return CoachTools.journal(await repo.journalEntries(days: days), days: days)

        case .labBook:
            guard includeOnDeviceSignals else {
                return "The Lab Book is not shared: “Trends and Lab Book” is off."
            }
            guard let store = await repo.storeHandle() else { return "The Lab Book cannot be read right now." }
            var values: [CoachTools.LabValue] = []
            for category in LabMarkerCategory.allCases {
                for row in (try? await store.labMarkers(deviceId: repo.deviceId, category: category.rawValue)) ?? [] {
                    let name = MarkerCatalog.definition(for: row.markerKey)?.displayName ?? row.markerKey
                    let value = row.value.map { "\(LabBookFormat.value($0, key: row.markerKey)) \(row.unit)" }
                        ?? row.valueText ?? "—"
                    values.append(.init(marker: name, day: row.day, value: value))
                }
            }
            return CoachTools.labBook(values)
        }
    }

    /// Reads the `date` a tool is given, in the local calendar like every day key of the app.
    static let toolDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
