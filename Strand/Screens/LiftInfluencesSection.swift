import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// The « What shapes my sessions » block of the Progression screen (fork chantier 18, lot C, maquette 4):
// EXPERIMENTAL and off until switched on here. Computed on the iPhone from what is already stored — the night's
// sleep, the water log (each glass keeps its time, so the water of a session is the glasses logged from three
// hours before it to its end), the strength sessions themselves, their workout rows and the strap's heart rate,
// the meal journal of the day before against the current protein goal, and the HRV of the night after.
// Nothing new is stored. The rules and thresholds are `LiftInfluences`; this file reads and lays out.

struct LiftInfluencesSection: View {
    let data: LiftProgressData
    let unitSystem: UnitSystem

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage(Self.enabledKey) private var enabled = false
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @State private var measure: LiftInfluences.Measure = .volume
    @State private var facts: [LiftInfluences.SessionFacts] = []
    @State private var loaded = false

    /// The switch, default off (an Experimental reading).
    static let enabledKey = "lift.influences.enabled"
    /// How many of the latest sessions are read.
    static let maxSessions = 60

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            HStack(spacing: NoopMetrics.space2) {
                Text("What shapes my sessions")
                    .font(StrandFont.sectionTitle)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("Experimental")
                    .font(StrandFont.caption2.weight(.bold))
                    .foregroundStyle(StrandPalette.metricAmber)
                    .padding(.horizontal, NoopMetrics.space2)
                    .padding(.vertical, NoopMetrics.spaceHalf)
                    .background(StrandPalette.metricAmber.opacity(0.16), in: Capsule())
            }
            NoopCard {
                Toggle(isOn: $enabled) {
                    VStack(alignment: .leading, spacing: NoopMetrics.spaceHalf) {
                        Text("Turn this analysis on")
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text("Worked out on the iPhone, never sent. Your sessions are only compared with your own.")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
            }
            if enabled {
                measureChips
                if !loaded {
                    ComingSoon(what: "Reading your sessions…", symbol: "chart.bar")
                } else {
                    ForEach(LiftInfluences.Factor.allCases) { factor in
                        factorCard(LiftInfluences.liftInfluenceComparison(facts, factor: factor, measure: measure))
                    }
                    Text("A difference seen in your sessions is not a cause: other things change on those days too.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task(id: "\(enabled)-\(data.sessions.count)") {
            guard enabled else { return }
            facts = await LiftInfluencesReader.liftInfluenceFacts(
                data: data, repo: repo, limit: Self.maxSessions,
                proteinGoalG: LiftInfluencesReader.liftInfluenceProteinGoal(profile: profile))
            loaded = true
        }
    }

    // MARK: - Measures

    private var measureChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: NoopMetrics.space2) {
                ForEach(LiftInfluences.Measure.allCases) { item in
                    let on = item == measure
                    Button { measure = item } label: {
                        measureName(item)
                            .font(StrandFont.caption.weight(.semibold))
                            .foregroundStyle(on ? StrandPalette.surfaceBase : StrandPalette.textPrimary)
                            .padding(.horizontal, NoopMetrics.space3)
                            .frame(minHeight: 32)
                            .background(on ? StrandPalette.textPrimary : StrandPalette.surfaceRaised, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func measureName(_ measure: LiftInfluences.Measure) -> Text {
        switch measure {
        case .averageHr: return Text("Average HR")
        case .recovery: return Text("HR recovery")
        case .volume: return Text("Weight lifted")
        case .effort: return Text("Effort")
        case .nextNightHrv: return Text("Next night's HRV")
        }
    }

    private func value(_ v: Double, _ measure: LiftInfluences.Measure) -> String {
        switch measure {
        case .averageHr, .recovery: return String(localized: "\(Int(v.rounded())) bpm")
        case .volume: return LiftFormat.weight(v, system: unitSystem)
        case .effort: return UnitFormatter.effortDisplay(v, scale: UnitPrefs.resolveEffortScale(effortScaleRaw))
        case .nextNightHrv: return String(localized: "\(Int(v.rounded())) ms")
        }
    }

    private func signed(_ v: Double, _ measure: LiftInfluences.Measure) -> String {
        (v >= 0 ? "+" : "−") + value(abs(v), measure)
    }

    // MARK: - Factors

    private func factorName(_ factor: LiftInfluences.Factor) -> Text {
        switch factor {
        case .sleep: return Text("Sleep the night before")
        case .water: return Text("Water before and during")
        case .sessionDayBefore: return Text("Training the day before")
        case .proteinDayBefore: return Text("Protein the day before")
        }
    }

    /// What the « with » and « without » groups are, in words.
    private func groups(_ factor: LiftInfluences.Factor) -> (with: String, without: String) {
        switch factor {
        case .sleep: return (String(localized: "7 h 30 or more"), String(localized: "less than 7 h 30"))
        case .water: return (String(localized: "750 ml or more"), String(localized: "less than 750 ml"))
        case .sessionDayBefore: return (String(localized: "a session the day before"),
                                        String(localized: "no session the day before"))
        case .proteinDayBefore:
            let goal = NutritionDayReader.currentPlan(profile: profile).proteinG
            return (String(localized: "\(goal) g or more"), String(localized: "less than \(goal) g"))
        }
    }

    private func factorCard(_ c: LiftInfluences.Comparison) -> some View {
        let names = groups(c.factor)
        return NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                HStack(alignment: .firstTextBaseline) {
                    factorName(c.factor)
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer(minLength: NoopMetrics.space2)
                    if c.isEnough { pill(c) }
                }
                if c.isEnough, let with = c.withMean, let without = c.withoutMean {
                    Group {
                        if c.isClearDifference {
                            Text(String(localized: "In your sessions, we observe \(value(with, c.measure)) on average with \(names.with), against \(value(without, c.measure)) with \(names.without)."))
                        } else {
                            Text(String(localized: "No clear difference in your sessions between \(names.with) and \(names.without)."))
                        }
                    }
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    bars(with: with, without: without, names: names, measure: c.measure)
                    Text(String(localized: "\(c.withCount) sessions against \(c.withoutCount)"))
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                } else {
                    Text(String(localized: "Not enough data yet: \(LiftInfluences.minPerGroup) sessions are needed in each group, \(LiftInfluences.minTotal) in all."))
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ProgressView(value: Double(min(c.smallerGroup, LiftInfluences.minPerGroup)),
                                 total: Double(LiftInfluences.minPerGroup))
                        .tint(StrandPalette.accent)
                    Text(String(localized: "\(c.withCount) sessions against \(c.withoutCount)"))
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
    }

    private func pill(_ c: LiftInfluences.Comparison) -> some View {
        let clear = c.isClearDifference
        let tint = !clear ? StrandPalette.textSecondary
            : (c.isFavorable ? StrandPalette.statusPositive : StrandPalette.metricAmber)
        return Group {
            if clear, let d = c.difference {
                Text(verbatim: signed(d, c.measure))
            } else {
                Text("No clear difference")
            }
        }
        .font(StrandFont.caption.weight(.bold))
        .foregroundStyle(tint)
        .padding(.horizontal, NoopMetrics.space2)
        .padding(.vertical, NoopMetrics.spaceHalf)
        .background(tint.opacity(0.16), in: Capsule())
    }

    private func bars(with: Double, without: Double, names: (with: String, without: String),
                      measure: LiftInfluences.Measure) -> some View {
        let top = max(with, without) * 1.08
        let bottom = min(with, without) * 0.8
        func fraction(_ v: Double) -> CGFloat {
            top > bottom ? CGFloat((v - bottom) / (top - bottom)) : 1
        }
        return VStack(spacing: NoopMetrics.space2) {
            bar(names.with, value(with, measure), fraction(with), StrandPalette.effortColor)
            bar(names.without, value(without, measure), fraction(without), StrandPalette.textTertiary)
        }
    }

    private func bar(_ label: String, _ value: String, _ fraction: CGFloat, _ tint: Color) -> some View {
        HStack(spacing: NoopMetrics.space2) {
            Text(verbatim: label)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                .frame(width: 110, alignment: .leading)
                .lineLimit(2)
            GeometryReader { proxy in
                Capsule().fill(StrandPalette.surfaceInset)
                    .overlay(alignment: .leading) {
                        Capsule().fill(tint).frame(width: max(4, proxy.size.width * min(1, max(0, fraction))))
                    }
            }
            .frame(height: 8)
            Text(verbatim: value)
                .font(StrandFont.captionNumber)
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(minWidth: 64, alignment: .trailing)
        }
    }
}

/// Reads the facts of the latest sessions for `LiftInfluences`: this block and the Coach's (fork chantier 18).
@MainActor
enum LiftInfluencesReader {
    /// The protein goal the day before is judged against: the current one (`NutritionDayReader.currentPlan`),
    /// nil when there is none.
    static func liftInfluenceProteinGoal(profile: ProfileStore) -> Int? {
        let goal = NutritionDayReader.currentPlan(profile: profile).proteinG
        return goal > 0 ? goal : nil
    }

    static func liftInfluenceFacts(data: LiftProgressData, repo: Repository, limit: Int,
                                   proteinGoalG: Int? = nil) async -> [LiftInfluences.SessionFacts] {
        let sessions = data.sessions
            .filter { $0.row.endTs != nil }
            .sorted { $0.row.startTs > $1.row.startTs }
            .prefix(limit)
        guard let store = await repo.storeHandle(), let oldest = sessions.last?.row.startTs,
              let newest = sessions.first?.row.startTs else { return [] }
        let workouts = (try? await store.workouts(deviceId: repo.deviceId, from: oldest - 1,
                                                  to: newest + 1, limit: 2000)) ?? []
        let starts = data.sessions.map(\.row.startTs)
        let calendar = Calendar.current
        // The meals of the day before each session, in one read (`MealJournal`): their protein, a day with no
        // meal written down being unknown rather than none.
        var proteinByDay: [String: Double] = [:]
        if let first = LiftInfluences.liftInfluenceDayKey(oldest, offset: -1, calendar: calendar),
           let last = LiftInfluences.liftInfluenceDayKey(newest, offset: -1, calendar: calendar) {
            let meals = (try? await MealJournal.mealJournalRange(store, fromDay: first, toDay: last)) ?? []
            for (day, dayMeals) in Dictionary(grouping: meals, by: \.meal.day) where !dayMeals.isEmpty {
                proteinByDay[day] = NutritionDaySummary(dayKey: day, meals: dayMeals, spent: nil).eaten.proteinG
            }
        }
        // The HRV of each night, by the day it ends.
        var hrvByDay: [String: Double] = [:]
        for day in repo.days {
            if let hrv = day.avgHrv, hrv > 0 { hrvByDay[day.day] = hrv }
        }
        var out: [LiftInfluences.SessionFacts] = []
        for session in sessions {
            guard let end = session.row.endTs else { continue }
            let start = session.row.startTs
            let day = Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(start)))
            let performed = session.sets.filter { LiftMetrics.isPerformed(reps: $0.reps) }
            var measures: [LiftInfluences.Measure: Double] = [:]
            if let volume = LiftMetrics.volumeLoadKg(performed), volume > 0 { measures[.volume] = volume }
            if let workout = workouts.first(where: { $0.startTs == start && $0.sport == session.row.sport }) {
                if let hr = workout.avgHr, hr > 0 { measures[.averageHr] = Double(hr) }
                if let strain = workout.strain, strain > 0 { measures[.effort] = strain }
            }
            let samples = await repo.hrSamples(from: start, to: end)
            var seen = Set<Int>()
            let spans = performed.compactMap { row -> LiftHeartRateMath.SetSpan? in
                guard let s = row.startTs, let e = row.endTs, seen.insert(e).inserted else { return nil }
                return LiftHeartRateMath.SetSpan(start: s, end: e, restSec: row.restSec ?? 0)
            }
            if let recovery = LiftHeartRateMath.mean(LiftHeartRateMath.recoveries(spans, samples: samples, now: end)) {
                measures[.recovery] = Double(recovery)
            }
            if let next = LiftInfluences.liftInfluenceDayKey(start, offset: 1, calendar: calendar),
               let hrv = hrvByDay[next] {
                measures[.nextNightHrv] = hrv
            }
            let dayBefore = LiftInfluences.liftInfluenceDayKey(start, offset: -1, calendar: calendar)
            out.append(LiftInfluences.SessionFacts(
                startTs: start,
                sleepMin: data.sleep[day],
                waterMl: LiftInfluences.liftSessionWater(repo.hydrationEntries(day: day), start: start, end: end),
                sessionDayBefore: LiftInfluences.liftHadSessionDayBefore(start, among: starts, calendar: calendar),
                measures: measures,
                proteinDayBeforeG: dayBefore.flatMap { proteinByDay[$0] },
                proteinGoalG: proteinGoalG))
        }
        return out
    }
}
