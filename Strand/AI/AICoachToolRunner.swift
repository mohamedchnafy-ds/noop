import Foundation
import WhoopStore
import StrandImport
import StrandAnalytics

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
            let keys = CoachTools.dayKeys(days: days, endingAt: now)
            guard metric.isDailyRow else {
                let values = await seriesValues(metric, days: days, now: now)
                return CoachTools.metricHistory(metric, dayKeys: keys, values: values)
            }
            let byDay = Dictionary(repo.days.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
            return CoachTools.metricHistory(metric, dayKeys: keys, byDay: byDay)

        case .night:
            guard let day = CoachTools.text(input, "date"), let date = Self.toolDayFormatter.date(from: day) else {
                return "Give the night as the date it ended, YYYY-MM-DD."
            }
            let back = max(Calendar.current.dateComponents([.day], from: date, to: now).day ?? 0, 0)
            guard back <= 400 else { return "That night is more than 400 days ago." }
            let sessions = await repo.allSleepSessions(days: back + 2)
            let ending = sessions
                .filter { Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0.endTs))) == day }
            let periods = ending.map { (start: $0.effectiveStartTs, end: $0.endTs) }
            // The Sleep screen's curves (`SleepView`): 1-minute sleeping HR from the session start, windowed
            // rMSSD from the effective start, read per period and grouped by `CoachTools.night`.
            var heartRate: [HRBucket] = []
            var hrv: [(ts: Int, value: Double)] = []
            for session in ending {
                let beats = await repo.hrBuckets(from: session.startTs, to: session.endTs, bucketSeconds: 60)
                let rmssd = await repo.timelineSeries(metric: .hrv, from: session.effectiveStartTs, to: session.endTs,
                                                      targetPoints: 240)
                heartRate.append(contentsOf: beats)
                hrv.append(contentsOf: rmssd.points.map { (ts: Int($0.date.timeIntervalSince1970), value: $0.value) })
            }
            return CoachTools.night(day: day, metric: repo.days.last { $0.day == day }, periods: periods,
                                    timeZone: .current, heartRate: heartRate, hrv: hrv)

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
                                   distance: w.distanceM.map { UnitFormatter.distanceFromMeters($0, system: distanceSystem) },
                                   start: Self.toolClockFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(w.startTs))),
                                   enteredByHand: WorkoutSource.classify(w.source) == .manual)
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

        case .meals:
            let days = CoachTools.integer(input, "days", fallback: 7, in: CoachTools.mealDayRange)
            guard let store = await repo.storeHandle() else { return "The meal journal cannot be read right now." }
            let keys = CoachTools.dayKeys(days: days, endingAt: now)
            guard let from = keys.first, let to = keys.last else { return "No days asked for." }
            let entries = (try? await MealJournal.mealJournalRange(store, fromDay: from, toDay: to)) ?? []
            let byDay = Dictionary(grouping: entries, by: { $0.meal.day })
            let mealDays = keys.map { key in
                CoachTools.MealDay(day: key, meals: (byDay[key] ?? []).map { entry in
                    CoachTools.MealDay.Meal(
                        time: Self.toolClockFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(entry.meal.eatenAt))),
                        name: entry.meal.name, nutrients: entry.mealTotals, slot: entry.mealSlot.rawValue,
                        fromCoachMenu: entry.isCoachMenuMeal)
                })
            }
            return CoachTools.meals(mealDays, from: from, to: to)

        case .dayHeartRate:
            let calendar = Calendar.current
            var date = now
            if let text = CoachTools.text(input, "date") {
                guard let asked = Self.toolDayFormatter.date(from: text) else {
                    return "Give the day as YYYY-MM-DD."
                }
                let back = calendar.dateComponents([.day], from: calendar.startOfDay(for: asked),
                                                   to: calendar.startOfDay(for: now)).day ?? 0
                guard back >= 0 else { return "That day has not happened yet." }
                guard back <= CoachTools.dayHeartRateLookbackDays else {
                    return "That day is more than \(CoachTools.dayHeartRateLookbackDays) days ago."
                }
                date = asked
            }
            // The Today card's own window and read: local midnight to now (today) or to the next midnight.
            let dayStart = calendar.startOfDay(for: date)
            let from = Int(dayStart.timeIntervalSince1970)
            let isToday = calendar.isDate(date, inSameDayAs: now)
            let to = isToday ? Int(now.timeIntervalSince1970)
                : Int((calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart).timeIntervalSince1970)
            let dayKey = Repository.localDayKey(dayStart)
            let buckets = await repo.hrBuckets(from: from, to: to, bucketSeconds: 300)
            let samples = await repo.hrSamples(from: from, to: to, limit: 200_000)
            let profile = self.profile ?? ProfileStore()
            let zoneSet = profile.hrZoneSet
            // A day is 170k+ samples: binned off the main actor, as Today scores its Effort.
            let zones = await Task.detached(priority: .utility) {
                samples.isEmpty ? nil : HRZones.timeInZone(samples, zoneSet: zoneSet)
            }.value
            let sleep = await repo.allSleepSessions(days: max(2, (Int(now.timeIntervalSince1970) - from) / 86_400 + 2))
                .map { $0.effectiveStartTs...max($0.effectiveStartTs, $0.endTs) }
                .filter { $0.upperBound > from && $0.lowerBound < to }
                .map { max($0.lowerBound, from)...min($0.upperBound, to) }
            return CoachTools.dayHeartRate(day: dayKey, buckets: buckets, sleep: sleep,
                                           restingHR: repo.days.last { $0.day == dayKey }?.restingHr.map(Double.init),
                                           zones: zones, hrMax: Int(zoneSet.maxHR.rounded()),
                                           timeZone: .current)

        case .caffeine:
            let store = CaffeineLogStore.shared
            return CoachTools.caffeine(store.intakes, estimate: store.estimate(), now: now, timeZone: .current)

        case .series:
            // Read through the charts' reader (chantier 9), so a series read here and shown by show_chart agree.
            let calendar = Calendar.current
            guard let spec = CoachTools.seriesSpec(input, today: CoachChart.dayKey(now, calendar: calendar)) else {
                return "Unknown series. Use one of the ids listed in the tool."
            }
            let points = await chartPoints(spec, now: now)
            return CoachTools.seriesResult(spec, points: points.first, calendar: calendar)
        }
    }

    /// One value per day of a series-backed metric, read where its screen reads it: the Apple Health weight
    /// series (Today's weight tile), the water tracker's day totals (`hydrationHistory`, a day with nothing
    /// logged left out rather than read as zero) and the Stress screen's daily history (`StressModel`).
    private func seriesValues(_ metric: CoachTools.Metric, days: Int, now: Date) async -> [String: Double] {
        switch metric {
        case .weight:
            let points = await repo.series(key: "weight", source: "apple-health", days: days + 1)
            return Dictionary(points.map { ($0.day, $0.value) }, uniquingKeysWith: { _, last in last })
        case .water:
            let points = await repo.hydrationHistory(days: days, now: now).filter { $0.value > 0 }
            return Dictionary(points.map { ($0.day, $0.value) }, uniquingKeysWith: { _, last in last })
        case .stress:
            let stored = await repo.series(key: "stress", source: "my-whoop")
            guard let model = StressModel(days: repo.days, stored: stored) else { return [:] }
            return Dictionary(model.fullTrend.map { (Self.stressDayFormatter.string(from: $0.date), $0.value) },
                              uniquingKeysWith: { _, last in last })
        default:
            return [:]
        }
    }

    /// Writes the Stress screen's trend dates back as day keys: `StressModel` parses its days in UTC.
    static let stressDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Writes a meal's time for a tool result, "HH:mm" in the local time zone.
    static let toolClockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// Reads the `date` a tool is given, in the local calendar like every day key of the app.
    static let toolDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
