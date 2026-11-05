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
    /// Widgets v2 (5 Nov.): Today's four rings, the heart-rate thresholds of the day and the stress curve, as
    /// the Today cards draw them.
    var rings: Rings?
    var heart: Heart?
    var stress: Stress?
    /// The other words the widgets need, keyed by their English text (`word(_:)`); a missing one reads in
    /// English.
    var words: [String: String]?

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

    /// One line of the medium "Today's session" widget (widgets v2): a program or planned cardio, done or to
    /// start, or the rest day.
    struct SessionRow: Codable, Equatable {
        enum Kind: String, Codable {
            case lift, cardio, rest
        }

        var kind: Kind
        /// "Full body A", "Walking", "Rest".
        var name: String
        /// "3 supersets + 1 exercise · ≈ 55 min", "Target: 30 min", "done · 52 min", "Next: Full body B · Monday".
        var detail: String?
        var isDone: Bool
        /// What its Start button launches (`Start.url`); nil when there is nothing to start.
        var start: String?
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
        /// Widgets v2: today's planned items (at most two), else the resolver's session alone.
        var rows: [SessionRow]?
        /// "Thu 5 Nov", in the app's language.
        var dayLine: String?
        /// "This week · **0 / 2** sessions done". Nil without a plan.
        var weekDone: Emphasis?
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
        /// Widgets v2, the Nutrition card's figures: "660" left of the goal, "2 100" spent, "−860" net.
        var left: String?
        var spent: String?
        var net: String?
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
        /// Widgets v2: each stage's total over the night, deep first: its name and its length.
        var stages: [StageTotal]?
    }

    /// One stage's total in the sleep widget's legend.
    struct StageTotal: Codable, Equatable {
        /// "deep", "rem", "light" or "wake", as in `Phase`.
        var stage: String
        /// "Deep".
        var name: String
        /// "56 min", "1h 08m".
        var length: String
    }

    /// One of Today's four rings (widgets v2), worded as the hero card words it.
    struct Ring: Codable, Equatable {
        /// "Activity", "Charge", "Effort", "Rest".
        var label: String
        /// "420", "19", "3,9"; nil reads as a dash.
        var value: String?
        /// "/ 600 kcal", "target 8–14", "6h 48m".
        var caption: String?
        /// The ring's fill, 0…1 (beyond 1 is a full ring).
        var fraction: Double
        /// The Effort ring's target band, as fractions of the ring.
        var bandFrom: Double?
        var bandTo: Double?
        /// The Charge score its tint follows (red / yellow / green, `StrandPalette.chargeTint`).
        var score: Double?
    }

    /// Today's hero rings, outside to inside.
    struct Rings: Codable, Equatable {
        var activity: Ring
        var charge: Ring
        var effort: Ring
        var rest: Ring
    }

    /// The heart-rate card's two thresholds over the day (widgets v2): at each 5-minute slot after local
    /// midnight, the rule Today's card applies (`TodayHRAlert.thresholds`), rounded; 0 where there is none.
    struct Heart: Codable, Equatable {
        static let slotSeconds = 300

        var high: [Int]
        var low: [Int]
        /// A side still comes from the resting-rate fallback (too little history).
        var provisional: Bool
        /// The day's sleep, `[start, end]` in unix seconds: the curve is not coloured there, as on Today.
        var sleep: [[Int]]
        /// « high … » / « low … », the figure left out (`value` is a stand-in the widget replaces).
        var highLabel: Emphasis?
        var lowLabel: Emphasis?

        /// The slot of `ts` in the local day of `zone`.
        static func slot(_ ts: Int, zone: TimeZone = .current) -> Int {
            let local = ts + zone.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(ts)))
            let day = 86_400
            return ((local % day) + day) % day / slotSeconds
        }

        /// The high and low thresholds at `ts`, nil where there is none.
        func thresholds(at ts: Int, zone: TimeZone = .current) -> (high: Int?, low: Int?) {
            let i = Self.slot(ts, zone: zone)
            let h = high.indices.contains(i) ? high[i] : 0
            let l = low.indices.contains(i) ? low[i] : 0
            return (h > 0 ? h : nil, l > 0 ? l : nil)
        }

        /// True while `ts` is inside the day's sleep.
        func isAsleep(_ ts: Int) -> Bool {
            sleep.contains { $0.count == 2 && $0[0] <= ts && ts <= $0[1] }
        }
    }

    /// The stress card of Today (widgets v2): its points and moving spans on the 06:00–22:00 axis, the level
    /// of the latest scored hour and the day's figures, all worded by the app.
    struct Stress: Codable, Equatable {
        /// A scored point: x on the axis (0…1), level 0…3, and its run (a gap starts a new one).
        struct Dot: Codable, Equatable {
            var x: Double
            var level: Double
            var run: Int
        }

        var points: [Dot]
        /// Hours masked for movement, `[from, to]` on the axis.
        var moving: [[Double]]
        var latestLevel: Double?
        /// "Moderate".
        var latestName: String?
        /// "1,4 of 3".
        var latestValue: String?
        /// "at 15:00", shown once the latest hour is no longer the current one.
        var latestAt: String?
        /// Until when the latest hour reads as "this hour" (unix seconds).
        var freshUntil: Int?
        /// "45 min" in the High band, "2,3" on average, "15:00" at the peak.
        var high: String?
        var mean: String?
        var peak: String?
        /// The axis' hour labels, 06:00 to 22:00.
        var axis: [String]
        /// Local midnight of the day scored (unix seconds): another day's curve is not drawn.
        var dayStart: Int?
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

    /// Where a "Start" button of the session widget leads (widgets v2): `noop://widget/start?program=…&name=…`
    /// starts that program's Lift Log session, `noop://widget/start?sport=…` the live workout of that sport.
    enum Start: Equatable {
        case program(id: String, name: String)
        case cardio(sport: String)

        static let path = "/start"

        var url: URL {
            var parts = URLComponents()
            parts.scheme = "noop"
            parts.host = Link.host
            parts.path = Self.path
            switch self {
            case .program(let id, let name):
                parts.queryItems = [URLQueryItem(name: "program", value: id), URLQueryItem(name: "name", value: name)]
            case .cardio(let sport):
                parts.queryItems = [URLQueryItem(name: "sport", value: sport)]
            }
            return parts.url ?? URL(fileURLWithPath: "/")
        }

        /// The start a tapped button opened the app with; nil for any other URL.
        init?(url: URL) {
            guard url.scheme == "noop", url.host == Link.host, url.path == Self.path,
                  let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
            func value(_ name: String) -> String? {
                items.first(where: { $0.name == name })?.value.flatMap { $0.isEmpty ? nil : $0 }
            }
            if let id = value("program") {
                self = .program(id: id, name: value("name") ?? "")
            } else if let sport = value("sport") {
                self = .cardio(sport: sport)
            } else {
                return nil
            }
        }
    }

    /// A word of `words`, or its English text when the app has not written it.
    func word(_ english: String) -> String {
        words?[english] ?? english
    }

    /// The widget kinds, one per section.
    static let sessionKind = "NOOPSessionWidget"
    static let nutritionKind = "NOOPNutritionWidget"
    static let sleepKind = "NOOPSleepWidget"
    /// Widgets v2: the rings, heart-rate and stress widgets also read this snapshot.
    static let ringsKind = "NOOPWidget"
    static let heartKind = "HeartRateWidget"
    static let stressKind = "StressWidget"

    /// App Group key, apart from `WidgetSnapshot.storageKey`.
    static let storageKey = "noop.widget.day"

    /// True while the day it describes lasts.
    func isCurrent(at now: Date) -> Bool {
        guard let validUntil else { return false }
        return now < validUntil
    }

    /// The kinds whose section changed since `previous`: only those widgets are reloaded. The labels and the
    /// words change all of them (the app's language).
    func changedWidgetKinds(from previous: DayWidgetsSnapshot?) -> [String] {
        guard let previous, previous.dayKey == dayKey, previous.validUntil == validUntil,
              previous.labels == labels, previous.words == words else {
            return Self.allKinds
        }
        var kinds: [String] = []
        if previous.session != session { kinds.append(Self.sessionKind) }
        if previous.nutrition != nutrition { kinds.append(Self.nutritionKind) }
        if previous.sleep != sleep { kinds.append(Self.sleepKind) }
        if previous.rings != rings { kinds.append(Self.ringsKind) }
        if previous.heart != heart { kinds.append(Self.heartKind) }
        if previous.stress != stress { kinds.append(Self.stressKind) }
        return kinds
    }

    /// Every widget that reads this snapshot.
    static let allKinds = [sessionKind, nutritionKind, sleepKind, ringsKind, heartKind, stressKind]

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
                tally: "0/3", weekLine: "This week 0/3",
                rows: [SessionRow(kind: .lift, name: "Full body A", detail: "5 supersets · ≈ 55 min", isDone: false,
                                  start: Start.program(id: "", name: "Full body A").url.absoluteString),
                       SessionRow(kind: .cardio, name: "Walking", detail: "Target: 30 min", isDone: false,
                                  start: Start.cardio(sport: "Walking").url.absoluteString)],
                dayLine: "Thu 5 Nov",
                weekDone: Emphasis(before: "This week · ", value: "0 / 3", after: " sessions done")),
            nutrition: Nutrition(
                eaten: "1,495", goalShort: "/ 2,560 kcal", goalLong: "/ 2,560 kcal eaten", fraction: 0.58,
                balance: Emphasis(before: "balance ", value: "−605", after: ""), meals: "3 meals",
                protein: Macro(eaten: "98", rest: "/ 160 g", fraction: 0.61),
                carbs: Macro(eaten: "162", rest: "/ 318 g", fraction: 0.51),
                fat: Macro(eaten: "52", rest: "/ 80 g", fraction: 0.65),
                left: "1,065", spent: "2,100", net: "−605"),
            sleep: Sleep(
                night: "6h 48m", debt: Emphasis(before: "debt ", value: "1h 12m", after: ""),
                bedtime: Emphasis(before: "Suggested bedtime ", value: "23:10", after: ""),
                usualWake: "usual wake-up 06:50", start: "23:52", end: "06:40",
                phases: [Phase(stage: "light", minutes: 54), Phase(stage: "deep", minutes: 27),
                         Phase(stage: "light", minutes: 42), Phase(stage: "rem", minutes: 21),
                         Phase(stage: "wake", minutes: 6), Phase(stage: "light", minutes: 48),
                         Phase(stage: "deep", minutes: 18), Phase(stage: "rem", minutes: 30),
                         Phase(stage: "wake", minutes: 9), Phase(stage: "light", minutes: 45)],
                stages: [StageTotal(stage: "deep", name: "Deep", length: "45 min"),
                         StageTotal(stage: "rem", name: "REM", length: "51 min"),
                         StageTotal(stage: "light", name: "Light", length: "3h 9m"),
                         StageTotal(stage: "wake", name: "Awake", length: "15 min")]),
            labels: .english,
            rings: Rings(
                activity: Ring(label: "Activity", value: "420", caption: "/600 kcal", fraction: 0.7),
                charge: Ring(label: "Charge", value: "68", caption: nil, fraction: 0.68, score: 68),
                effort: Ring(label: "Effort", value: "38", caption: "target 59–75", fraction: 0.38,
                             bandFrom: 0.59, bandTo: 0.75),
                rest: Ring(label: "Rest", value: "76", caption: "6h 48m", fraction: 0.76)))
    }
}
