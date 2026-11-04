import Foundation
import StrandAnalytics
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
                            sleep: DayWidgetsSnapshot.Sleep?) -> DayWidgetsSnapshot {
        DayWidgetsSnapshot(dayKey: Repository.localDayKey(dayStart),
                           validUntil: dayWidgetsValidUntil(dayStart: dayStart, calendar: calendar),
                           session: session, nutrition: nutrition, sleep: sleep, labels: widgetLabels())
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
        let blocks = resolution.programId.map { id in
            TrainingDays.programSummary(id: id, name: session?.name ?? "", items: resolution.programItems,
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
            weekLine: tallyText.map { String(localized: "This week") + " " + $0 })
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
            fat: macro(eaten.fatG, goal: plan.fatG))
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
            phases: phases.isEmpty ? nil : phases)
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
