import Foundation

/// What the three day widgets draw (personal fork, chantier 6): today's session with the week, today's meals
/// against the goals, and last night's sleep with the debt and the suggested bedtime.
///
/// The app builds it (`DayWidgetsContent`, from the resolvers Today, Nutrition and Sleep read) and writes it
/// into the App Group under its own key, apart from `WidgetSnapshot`, so neither publish dedups the other. The
/// widget extension only reads it: every word and number arrives already worded and formatted, because the
/// extension has no catalog. Every field is optional so a snapshot written by an older build still decodes.
///
/// Foundation only: compiled into the macOS app module too, so `StrandTests` builds and renders it.
struct DayWidgetsSnapshot: Codable, Equatable {
    /// The logical day it describes, "yyyy-MM-dd".
    var dayKey: String?
    /// When that day ends (the app's day rollover). Past it, the widgets say "no data" until the app
    /// publishes the new day, rather than show yesterday's figures as today's.
    var validUntil: Date?
    var session: Session?
    var nutrition: Nutrition?
    var sleep: Sleep?
    var labels: Labels?

    /// A day of the week strip: outlined blue = lift planned, filled blue = lift done, grey outline = missed,
    /// orange = cardio — the Training calendar's marks, one per day.
    enum Mark: String, Codable {
        case planned, done, missed, cardio, none
    }

    /// One letter of the week strip and its mark.
    struct WeekDay: Codable, Equatable {
        var letter: String
        var mark: Mark
        var isToday: Bool
    }

    /// A line with one figure set apart: "debt **1h 12m**", "Protein **98** / 160 g". Split app-side from the
    /// localized sentence, so the figure stays where the language puts it.
    struct Emphasis: Codable, Equatable {
        var before: String
        var value: String
        var after: String
    }

    /// "Today's session": the Synthèse's session (`TodaySessionResolver`) and this week's strip.
    struct Session: Codable, Equatable {
        enum State: String, Codable {
            case next, running, done, rest
        }

        /// "Full body A", "Rest". Nil when there is no session to name.
        var name: String?
        var state: State?
        /// The Synthèse's line: "5 supersets · ≈ 55 min", "done · 52 min", "rest day in your plan".
        var line: String?
        /// The medium widget's line: the same, then "planned" for a session still to do.
        var lineMedium: String?
        /// The program's first two blocks: "A1 Squat · A2 Row".
        var blocks: [String]?
        /// Monday to Sunday.
        var week: [WeekDay]?
        /// "0/3": sessions done this week for the days the plan sets. Nil without a plan.
        var tally: String?
        /// "This week 0/3".
        var weekLine: String?
    }

    /// One macronutrient: eaten against its goal.
    struct Macro: Codable, Equatable {
        /// "98".
        var eaten: String
        /// "/ 160 g", or "g" without a goal.
        var rest: String
        /// Eaten ÷ goal, nil without a goal.
        var fraction: Double?
    }

    /// "Nutrition": the meal journal of the day against the intake goal (`NutritionDaySummary`,
    /// `NutritionDayReader.currentPlan`).
    struct Nutrition: Codable, Equatable {
        /// "1 495".
        var eaten: String
        /// "/ 2 560 kcal", or "kcal" without a goal.
        var goalShort: String
        /// "/ 2 560 kcal eaten", or "kcal eaten" without a goal.
        var goalLong: String
        /// Eaten ÷ intake goal, nil without a goal.
        var fraction: Double?
        /// "balance **−605**", nil without a measured expenditure.
        var balance: Emphasis?
        /// "3 meals".
        var meals: String
        var protein: Macro
        var carbs: Macro
        var fat: Macro
    }

    /// One stretch of the night's hypnogram.
    struct Phase: Codable, Equatable {
        /// "light", "deep", "rem" or "wake".
        var stage: String
        var minutes: Int
    }

    /// "Sleep": the night Today's Rest ring names, and the Synthèse's debt and bedtime
    /// (`Repository.sleepSynthesisFigures`).
    struct Sleep: Codable, Equatable {
        /// "6h 48m".
        var night: String?
        /// "debt **1h 12m**".
        var debt: Emphasis?
        /// "Suggested bedtime **23:10**".
        var bedtime: Emphasis?
        /// "usual wake-up 06:50".
        var usualWake: String?
        /// The night's onset and wake, "23:52" and "06:40".
        var start: String?
        var end: String?
        var phases: [Phase]?
    }

    /// The words the widgets need beyond the figures, worded by the app. Missing ones read in English.
    struct Labels: Codable, Equatable {
        var sessionTitle: String
        var nutritionTitle: String
        var sleepTitle: String
        var sessionAbout: String
        var nutritionAbout: String
        var sleepAbout: String
        var open: String
        var noData: String
        var protein: String
        var carbs: String
        var fat: String

        init(sessionTitle: String, nutritionTitle: String, sleepTitle: String, sessionAbout: String,
             nutritionAbout: String, sleepAbout: String, open: String, noData: String, protein: String,
             carbs: String, fat: String) {
            self.sessionTitle = sessionTitle
            self.nutritionTitle = nutritionTitle
            self.sleepTitle = sleepTitle
            self.sessionAbout = sessionAbout
            self.nutritionAbout = nutritionAbout
            self.sleepAbout = sleepAbout
            self.open = open
            self.noData = noData
            self.protein = protein
            self.carbs = carbs
            self.fat = fat
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let english = Labels.english
            func text(_ key: CodingKeys, _ fallback: String) throws -> String {
                try c.decodeIfPresent(String.self, forKey: key) ?? fallback
            }
            sessionTitle = try text(.sessionTitle, english.sessionTitle)
            nutritionTitle = try text(.nutritionTitle, english.nutritionTitle)
            sleepTitle = try text(.sleepTitle, english.sleepTitle)
            sessionAbout = try text(.sessionAbout, english.sessionAbout)
            nutritionAbout = try text(.nutritionAbout, english.nutritionAbout)
            sleepAbout = try text(.sleepAbout, english.sleepAbout)
            open = try text(.open, english.open)
            noData = try text(.noData, english.noData)
            protein = try text(.protein, english.protein)
            carbs = try text(.carbs, english.carbs)
            fat = try text(.fat, english.fat)
        }

        /// The words before the app has published any: the widget gallery on a fresh install.
        static let english = Labels(
            sessionTitle: "Today's session", nutritionTitle: "Nutrition", sleepTitle: "Sleep",
            sessionAbout: "Today's session from your week plan, and your week at a glance.",
            nutritionAbout: "What you ate today against your goals.",
            sleepAbout: "Last night, your sleep debt and the suggested bedtime.",
            open: "Open", noData: "no data", protein: "Protein", carbs: "Carbs", fat: "Fat")
    }

    /// Where a widget's tap leads: `noop://widget/<name>`.
    enum Link: String, CaseIterable {
        case session, nutrition, sleep

        static let host = "widget"

        var url: URL {
            var parts = URLComponents()
            parts.scheme = "noop"
            parts.host = Self.host
            parts.path = "/" + rawValue
            return parts.url ?? URL(fileURLWithPath: "/")
        }

        /// The link a tapped widget opened the app with; nil for any other URL.
        init?(url: URL) {
            guard url.scheme == "noop", url.host == Self.host else { return nil }
            self.init(rawValue: url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        }
    }

    /// The widget kinds, one per section.
    static let sessionKind = "NOOPSessionWidget"
    static let nutritionKind = "NOOPNutritionWidget"
    static let sleepKind = "NOOPSleepWidget"

    /// App Group key, apart from `WidgetSnapshot.storageKey`.
    static let storageKey = "noop.widget.day"

    /// True while the day it describes lasts.
    func isCurrent(at now: Date) -> Bool {
        guard let validUntil else { return false }
        return now < validUntil
    }

    /// The kinds whose section changed since `previous`: only those widgets are reloaded. The labels change
    /// all three (the app's language).
    func changedWidgetKinds(from previous: DayWidgetsSnapshot?) -> [String] {
        guard let previous, previous.dayKey == dayKey, previous.validUntil == validUntil,
              previous.labels == labels else {
            return [Self.sessionKind, Self.nutritionKind, Self.sleepKind]
        }
        var kinds: [String] = []
        if previous.session != session { kinds.append(Self.sessionKind) }
        if previous.nutrition != nutrition { kinds.append(Self.nutritionKind) }
        if previous.sleep != sleep { kinds.append(Self.sleepKind) }
        return kinds
    }

    /// Decode a stored snapshot; nil for anything unreadable.
    static func decodeDayWidgets(_ data: Data) -> DayWidgetsSnapshot? {
        try? JSONDecoder().decode(DayWidgetsSnapshot.self, from: data)
    }

    /// The last snapshot the app wrote into the App Group `suiteName`, if any.
    static func loadDayWidgets(suiteName: String) -> DayWidgetsSnapshot? {
        guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: storageKey) else { return nil }
        return decodeDayWidgets(data)
    }

    /// Write this snapshot into the App Group `suiteName`.
    func saveDayWidgets(suiteName: String) {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// The widget gallery's sample before the app has published (values of the mockup).
    static var galleryPreview: DayWidgetsSnapshot {
        let marks: [Mark] = [.planned, .none, .planned, .none, .planned, .none, .cardio]
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        return DayWidgetsSnapshot(
            dayKey: nil, validUntil: .distantFuture,
            session: Session(
                name: "Full body A", state: .next, line: "5 supersets · ≈ 55 min",
                lineMedium: "5 supersets · ≈ 55 min · planned",
                blocks: ["A1 Squat · A2 Row", "B1 Bench press · B2 Lunge"],
                week: zip(letters, marks).enumerated().map { WeekDay(letter: $1.0, mark: $1.1, isToday: $0 == 0) },
                tally: "0/3", weekLine: "This week 0/3"),
            nutrition: Nutrition(
                eaten: "1,495", goalShort: "/ 2,560 kcal", goalLong: "/ 2,560 kcal eaten", fraction: 0.58,
                balance: Emphasis(before: "balance ", value: "−605", after: ""), meals: "3 meals",
                protein: Macro(eaten: "98", rest: "/ 160 g", fraction: 0.61),
                carbs: Macro(eaten: "162", rest: "/ 318 g", fraction: 0.51),
                fat: Macro(eaten: "52", rest: "/ 80 g", fraction: 0.65)),
            sleep: Sleep(
                night: "6h 48m", debt: Emphasis(before: "debt ", value: "1h 12m", after: ""),
                bedtime: Emphasis(before: "Suggested bedtime ", value: "23:10", after: ""),
                usualWake: "usual wake-up 06:50", start: "23:52", end: "06:40",
                phases: [Phase(stage: "light", minutes: 54), Phase(stage: "deep", minutes: 27),
                         Phase(stage: "light", minutes: 42), Phase(stage: "rem", minutes: 21),
                         Phase(stage: "wake", minutes: 6), Phase(stage: "light", minutes: 48),
                         Phase(stage: "deep", minutes: 18), Phase(stage: "rem", minutes: 30),
                         Phase(stage: "wake", minutes: 9), Phase(stage: "light", minutes: 45)]),
            labels: .english)
    }
}
