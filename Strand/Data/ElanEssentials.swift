import Foundation
import WhoopStore

// Personal fork, chantier 10 (Élan), PR B: the readings of the Lectures tab.
//
// « Les essentiels » are written once, offline, in French and English, in `Strand/Resources/ElanEssentials.json`
// (Mohamed's choice, 8 Nov.: the nine of the mockup, FR + EN; every source verified by a web search, none
// invented; other languages read the English). The daily reading (PR D) will produce the same `ElanReading`
// from the Coach, so one reading screen serves both. The reader's own figures (« Pour toi ») are resolved
// here from the screens that own them, never recomputed.

/// A text in the two languages the readings are written in.
struct ElanLocalized: Codable, Equatable {
    var fr: String
    var en: String

    /// French for a French app, English otherwise.
    func text(languageCode: String) -> String {
        languageCode.lowercased().hasPrefix("fr") ? fr : en
    }
}

/// The theme of a reading: its colour is the colour of the screen that owns the subject.
enum ElanReadingTheme: String, Codable, CaseIterable, Equatable {
    case heart, sleep, nutrition, training
}

/// The figures of the reader a reading can show under « Pour toi », filled by `ElanFigures`.
enum ElanFigureKey: String, Codable, CaseIterable, Equatable {
    case hrvLastNight, hrvNormal, restingHrLastNight, restingHrNormal
    case spo2LastNight, respiratoryRateLastNight
    case sleepLastNight, sleepNeed, sleepDebt, sleepAverage7
    case chargeToday, effortToday
    case proteinGoal, intakeGoal, intakeToday
    case sessionsThisWeek
}

/// One section of a reading, citing one of its sources (1-based).
struct ElanReadingSection: Codable, Equatable {
    var heading: ElanLocalized
    var body: ElanLocalized
    var source: Int
}

/// A source the reading rests on: a real page.
struct ElanReadingSource: Codable, Equatable {
    var title: String
    var url: String
    var host: String
    var year: Int?
}

/// A reading, essential or daily.
struct ElanReading: Codable, Equatable, Identifiable {
    var id: String
    var theme: ElanReadingTheme
    var minutes: Int
    var figures: [ElanFigureKey]
    var title: ElanLocalized
    var points: ElanLocalizedList
    var sections: [ElanReadingSection]
    var tryIt: ElanLocalized
    var sources: [ElanReadingSource]
}

/// A list of texts in the two languages (the three points of « L'essentiel »).
struct ElanLocalizedList: Codable, Equatable {
    var fr: [String]
    var en: [String]

    func texts(languageCode: String) -> [String] {
        languageCode.lowercased().hasPrefix("fr") ? fr : en
    }
}

/// The bundled file.
struct ElanEssentialsFile: Codable, Equatable {
    var version: Int
    var essentials: [ElanReading]
}

enum ElanEssentials {

    static let resourceName = "ElanEssentials"

    /// The nine essentials, in the file's order, read once.
    static let bundled: [ElanReading] = readBundledEssentials()

    static func readBundledEssentials(bundle: Bundle = .main) -> [ElanReading] {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return parseEssentials(data)
    }

    /// The file's essentials; empty when it does not parse (the tab then says the readings are missing).
    static func parseEssentials(_ data: Data) -> [ElanReading] {
        (try? JSONDecoder().decode(ElanEssentialsFile.self, from: data))?.essentials ?? []
    }

    /// What a reading must hold to be shown: three points, at least one section, every section citing an
    /// existing source, at least one source, both languages filled. The test on the bundled file pins it.
    static func validationIssues(_ reading: ElanReading) -> [String] {
        var issues: [String] = []
        if reading.points.fr.count != 3 || reading.points.en.count != 3 { issues.append("\(reading.id): three points") }
        if reading.sections.isEmpty { issues.append("\(reading.id): no section") }
        if reading.sources.isEmpty { issues.append("\(reading.id): no source") }
        for section in reading.sections where section.source < 1 || section.source > reading.sources.count {
            issues.append("\(reading.id): section cites source \(section.source)")
        }
        for source in reading.sources where !source.url.hasPrefix("https://") {
            issues.append("\(reading.id): source without https: \(source.url)")
        }
        let texts = [reading.title.fr, reading.title.en, reading.tryIt.fr, reading.tryIt.en]
            + reading.sections.flatMap { [$0.heading.fr, $0.heading.en, $0.body.fr, $0.body.en] }
            + reading.points.fr + reading.points.en
        if texts.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            issues.append("\(reading.id): an empty text")
        }
        if reading.minutes < 1 || reading.minutes > 15 { issues.append("\(reading.id): minutes") }
        return issues
    }

    /// The essentials of one theme, in the file's order; all of them for nil.
    static func essentials(_ readings: [ElanReading], theme: ElanReadingTheme?) -> [ElanReading] {
        guard let theme else { return readings }
        return readings.filter { $0.theme == theme }
    }
}

// MARK: - Read / unread

/// Which readings were opened, by id. UserDefaults; a mark is not data.
enum ElanReadLog {
    static let key = "elan.readings.read"

    static func readIds(_ d: UserDefaults = .standard) -> Set<String> {
        Set(d.stringArray(forKey: key) ?? [])
    }

    static func markRead(_ id: String, _ d: UserDefaults = .standard) {
        var ids = readIds(d)
        guard ids.insert(id).inserted else { return }
        d.set(ids.sorted(), forKey: key)
    }
}

// MARK: - « Pour toi »: the reader's own figures

/// The reader's figures a reading can show, already worded, by key. Missing data = no row.
struct ElanFigures: Equatable {
    var values: [ElanFigureKey: String] = [:]

    subscript(key: ElanFigureKey) -> String? { values[key] }

    /// The rows of a reading: its keys, in its order, those with a value.
    func rows(for reading: ElanReading) -> [(key: ElanFigureKey, value: String)] {
        reading.figures.compactMap { key in values[key].map { (key: key, value: $0) } }
    }
}

extension ElanFigures {

    /// The figures from the screens that own them: the latest banked day for the night's vitals, the Charge
    /// baselines for the normals, the Synthèse's sleep figures, Nutrition's plan and day, Élan's week tally.
    @MainActor
    static func loadElanFigures(repo: Repository, profile: ProfileStore, sessionsThisWeek: Int?,
                                now: Date = Date()) async -> ElanFigures {
        var figures = ElanFigures()
        let latest = repo.days.filter { $0.day <= Repository.localDayKey(now) }.last
        func whole(_ v: Double?) -> Int? { v.map { Int($0.rounded()) } }
        if let hrv = whole(latest?.avgHrv) { figures.values[.hrvLastNight] = String(localized: "\(hrv) ms") }
        if let rhr = whole(latest?.restingHr) { figures.values[.restingHrLastNight] = String(localized: "\(rhr) bpm") }
        if let spo2 = whole(latest?.spo2Pct) { figures.values[.spo2LastNight] = String(spo2) + " %" }
        if let rate = latest?.respRateBpm {
            figures.values[.respiratoryRateLastNight] = String(localized: "\(UnitFormatter.decimal(rate, places: 1)) /min")
        }
        if let band = TodayVitalRange.normalBand(repo.chargeBaselines?.hrv) {
            figures.values[.hrvNormal] = String(localized: "\(Int(band.lowerBound.rounded()))–\(Int(band.upperBound.rounded())) ms")
        }
        if let band = TodayVitalRange.normalBand(repo.chargeBaselines?.restingHR) {
            figures.values[.restingHrNormal] = String(localized: "\(Int(band.lowerBound.rounded()))–\(Int(band.upperBound.rounded())) bpm")
        }
        if let minutes = latest?.totalSleepMin, minutes > 0 {
            figures.values[.sleepLastNight] = SleepDurationText.format(minutes)
        }
        let recent = repo.days.suffix(7).compactMap(\.totalSleepMin).filter { $0 > 0 }
        if !recent.isEmpty {
            figures.values[.sleepAverage7] = SleepDurationText.format(recent.reduce(0, +) / Double(recent.count))
        }
        if let sleep = await repo.sleepSynthesisFigures(now: now) {
            figures.values[.sleepNeed] = SleepDurationText.format(sleep.needMin)
            if let debt = sleep.debtText { figures.values[.sleepDebt] = debt }
        }
        if let charge = whole(latest?.recovery) { figures.values[.chargeToday] = String(charge) }
        if let effort = latest?.strain {
            let scale = EffortScale(rawValue: UserDefaults.standard.string(forKey: UnitPrefs.effortScaleKey) ?? "") ?? .hundred
            figures.values[.effortToday] = UnitFormatter.effortDisplay(effort, scale: scale)
        }
        let plan = NutritionDayReader.currentPlan(profile: profile)
        if plan.intakeKcal > 0 { figures.values[.intakeGoal] = String(localized: "\(plan.intakeKcal) kcal") }
        if plan.proteinG > 0 { figures.values[.proteinGoal] = String(localized: "\(plan.proteinG) g") }
        let day = await NutritionDayReader.readDay(repo, profile: profile, day: now)
        if !day.meals.isEmpty { figures.values[.intakeToday] = String(localized: "\(day.eaten.kcal) kcal") }
        if let sessionsThisWeek { figures.values[.sessionsThisWeek] = String(sessionsThisWeek) }
        return figures
    }
}
