import Foundation
import StrandAnalytics
import StrandDesign
import WhoopStore

// Personal fork, chantier 6: what the three day widgets say, worded and formatted app-side (the widget
// extension has no catalog), from the funnels the screens read — today's session from
// `TodaySessionResolver` (the Synthèse), the week from `TrainingDays.buildTrainingDays` (the Training
// calendar), the meals from `NutritionDaySummary` and `NutritionDayReader.currentPlan` (Nutrition and the
// Coach), the night from `LiveHRBannerFigures.nightSleepMinutes` (Today's Rest ring) and the debt and the
// bedtime from `Repository.sleepSynthesisFigures` (the Synthèse). Pure, so `StrandTests` covers it; the iOS
// app gathers the inputs (`DayWidgetsSnapshot.publishDayWidgets`).

enum DayWidgetsContent {

    // MARK: - The day

    /// The snapshot of the logical day starting at `dayStart`, valid until that day ends.
    static func daySnapshot(dayStart: Date, calendar: Calendar, session: DayWidgetsSnapshot.Session?,
                            nutrition: DayWidgetsSnapshot.Nutrition?,
                            sleep: DayWidgetsSnapshot.Sleep?, rings: DayWidgetsSnapshot.Rings? = nil,
                            heart: DayWidgetsSnapshot.Heart? = nil,
                            stress: DayWidgetsSnapshot.Stress? = nil) -> DayWidgetsSnapshot {
        DayWidgetsSnapshot(dayKey: Repository.localDayKey(dayStart),
                           validUntil: dayWidgetsValidUntil(dayStart: dayStart, calendar: calendar),
                           session: session, nutrition: nutrition, sleep: sleep, labels: widgetLabels(),
                           rings: rings, heart: heart, stress: stress, words: widgetWords())
    }

    /// When the logical day starting at `dayStart` ends: the next calendar midnight plus the app's rollover
    /// hour (`Repository.logicalDayRolloverHour`).
    static func dayWidgetsValidUntil(dayStart: Date, calendar: Calendar,
                                     rolloverHour: Int = Repository.logicalDayRolloverHour) -> Date {
        let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: dayStart))
            ?? dayStart.addingTimeInterval(86_400)
        return next.addingTimeInterval(TimeInterval(rolloverHour * 3_600))
    }

    /// The words the widgets need beyond the figures.
    static func widgetLabels() -> DayWidgetsSnapshot.Labels {
        DayWidgetsSnapshot.Labels(
            sessionTitle: String(localized: "Today's session"),
            nutritionTitle: String(localized: "Nutrition"),
            sleepTitle: String(localized: "Sleep"),
            sessionAbout: String(localized: "Today's session from your week plan, and your week at a glance."),
            nutritionAbout: String(localized: "What you ate today against your goals."),
            sleepAbout: String(localized: "Last night, your sleep debt and the suggested bedtime."),
            open: String(localized: "Open"),
            noData: String(localized: "no data"),
            protein: String(localized: "Protein"),
            carbs: String(localized: "Carbs"),
            fat: String(localized: "Fat"))
    }

    /// `sentence` split around `value`, wherever the language put it ("dette 1h 12m", "昨晚 …"). A sentence
    /// that does not contain it is kept whole, with nothing set apart.
    static func emphasis(_ sentence: String, value: String) -> DayWidgetsSnapshot.Emphasis {
        guard !value.isEmpty, let range = sentence.range(of: value) else {
            return .init(before: sentence, value: "", after: "")
        }
        return .init(before: String(sentence[..<range.lowerBound]), value: value,
                     after: String(sentence[range.upperBound...]))
    }

    /// Where a widget's tap leads in the app.
    static func widgetRoute(_ link: DayWidgetsSnapshot.Link) -> TabRoute {
        switch link {
        case .session: return .liftLog
        case .nutrition: return .nutrition
        case .sleep: return .sleep
        }
    }

    // MARK: - Today's session

    /// "Today's session": the Synthèse's session and line, the program's first two blocks, and this week's
    /// strip with the sessions done for the days planned. `today` is the logical day's start.
    static func sessionSection(_ resolution: TodaySessionResolution, today: Date,
                               calendar: Calendar) -> DayWidgetsSnapshot.Session {
        let session = resolution.session
        let line = session == nil ? nil : TodaySynthesisLogic.sessionRow(session, route: nil).subtitle
        var lineMedium = line
        if session?.state == .next {
            lineMedium = [line, String(localized: "planned")].compactMap { $0 }.joined(separator: " · ")
        }
        // Fork chantier 18: the lines left out for today from the Training day card are not shown.
        let blocks = resolution.programId.map { id in
            let leftOut = LiftDayAdditions.removedLineIds(day: TrainingCalendar.trainingDayKey(today, calendar: calendar),
                                                          programId: id)
            return TrainingDays.programSummary(id: id, name: session?.name ?? "",
                                               items: LiftDayAdditions.keptProgramLines(resolution.programItems,
                                                                                        removed: leftOut),
                                               finished: []).blocks.map(\.text)
        } ?? []
        let days = widgetWeekDays(resolution, today: today, calendar: calendar)
        let letters = DateFormatter()
        letters.locale = AppLanguage.activeLocale
        let symbols = letters.veryShortStandaloneWeekdaySymbols ?? []
        let tally = TrainingDays.sessionTally(days)
        let tallyText = tally.planned > 0 ? "\(tally.done)/\(tally.planned)" : nil
        return DayWidgetsSnapshot.Session(
            name: session?.name,
            state: session.map { sessionState($0.state) },
            line: line,
            lineMedium: lineMedium,
            blocks: blocks.isEmpty ? nil : blocks,
            week: days.map { day -> DayWidgetsSnapshot.WeekDay in
                let index = calendar.component(.weekday, from: day.date) - 1
                return DayWidgetsSnapshot.WeekDay(letter: symbols.indices.contains(index) ? symbols[index] : "",
                                                  mark: weekMark(day), isToday: day.isToday)
            },
            tally: tallyText,
            weekLine: tallyText.map { String(localized: "This week") + " " + $0 },
            rows: widgetSessionRows(resolution, week: days, calendar: calendar),
            dayLine: widgetDayLine(today, calendar: calendar),
            weekDone: weekDoneLine(days))
    }

    static func sessionState(_ state: TodaySynthesisLogic.Session.State) -> DayWidgetsSnapshot.Session.State {
        switch state {
        case .next: return .next
        case .running: return .running
        case .done: return .done
        case .rest: return .rest
        }
    }

    /// Monday to Sunday of `today`'s week, built by the Training calendar's own rule from the resolver's
    /// sessions (finished, with a working set) and its other activities.
    static func widgetWeekDays(_ resolution: TodaySessionResolution, today: Date,
                               calendar: Calendar) -> [TrainingDay] {
        let lifts = resolution.performed.compactMap { entry -> TrainingLiftDone? in
            guard let end = entry.row.endTs else { return nil }
            return TrainingLiftDone(sessionId: entry.row.id, programId: entry.row.programId,
                                    name: entry.row.programName ?? "", startTs: entry.row.startTs, endTs: end,
                                    workingSets: entry.workingSets, effort: nil)
        }
        let activities = resolution.otherWorkouts.map { row in
            TrainingActivityDone(sport: row.sport, source: row.source, startTs: row.startTs, endTs: row.endTs,
                                 kcal: nil)
        }
        let monday = TrainingCalendar.mondayOf(today, calendar: calendar)
        return TrainingDays.buildTrainingDays(TrainingCalendar.weekDates(from: monday, calendar: calendar),
                                              plan: resolution.plan, lifts: lifts, activities: activities,
                                              now: today, calendar: calendar)
    }

    /// One mark per day, by priority: a lift done, a lift still planned, a lift missed, then cardio.
    static func weekMark(_ day: TrainingDay) -> DayWidgetsSnapshot.Mark {
        if day.hasLift { return .done }
        if day.isPlannedOpen { return .planned }
        if day.isMissed { return .missed }
        if day.hasActivity { return .cardio }
        return .none
    }

    // MARK: - Nutrition

    /// "Nutrition": the day's meals against the intake goal and the macro goals, and the balance with the
    /// energy measured.
    static func nutritionSection(_ day: NutritionDaySummary, plan: NutritionGoals.Plan) -> DayWidgetsSnapshot.Nutrition {
        let eaten = day.eaten
        func share(_ value: Double, of goal: Int?) -> Double? {
            guard let goal, goal > 0 else { return nil }
            return value / Double(goal)
        }
        func macro(_ grams: Double, goal: Int?) -> DayWidgetsSnapshot.Macro {
            DayWidgetsSnapshot.Macro(eaten: NutritionFormat.grams(grams),
                                     rest: goal.map { "/ " + NutritionFormat.gramsUnit($0) } ?? "g",
                                     fraction: share(grams, of: goal))
        }
        let goal: Int? = plan.intakeKcal
        let balance = day.balanceKcal.map { kcal -> DayWidgetsSnapshot.Emphasis in
            let value = NutritionFormat.signedKcal(kcal)
            return emphasis(String(localized: "balance \(value)"), value: value)
        }
        let count = day.meals.count
        let figures = nutritionFigures(day, plan: plan)
        return DayWidgetsSnapshot.Nutrition(
            eaten: NutritionFormat.whole(eaten.kcal),
            goalShort: goal.map { "/ " + NutritionFormat.kcalUnit($0) } ?? String(localized: "kcal"),
            goalLong: goal.map { "/ " + NutritionFormat.whole($0) + " " + String(localized: "kcal eaten") }
                ?? String(localized: "kcal eaten"),
            fraction: share(Double(eaten.kcal), of: goal),
            balance: balance,
            meals: count == 1 ? String(localized: "1 meal") : String(localized: "\(count) meals"),
            protein: macro(eaten.proteinG, goal: plan.proteinG),
            carbs: macro(eaten.carbsG, goal: plan.carbsG),
            fat: macro(eaten.fatG, goal: plan.fatG),
            left: figures.left, spent: figures.spent, net: figures.net)
    }

    // MARK: - Sleep

    /// "Sleep": the night Today's Rest ring names, the Synthèse's debt and bedtime, the usual wake-up, and
    /// the onset, end and phases of the night the widget draws.
    static func sleepSection(nightMinutes: Double?, figures: SleepSynthesisFigures?,
                             night: CachedSleepSession?) -> DayWidgetsSnapshot.Sleep {
        let formatter = AppClock.hourMinuteFormatter()
        func nightClock(_ ts: Int) -> String { formatter.string(from: Date(timeIntervalSince1970: TimeInterval(ts))) }
        let phases = night.map {
            widgetPhases(AnalyticsEngine.decodeStages($0.stagesJSON), from: $0.effectiveStartTs, to: $0.endTs)
        } ?? []
        return DayWidgetsSnapshot.Sleep(
            night: nightMinutes.map { SleepDurationText.format($0) },
            debt: figures?.debtText.map { debt in emphasis(String(localized: "debt \(debt)"), value: debt) },
            bedtime: figures?.bedtimeMin.map { minutes in
                DayWidgetsSnapshot.Emphasis(before: String(localized: "Suggested bedtime") + " ",
                                            value: TodaySynthesisLogic.clock(minutes), after: "")
            },
            usualWake: figures?.usualWakeMin.map { wake in
                String(localized: "usual wake-up \(TodaySynthesisLogic.clock(wake))")
            },
            start: night.map { nightClock($0.effectiveStartTs) },
            end: night.map { nightClock($0.endTs) },
            phases: phases.isEmpty ? nil : phases,
            stages: phases.isEmpty ? nil : stageTotals(phases))
    }

    /// The night the medium widget draws: the longest sleep that ended in the 24 hours before `now`.
    static func widgetNight(_ sleeps: [CachedSleepSession], now: Date) -> CachedSleepSession? {
        let nowTs = Int(now.timeIntervalSince1970)
        return sleeps
            .filter { $0.endTs <= nowTs && $0.endTs > nowTs - 86_400 && $0.endTs > $0.effectiveStartTs }
            .max { ($0.endTs - $0.effectiveStartTs) < ($1.endTs - $1.effectiveStartTs) }
    }

    /// The hypnogram inside `start…end`, consecutive stretches of one stage merged, in whole minutes. Any
    /// stage but light, deep and REM reads as awake.
    static func widgetPhases(_ segments: [StageSegment], from start: Int, to end: Int) -> [DayWidgetsSnapshot.Phase] {
        var stretches: [(stage: String, seconds: Int)] = []
        for segment in segments.sorted(by: { $0.start < $1.start }) {
            let lower = max(segment.start, start), upper = min(segment.end, end)
            guard upper > lower else { continue }
            let stage = ["light", "deep", "rem"].contains(segment.stage) ? segment.stage : "wake"
            if let last = stretches.last, last.stage == stage {
                stretches[stretches.count - 1].seconds += upper - lower
            } else {
                stretches.append((stage, upper - lower))
            }
        }
        return stretches
            .map { DayWidgetsSnapshot.Phase(stage: $0.stage, minutes: Int((Double($0.seconds) / 60).rounded())) }
            .filter { $0.minutes > 0 }
    }
}

// MARK: - Widgets v2 (5 Nov.)

// What the redesigned widgets add: the session's planned items one per line with their Start, the week's
// tally in words, Nutrition's three figures, the night's stage totals, Today's four rings, the heart-rate
// thresholds of the day and the stress card, each from the funnel the Today, Nutrition and Sleep screens read.
extension DayWidgetsContent {

    /// The words the widgets draw beyond their figures, keyed by their English text.
    static func widgetWords() -> [String: String] {
        [
            "Heart rate": String(localized: "Heart rate"),
            "Last 3 hours": String(localized: "Last 3 hours"),
            "bpm": String(localized: "bpm"),
            "Min": String(localized: "Min"),
            "Avg": String(localized: "Avg"),
            "Max": String(localized: "Max"),
            "Stress": String(localized: "Stress"),
            "Calm": String(localized: "Calm"),
            "Moderate": String(localized: "Moderate"),
            "High": String(localized: "High"),
            "Peak": String(localized: "Peak"),
            "moving": String(localized: "moving"),
            "this hour": String(localized: "this hour"),
            "Start": String(localized: "Start"),
            "Nothing planned": String(localized: "Nothing planned"),
            "Left": String(localized: "Left"),
            "Spent": String(localized: "Spent"),
            "Net": String(localized: "Net"),
        ]
    }

    /// « high 114 » / « low 68 » as the heart-rate card's legend words them, split around the number so the
    /// widget puts in its own: the catalogue's sentence is worded once with a stand-in figure.
    static func heartLineLabels() -> (high: DayWidgetsSnapshot.Emphasis, low: DayWidgetsSnapshot.Emphasis) {
        let standIn = 987_654
        return (emphasis(String(localized: "high \(standIn)"), value: "\(standIn)"),
                emphasis(String(localized: "low \(standIn)"), value: "\(standIn)"))
    }

    // MARK: Today's session

    /// The medium widget's lines: today's planned items in the plan's order (at most two), each a program or
    /// cardio, done or still to start; without a plan for today, the resolver's session alone (the rotation's
    /// next program, the session done or running, or the rest day with the next planned session).
    static func widgetSessionRows(_ resolution: TodaySessionResolution, week: [TrainingDay],
                                  calendar: Calendar) -> [DayWidgetsSnapshot.SessionRow] {
        let session = resolution.session
        let today = week.first(where: \.isToday)
        var rows: [DayWidgetsSnapshot.SessionRow] = []
        if let session, session.state == .running {
            rows.append(.init(kind: .lift, name: session.name, detail: String(localized: "in progress"),
                              isDone: false, start: nil))
        }
        if let today, !today.planned.isEmpty {
            for planned in today.planned {
                switch planned.item {
                case .program(let id):
                    if session?.state == .running, resolution.programId == id { continue }
                    rows.append(programRow(id: id, isDone: planned.isDone, resolution: resolution, today: today))
                case .cardio(let sport, let minutes):
                    rows.append(cardioRow(sport: sport, minutes: minutes, isDone: planned.isDone, today: today))
                }
            }
            return Array(rows.prefix(2))
        }
        guard let session, session.state != .running else { return rows }
        switch session.state {
        case .rest:
            rows.append(.init(kind: .rest, name: session.name,
                              detail: nextPlannedLine(week, resolution: resolution, calendar: calendar)
                                  ?? TodaySynthesisLogic.sessionRow(session, route: nil).subtitle,
                              isDone: false, start: nil))
        case .done:
            rows.append(.init(kind: session.isCardio ? .cardio : .lift, name: session.name,
                              detail: TodaySynthesisLogic.sessionRow(session, route: nil).subtitle,
                              isDone: true, start: nil))
        case .next:
            let start = resolution.programId.map {
                DayWidgetsSnapshot.Start.program(id: $0, name: session.name).url.absoluteString
            }
            rows.append(.init(kind: .lift, name: session.name, detail: liftDetail(session), isDone: false,
                              start: start))
        case .running:
            break
        }
        return rows
    }

    /// A planned program: done (with how long it ran), or still to start (the Synthèse's line when it is the
    /// session the resolver names).
    private static func programRow(id: String, isDone: Bool, resolution: TodaySessionResolution,
                                   today: TrainingDay) -> DayWidgetsSnapshot.SessionRow {
        let session = resolution.session
        let lift = today.lifts.first(where: { $0.programId == id })
        let name = (resolution.programId == id ? session?.name : nil) ?? resolution.programNames[id] ?? lift?.name ?? ""
        if isDone {
            let seconds = lift.map {
                TrainingDays.liftSessionSeconds(startTs: $0.startTs, endTs: $0.endTs,
                                                workout: resolution.liftWorkouts[$0.startTs])
            }
            return .init(kind: .lift, name: name,
                         detail: seconds.map { String(localized: "done · \($0 / 60) min") } ?? String(localized: "done"),
                         isDone: true, start: nil)
        }
        let detail = resolution.programId == id && session?.state == .next ? session.flatMap { liftDetail($0) } : nil
        return .init(kind: .lift, name: name, detail: detail, isDone: false,
                     start: DayWidgetsSnapshot.Start.program(id: id, name: name).url.absoluteString)
    }

    /// Planned cardio: done (with how long the activity lasted), or still to start with its target.
    private static func cardioRow(sport: String, minutes: Int, isDone: Bool,
                                  today: TrainingDay) -> DayWidgetsSnapshot.SessionRow {
        let name = WorkoutCatalog.shownSportName(sport)
        if isDone {
            let activity = today.activities.first(where: { TrainingDays.isSameSport($0.sport, sport) })
            return .init(kind: .cardio, name: name,
                         detail: activity.map { String(localized: "done · \(max(0, $0.endTs - $0.startTs) / 60) min") }
                             ?? String(localized: "done"),
                         isDone: true, start: nil)
        }
        return .init(kind: .cardio, name: name,
                     detail: minutes > 0 ? String(localized: "Target: \(minutes) min") : nil, isDone: false,
                     start: DayWidgetsSnapshot.Start.cardio(sport: sport).url.absoluteString)
    }

    /// The Synthèse's line for a program still to do, without the other planned items it lists after it
    /// (the widget gives each its own line).
    static func liftDetail(_ session: TodaySynthesisLogic.Session) -> String? {
        var alone = session
        alone.alsoPlanned = []
        return TodaySynthesisLogic.sessionRow(alone, route: nil).subtitle
    }

    /// « Next: Full body B · Monday »: the first item planned on a later day of this week.
    static func nextPlannedLine(_ week: [TrainingDay], resolution: TodaySessionResolution,
                                calendar: Calendar) -> String? {
        guard let todayIndex = week.firstIndex(where: \.isToday) else { return nil }
        for day in week[(todayIndex + 1)...] {
            guard let item = day.planned.first?.item else { continue }
            let name: String
            switch item {
            case .program(let id): name = resolution.programNames[id] ?? ""
            case .cardio(let sport, _): name = WorkoutCatalog.shownSportName(sport)
            }
            guard !name.isEmpty else { continue }
            let weekday = DateFormatter()
            weekday.locale = AppLanguage.activeLocale
            weekday.calendar = calendar
            weekday.setLocalizedDateFormatFromTemplate("EEEE")
            let next = name + " · " + weekday.string(from: day.date)
            return String(localized: "Next: \(next)")
        }
        return nil
    }

    /// « jeu. 5 nov. »: the day in the app's language, abbreviated.
    static func widgetDayLine(_ day: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.activeLocale
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return formatter.string(from: day)
    }

    /// « This week · **0 / 2** sessions done », the Training calendar's tally (`TrainingDays.sessionTally`);
    /// nil without a plan.
    static func weekDoneLine(_ week: [TrainingDay]) -> DayWidgetsSnapshot.Emphasis? {
        let tally = TrainingDays.sessionTally(week)
        guard tally.planned > 0 else { return nil }
        let value = "\(tally.done) / \(tally.planned)"
        let sentence = String(localized: "This week") + " · "
            + String(localized: "\(tally.done) / \(tally.planned) sessions done")
        return emphasis(sentence, value: value)
    }

    // MARK: Nutrition

    /// The Nutrition card's three figures: left of the intake goal, spent, net (`NutritionView.figuresLine`).
    static func nutritionFigures(_ day: NutritionDaySummary,
                                 plan: NutritionGoals.Plan) -> (left: String?, spent: String?, net: String?) {
        let goal = plan.intakeKcal
        let left = goal > 0 ? NutritionFormat.whole(max(0, goal - day.eaten.kcal)) : nil
        let spent = day.spent.map { NutritionFormat.whole(Int($0.totalKcal.rounded())) }
        let net = day.balanceKcal.map(NutritionFormat.signedKcal)
        return (left, spent, net)
    }

    // MARK: Sleep

    /// Each stage's total over the night, deep first, as the sleep widget's legend lists them; a stage the
    /// night did not have is left out.
    static func stageTotals(_ phases: [DayWidgetsSnapshot.Phase]) -> [DayWidgetsSnapshot.StageTotal] {
        let order: [(stage: String, label: SleepStage)] = [("deep", .deep), ("rem", .rem), ("light", .light),
                                                           ("wake", .awake)]
        return order.compactMap { entry in
            let minutes = phases.filter { $0.stage == entry.stage }.reduce(0) { $0 + $1.minutes }
            guard minutes > 0 else { return nil }
            let length = minutes < 60 ? String(localized: "\(minutes) min") : SleepDurationText.format(Double(minutes))
            return .init(stage: entry.stage, name: entry.label.label, length: length)
        }
    }

    // MARK: Rings

    /// Today's four rings as the hero card draws them (`TodayHeroCard`): activity against the activity goal
    /// (`TodayEnergy.goal`), Charge, Effort with its target band, Rest with the night.
    static func ringsSection(activity: TodayEnergy.Split?, activityGoal: Double?, charge: Double?,
                             effortStored: Double?, effortScale: EffortScale, rest: Double?,
                             nightMinutes: Double?) -> DayWidgetsSnapshot.Rings {
        func whole(_ v: Double) -> String { Int(v.rounded()).formatted(.number.locale(AppLanguage.activeLocale)) }
        let activityFraction: Double = {
            guard let activity else { return 0 }
            if let goal = activityGoal, goal > 0 { return activity.activityKcal / goal }
            return TodayEnergy.arc(activity, goal: nil).activity
        }()
        let activityCaption: String = {
            guard let goal = activityGoal, goal > 0 else { return String(localized: "kcal") }
            return "/" + whole(goal) + " " + String(localized: "kcal")
        }()
        let effortMax: Double = effortScale == .whoop ? 21 : 100
        let effort = effortStored.map { UnitFormatter.effortValue($0, scale: effortScale) }
        let band = TodayHeroFigures.heroEffortTarget(recovery: charge, scale: effortScale)
        return DayWidgetsSnapshot.Rings(
            activity: .init(label: String(localized: "Activity"), value: activity.map { whole($0.activityKcal) },
                            caption: activityCaption, fraction: activityFraction),
            charge: .init(label: String(localized: "Charge"), value: charge.map(whole), caption: nil,
                          fraction: (charge ?? 0) / 100, score: charge),
            effort: .init(label: String(localized: "Effort"),
                          value: effort.map { effortScale == .whoop ? UnitFormatter.decimal($0, places: 1) : whole($0) },
                          caption: TodayHeroFigures.heroEffortCaption(band),
                          fraction: (effort ?? 0) / effortMax,
                          bandFrom: band.map { $0.lowerBound / effortMax }, bandTo: band.map { $0.upperBound / effortMax }),
            rest: .init(label: String(localized: "Rest"), value: rest.map(whole),
                        caption: nightMinutes.map { SleepDurationText.format($0) }, fraction: (rest ?? 0) / 100))
    }

    // MARK: Heart rate

    /// The day's two thresholds at each 5-minute slot, by the rule Today's heart-rate card applies at each
    /// step (`TodayHRAlert.thresholds`: the usual rate plus the margin, the awake floor, the resting fallback);
    /// nil when no slot has either.
    static func heartSection(habitual: [Int: Double], awakeFloor: Double?, restingHR: Double?,
                             sleep: [ClosedRange<Int>]) -> DayWidgetsSnapshot.Heart? {
        let slots = 86_400 / DayWidgetsSnapshot.Heart.slotSeconds
        var high = Array(repeating: 0, count: slots), low = Array(repeating: 0, count: slots)
        var provisional = false
        for slot in 0..<slots {
            let t = TodayHRAlert.thresholds(usualNow: habitual[slot], awakeFloor: awakeFloor, restingHR: restingHR)
            high[slot] = t.high.map { Int($0.rounded()) } ?? 0
            low[slot] = t.low.map { Int($0.rounded()) } ?? 0
            provisional = provisional || t.provisional
        }
        guard high.contains(where: { $0 > 0 }) || low.contains(where: { $0 > 0 }) else { return nil }
        let labels = heartLineLabels()
        return .init(high: high, low: low, provisional: provisional,
                     sleep: sleep.map { [$0.lowerBound, $0.upperBound] },
                     highLabel: labels.high, lowLabel: labels.low)
    }

    // MARK: Stress

    /// The Today stress card's model (`TodayStressLogic.model`) as the widget draws it, worded.
    static func stressSection(_ model: TodayStressModel, dayStart: Int) -> DayWidgetsSnapshot.Stress {
        let formatter = AppClock.hourMinuteFormatter()
        let axisHours = stride(from: TodayStressLogic.startHour, through: TodayStressLogic.endHour, by: 4)
        let latestEnd = model.latestStartTs.map { $0 + DaytimeStress.bucketSeconds }
        return DayWidgetsSnapshot.Stress(
            points: model.points.map { .init(x: $0.x, level: $0.level, run: $0.run) },
            moving: model.moving.map { [$0.lowerBound, $0.upperBound] },
            latestLevel: model.latestLevel,
            latestName: model.latestLevel.map { TodayStressLogic.bandName(TodayStressLogic.stressBand($0)) },
            latestValue: model.latestLevel.map { TodayStressLogic.levelText($0) + " " + String(localized: "of 3") },
            latestAt: model.latestStartTs.map { String(localized: "at \(TodayStressLogic.stressClock($0))") },
            freshUntil: latestEnd.map { $0 + DaytimeStress.timelineStepSeconds },
            high: model.hasData ? TodayStressLogic.minutesText(model.highMinutes) : nil,
            mean: model.mean.map(TodayStressLogic.levelText),
            peak: model.peakStartTs.map(TodayStressLogic.stressClock),
            axis: axisHours.map { hour in
                formatter.string(from: Date(timeIntervalSince1970: TimeInterval(dayStart + hour * 3_600)))
            },
            dayStart: dayStart)
    }
}
