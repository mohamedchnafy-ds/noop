import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Micronutrients on Nutrition (fork chantier 22, mockup https://claude.ai/artifact/XKB1FyUES9WhHQzZwL81JN)
//
// The day card under the moments (« To complete » | « Ceilings »), the detail screen (the day or the
// 7-day average, four groups, « Where it comes from » on a tap), and the line under a food. Every figure
// comes from `MealMicros` and `MicroReference`; a food without the value is counted, never read as 0.

/// How the micronutrient screens write names and amounts.
enum MicroFormat {

    private static var locale: Locale { AppLanguage.activeLocale }

    static func microName(_ nutrient: MicroNutrient) -> String {
        switch nutrient {
        case .fiber: return String(localized: "Fiber")
        case .sugars: return String(localized: "Sugars")
        case .saturatedFat: return String(localized: "Saturated fat")
        case .monounsaturatedFat: return String(localized: "Monounsaturated fat")
        case .polyunsaturatedFat: return String(localized: "Polyunsaturated fat")
        case .cholesterol: return String(localized: "Cholesterol")
        case .salt: return String(localized: "Salt")
        case .alphaLinolenicAcid: return String(localized: "ALA (omega-3)")
        case .epaDha: return String(localized: "EPA + DHA (omega-3)")
        case .linoleicAcid: return String(localized: "Linoleic acid (omega-6)")
        case .calcium: return String(localized: "Calcium")
        case .iron: return String(localized: "Iron")
        case .magnesium: return String(localized: "Magnesium")
        case .potassium: return String(localized: "Potassium")
        case .sodium: return String(localized: "Sodium")
        case .zinc: return String(localized: "Zinc")
        case .phosphorus: return String(localized: "Phosphorus")
        case .iodine: return String(localized: "Iodine")
        case .selenium: return String(localized: "Selenium")
        case .copper: return String(localized: "Copper")
        case .manganese: return String(localized: "Manganese")
        case .vitaminA: return String(localized: "Vitamin A")
        case .vitaminD: return String(localized: "Vitamin D")
        case .vitaminE: return String(localized: "Vitamin E")
        case .vitaminK1: return String(localized: "Vitamin K1")
        case .vitaminC: return String(localized: "Vitamin C")
        case .vitaminB1: return String(localized: "Vitamin B1")
        case .vitaminB2: return String(localized: "Vitamin B2")
        case .vitaminB3: return String(localized: "Vitamin B3")
        case .vitaminB5: return String(localized: "Vitamin B5")
        case .vitaminB6: return String(localized: "Vitamin B6")
        case .vitaminB9: return String(localized: "Vitamin B9")
        case .vitaminB12: return String(localized: "Vitamin B12")
        }
    }

    static func microGroupTitle(_ group: MicroGroup) -> String {
        switch group {
        case .carbsAndFats: return String(localized: "Carbs and fats")
        case .omegas: return String(localized: "Omega-3 and 6")
        case .minerals: return String(localized: "Minerals")
        case .vitamins: return String(localized: "Vitamins")
        }
    }

    /// A number with the precision its size calls for: "0,09", "2,1", "255".
    static func microNumber(_ value: Double) -> String {
        let v = value.isFinite ? max(0, value) : 0
        let digits = v < 0.1 ? 2 : (v < 10 ? 1 : 0)
        return v.formatted(.number.precision(.fractionLength(0...digits)).locale(locale))
    }

    /// An amount in the nutrient's own unit, written in the unit it is shown in: "2,1 µg", "120 mg".
    static func microAmount(_ nutrient: MicroNutrient, _ amount: Double) -> String {
        microNumber(nutrient.shownAmount(amount)) + " " + nutrient.shownUnit.symbol
    }

    /// The reference and the share reached: "/ 15 µg · 14 %", "≤ 5 g · 116 %"; nil without a reference.
    static func microReferenceLine(_ nutrient: MicroNutrient, amount: Double?, reference: Double?) -> String? {
        guard let reference else { return nil }
        let head = (nutrient.isCeiling ? "≤ " : "/ ") + microAmount(nutrient, reference)
        guard let amount, let pct = MicroReference.percent(amount, of: reference) else { return head }
        return head + " · " + NutritionFormat.percentText(pct)
    }

    /// "2 foods without this value", or nil when none lacks it.
    static func missingLine(_ count: Int) -> String? {
        if count <= 0 { return nil }
        if count == 1 { return String(localized: "1 food without this value") }
        return String(localized: "\(count) foods without this value")
    }

    /// The headline micronutrients of one line: "Fiber 9,4 g · Iron 4,4 mg · Vitamin B9 112 µg"; nil when the
    /// line has none.
    static func lineMicroSummary(_ micros: [MicroNutrient: Double]?, limit: Int = 3) -> String? {
        guard let micros, !micros.isEmpty else { return nil }
        let shown = MicroNutrient.headline.filter { (micros[$0] ?? 0) > 0 }.prefix(limit)
        guard !shown.isEmpty else { return nil }
        return shown.map { microName($0) + " " + microAmount($0, micros[$0] ?? 0) }.joined(separator: " · ")
    }
}

/// One nutrient as the screens show it: the amount, the reference, the bar.
struct MicroRowModel: Identifiable, Equatable {
    let nutrient: MicroNutrient
    let amount: Double?
    let reference: Double?
    let missing: Int

    var id: String { nutrient.rawValue }

    /// The share of the reference, uncapped (a ceiling passed reads above 100).
    var percent: Int? { amount.flatMap { MicroReference.percent($0, of: reference) } }

    static func microRow(_ nutrient: MicroNutrient, totals: MicroTotals, sex: String, intakeKcal: Int) -> MicroRowModel {
        MicroRowModel(nutrient: nutrient, amount: totals.amount(nutrient),
                      reference: MicroReference.reference(for: nutrient, sex: sex, intakeKcal: intakeKcal),
                      missing: totals.missingLines(nutrient))
    }
}

/// The bar of a nutrient: the share of its reference; a ceiling has its limit mark at the end.
struct MicroBar: View {
    let row: MicroRowModel

    private var fill: Color {
        let pct = row.percent ?? 0
        if row.nutrient.isCeiling { return pct > 100 ? StrandPalette.deviationOrange : StrandPalette.textSecondary }
        return pct >= 100 ? StrandPalette.statusPositive : StrandPalette.textPrimary
    }

    var body: some View {
        GeometryReader { geo in
            let share = min(1, Double(row.percent ?? 0) / 100)
            ZStack(alignment: .leading) {
                Capsule().fill(StrandPalette.surfaceOverlay)
                Capsule().fill(fill).frame(width: geo.size.width * CGFloat(share))
                if row.nutrient.isCeiling {
                    Rectangle().fill(StrandPalette.textSecondary)
                        .frame(width: 2, height: 12)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// One nutrient line: name, amount, reference and share, the bar, and how many foods lacked the value.
struct MicroLine: View {
    let row: MicroRowModel
    var showMissing = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: MicroFormat.microName(row.nutrient))
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: row.amount.map { MicroFormat.microAmount(row.nutrient, $0) } ?? "—")
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .monospacedDigit()
                if let reference = MicroFormat.microReferenceLine(row.nutrient, amount: row.amount,
                                                                  reference: row.reference) {
                    Text(verbatim: reference)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            if row.reference != nil { MicroBar(row: row) }
            if showMissing, let missing = MicroFormat.missingLine(row.missing) {
                Text(verbatim: missing)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

/// The two views of the day card.
enum MicroCardTab: Hashable {
    case toComplete, ceilings
}

/// The card under the moments: the targets furthest from their reference, or the three ceilings.
struct NutritionMicrosCard: View {
    let totals: MicroTotals
    let sex: String
    let intakeKcal: Int
    let onOpen: () -> Void

    @State private var tab: MicroCardTab = .toComplete

    /// The rows the tab shows: five targets (furthest first), or the three ceilings.
    static func microCardRows(_ tab: MicroCardTab, totals: MicroTotals, sex: String, intakeKcal: Int) -> [MicroRowModel] {
        switch tab {
        case .toComplete:
            return MealMicros.targetShortfall(totals, sex: sex, intakeKcal: intakeKcal).prefix(5).map {
                MicroRowModel.microRow($0.0, totals: totals, sex: sex, intakeKcal: intakeKcal)
            }
        case .ceilings:
            return MicroNutrient.allCases.filter(\.isCeiling).map {
                MicroRowModel.microRow($0, totals: totals, sex: sex, intakeKcal: intakeKcal)
            }
        }
    }

    private var foodsWithout: Int { totals.lineCount - totals.linesWithMicros }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onOpen) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Micronutrients")
                        .font(StrandFont.body.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                    Text("See all ›")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.accent)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens every micronutrient"))

            if totals.linesWithMicros == 0 {
                Text("Log a food from the table or scan a product to see its micronutrients.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
            } else {
                if tab == .toComplete {
                    Text("Furthest from the reference today")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                } else {
                    Text("Ceilings, not to go over")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                Picker(selection: $tab) {
                    Text("To complete").tag(MicroCardTab.toComplete)
                    Text("Ceilings").tag(MicroCardTab.ceilings)
                } label: {
                    Text("Micronutrients")
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 6)
                ForEach(Self.microCardRows(tab, totals: totals, sex: sex, intakeKcal: intakeKcal)) { row in
                    Divider().overlay(StrandPalette.hairline)
                    MicroLine(row: row, showMissing: false)
                }
                Divider().overlay(StrandPalette.hairline)
                footnote
                    .padding(.vertical, 8)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
    }

    @ViewBuilder private var footnote: some View {
        if foodsWithout == 1 {
            Text("1 food without micronutrients (typed by hand) · ANSES references, adult")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if foodsWithout > 1 {
            Text("\(foodsWithout) foods without micronutrients (typed by hand) · ANSES references, adult")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("ANSES references, adult")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
        }
    }
}

/// The period of the detail screen.
enum MicroPeriod: Hashable {
    case day, week
}

/// What the detail screen reads: the lines of the day, and the lines of each of the 7 days up to it.
struct MicroDetailData: Equatable {
    var dayItems: [MealItemRow] = []
    var weekDays: [[MealItemRow]] = []

    /// The day's lines and the seven days ending on `day` (that day included), from the journal.
    static func loadMicroDetail(_ repo: Repository, day: Date) async -> MicroDetailData {
        guard let store = await repo.storeHandle() else { return MicroDetailData() }
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -6, to: day) ?? day
        let fromKey = MealJournal.mealDayKey(start), toKey = MealJournal.mealDayKey(day)
        let entries = (try? await MealJournal.mealJournalRange(store, fromDay: fromKey, toDay: toKey)) ?? []
        var byDay: [String: [MealItemRow]] = [:]
        for entry in entries { byDay[entry.meal.day, default: []] += entry.items }
        let keys = (0..<7).compactMap { cal.date(byAdding: .day, value: -$0, to: day) }.map { MealJournal.mealDayKey($0) }
        return MicroDetailData(dayItems: byDay[toKey] ?? [], weekDays: keys.map { byDay[$0] ?? [] })
    }
}

/// « Micronutrients »: every nutrient of the day, or the 7-day average, in four groups; a tap on a line
/// shows the foods it came from.
struct NutritionMicrosScreen: View {
    let day: Date

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage(MealJournal.revisionKey) private var mealRevision = 0

    @State private var period: MicroPeriod = .day
    @State private var data: MicroDetailData?
    @State private var opened: MicroNutrient?

    var body: some View {
        let plan = NutritionDayReader.currentPlan(profile: profile)
        let loaded = data ?? MicroDetailData()
        let week = MealMicros.dailyAverage(loaded.weekDays)
        let totals = period == .day ? MealMicros.microTotals(loaded.dayItems) : week.totals
        let sourceItems = period == .day ? loaded.dayItems : loaded.weekDays.flatMap { $0 }
        ScreenScaffold(title: "Micronutrients") {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Picker(selection: $period) {
                    Text("Today").tag(MicroPeriod.day)
                    Text("7-day average").tag(MicroPeriod.week)
                } label: {
                    Text("Period")
                }
                .pickerStyle(.segmented)
                periodNote(totals: totals, days: week.days)
                ForEach(MicroGroup.allCases, id: \.self) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: MicroFormat.microGroupTitle(group))
                            .font(StrandFont.sectionTitle)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .padding(.top, 6)
                        VStack(spacing: 0) {
                            let rows = MicroNutrient.allCases.filter { $0.group == group }
                            ForEach(Array(rows.enumerated()), id: \.element) { index, nutrient in
                                if index > 0 { Divider().overlay(StrandPalette.hairline) }
                                detailRow(MicroRowModel.microRow(nutrient, totals: totals, sex: profile.sex,
                                                                 intakeKcal: plan.intakeKcal),
                                          items: sourceItems, average: period == .week ? week.days : nil)
                            }
                        }
                        .padding(.horizontal, 14)
                        .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
                    }
                }
                Text("Values: Anses, Ciqual 2025 table, and Open Food Facts for scanned products. References: ANSES, adult, from your profile. A food without the value is not counted as zero: it is shown under the line. Tap a line to see where it comes from.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: "\(Repository.localDayKey(day))-\(mealRevision)") {
            let read = await MicroDetailData.loadMicroDetail(repo, day: day)
            if !Task.isCancelled { data = read }
        }
    }

    @ViewBuilder private func periodNote(totals: MicroTotals, days: Int) -> some View {
        if period == .day {
            Text("\(totals.linesWithMicros) of \(totals.lineCount) foods with values")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
        } else {
            Text("Days without a meal logged are left out (\(days) of 7 days)")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
        }
    }

    /// One line; a tap shows (or hides) the foods it came from. Over the week, a food's share is its
    /// daily average too (`average` days).
    @ViewBuilder private func detailRow(_ row: MicroRowModel, items: [MealItemRow], average: Int?) -> some View {
        let isOpen = opened == row.nutrient
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(StrandMotion.interactive) { opened = isOpen ? nil : row.nutrient }
            } label: {
                MicroLine(row: row).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen ? Text("Hides the foods") : Text("Shows the foods it comes from"))
            if isOpen {
                let sources = MealMicros.topSources(row.nutrient, in: items)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Where it comes from")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                    if sources.isEmpty {
                        Text("No food with this value")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    ForEach(sources, id: \.name) { source in
                        let amount = source.amount / Double(max(1, average ?? 1))
                        HStack {
                            Text(verbatim: source.name)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(verbatim: MicroFormat.microAmount(row.nutrient, amount))
                                .monospacedDigit()
                        }
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textPrimary)
                    }
                }
                .padding(.bottom, 10)
            }
        }
    }
}

/// The micronutrients a portion brings, as the Portion screen shows them: six headline lines with their
/// share of the day's reference, then « Every micronutrient » folded.
struct NutritionPortionMicros: View {
    let micros: [MicroNutrient: Double]

    /// The profile's sex (`ProfileStore.sex`): the headline nutrients' references do not depend on energy.
    @AppStorage("profile.sex") private var sex = "male"
    @State private var showAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What this portion brings")
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(StrandPalette.textPrimary)
            let headline = MicroNutrient.headline.filter { micros[$0] != nil }.prefix(6)
            ForEach(Array(headline), id: \.self) { nutrient in
                let row = MicroRowModel(nutrient: nutrient, amount: micros[nutrient],
                                        reference: MicroReference.reference(for: nutrient, sex: sex,
                                                                            intakeKcal: 0),
                                        missing: 0)
                HStack(spacing: 10) {
                    Text(verbatim: MicroFormat.microName(nutrient))
                        .font(StrandFont.caption)
                        .frame(width: 110, alignment: .leading)
                    MicroBar(row: row)
                    Text(verbatim: shareText(row))
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .monospacedDigit()
                        .frame(width: 104, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
            Button {
                withAnimation(StrandMotion.interactive) { showAll.toggle() }
            } label: {
                if showAll { Text("Less") } else { Text("Every micronutrient") }
            }
            .font(StrandFont.subhead.weight(.semibold))
            .foregroundStyle(StrandPalette.accent)
            .buttonStyle(.plain)
            if showAll {
                let rest = MicroNutrient.allCases.filter { !headline.contains($0) }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], spacing: 6) {
                    ForEach(rest, id: \.self) { nutrient in
                        HStack {
                            Text(verbatim: MicroFormat.microName(nutrient)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(verbatim: micros[nutrient].map { MicroFormat.microAmount(nutrient, $0) } ?? "—")
                                .monospacedDigit()
                        }
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
            }
            Text("Share of the day's reference (ANSES). « — » = no value in the table, not zero.")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func shareText(_ row: MicroRowModel) -> String {
        let amount = row.amount.map { MicroFormat.microAmount(row.nutrient, $0) } ?? "—"
        guard let pct = row.percent else { return amount }
        return amount + " · " + NutritionFormat.percentText(pct)
    }
}
