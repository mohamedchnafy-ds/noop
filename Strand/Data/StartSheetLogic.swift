import Foundation

// Personal fork (mockup « Démarrer », 4 Nov.): what the « Start » sheet opened by Today's « + » offers.
// Pure: the Training snapshot's days, programs and activities go in, the rows the sheet draws come out.

/// Something planned today and still to do, as the sheet lists it: a program, or cardio.
enum StartSheetPlanned: Equatable {
    case program(TrainingProgramSummary)
    case cardio(sport: String, minutes: Int)
}

enum StartSheetLogic {
    /// How far back the sport grid counts activities.
    static let sportWindowDays = 90
    /// How many sports the grid shows (« Other sport… » comes after them).
    static let sportGridCount = 5
    /// Strength sports stay out of the live cardio grid: a Lift Log session is started from its own row.
    static let strengthSportNames: Set<String> = ["Strength", "Bodybuilding", "Weightlifting"]
    /// The grid's filling when the history and the recents name fewer sports than it shows.
    static let defaultSportNames = ["Running", "Walking", "Cycling", "Elliptical", "Treadmill walk",
                                    "Indoor cycle", "Row machine"]

    /// Today's planned items still to do, as the Training screen's day card lists them: the programs that
    /// still exist first, then cardio, each in the plan's order. Empty when nothing is planned or all of it
    /// is done.
    static func startPlannedRows(day: TrainingDay?, programs: [TrainingProgramSummary]) -> [StartSheetPlanned] {
        guard let day, day.isToday else { return [] }
        let open = day.openItems
        var rows: [StartSheetPlanned] = open.compactMap { item in
            guard let id = item.programId else { return nil }
            return programs.first(where: { $0.id == id }).map(StartSheetPlanned.program)
        }
        rows += open.compactMap { item in
            if case .cardio(let sport, let minutes) = item { return .cardio(sport: sport, minutes: minutes) }
            return nil
        }
        return rows
    }

    /// The programs a session can start from: the ones with at least one line, in the order given.
    static func startablePrograms(_ programs: [TrainingProgramSummary]) -> [TrainingProgramSummary] {
        programs.filter { $0.blockCount > 0 }
    }

    /// The live cardio grid: the catalogue sports done most over the last `sportWindowDays` days (most
    /// sessions first, then the most recent, then the name), then the recent picks, then the defaults, up
    /// to `count`, each once. Strength sports and « Other » are left out; so is a label the catalogue does
    /// not know, since the grid starts a live workout under the catalogue's stored name.
    static func startSportGrid(activities: [TrainingActivityDone], recent: [String], now: Date,
                               count: Int = sportGridCount) -> [String] {
        let from = Int(now.timeIntervalSince1970) - sportWindowDays * 86_400
        func catalogueName(_ label: String) -> String? {
            guard let name = WorkoutCatalog.sport(named: WorkoutSource.editableSport(label))?.name,
                  name != WorkoutCatalog.defaultSportName, !strengthSportNames.contains(name) else { return nil }
            return name
        }
        var tally: [String: (sessions: Int, latest: Int)] = [:]
        for activity in activities where activity.startTs >= from {
            guard let name = catalogueName(activity.sport) else { continue }
            let seen = tally[name] ?? (sessions: 0, latest: 0)
            tally[name] = (sessions: seen.sessions + 1, latest: max(seen.latest, activity.startTs))
        }
        var grid = tally.sorted { a, b in
            if a.value.sessions != b.value.sessions { return a.value.sessions > b.value.sessions }
            if a.value.latest != b.value.latest { return a.value.latest > b.value.latest }
            return a.key < b.key
        }.map(\.key)
        for name in recent.compactMap(catalogueName) + defaultSportNames where !grid.contains(name) {
            grid.append(name)
        }
        return Array(grid.prefix(max(0, count)))
    }

    /// Sessions done over the days given (a week): every Lift Log session and every other activity.
    static func sessionsThisWeek(_ days: [TrainingDay]) -> Int {
        days.reduce(0) { $0 + $1.lifts.count + $1.activities.count }
    }
}
