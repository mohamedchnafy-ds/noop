import SwiftUI
import Charts
import StrandDesign

// MARK: - Nutrition history (personal fork, chantier 8, lot 3)
//
// Under the day's journal: the 7 or 30 complete days before today, from `NutritionHistoryModel`. Three charts,
// eaten against the current intake goal, the three macros, and the estimated balance. A day with no meal
// written down is left empty, never drawn at 0. Nothing here computes a figure: the days come from
// `NutritionHistory.loadNutritionHistory`, which reads each day as the day page does.

struct NutritionHistoryCard: View {
    let model: NutritionHistoryModel
    let range: NutritionHistoryRange
    var onRange: (NutritionHistoryRange) -> Void = { _ in }
    /// True while the days are being read; the charts wait rather than show a range of holes.
    var loading = false

    init(model: NutritionHistoryModel, range: NutritionHistoryRange,
         onRange: @escaping (NutritionHistoryRange) -> Void = { _ in }, loading: Bool = false) {
        self.model = model
        self.range = range
        self.onRange = onRange
        self.loading = loading
    }

    private var hairline: some View {
        Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
    }

    var body: some View {
        NoopCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.fill")
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.intakeColor)
                        .accessibilityHidden(true)
                    Text("History")
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer(minLength: 8)
                    rangeSwitch
                }
                if loading {
                    Text("Reading the journal…")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                } else if model.loggedDays.isEmpty {
                    Text("No meal written down over these days.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    loggedLine
                    intakeSection
                    hairline
                    macroSection
                    hairline
                    balanceSection
                }
                Text("The days before today. A day with no meal written down stays empty, never 0. Goals are your current ones; the balance is an estimate (eaten − the strap's estimated expenditure).")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Range

    private var rangeSwitch: some View {
        HStack(spacing: 4) {
            ForEach(NutritionHistoryRange.allCases) { option in
                Button {
                    onRange(option)
                } label: {
                    rangeLabel(option)
                        .font(StrandFont.footnote.weight(.semibold))
                        .foregroundStyle(option == range ? StrandPalette.surfaceBase : StrandPalette.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(option == range ? StrandPalette.textPrimary : StrandPalette.hairline))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(option == range ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private func rangeLabel(_ option: NutritionHistoryRange) -> some View {
        switch option {
        case .week: Text("7 days")
        case .month: Text("30 days")
        }
    }

    private var loggedLine: some View {
        Text("\(model.loggedDays.count) of \(model.days.count) days written down")
            .font(StrandFont.subhead)
            .foregroundStyle(StrandPalette.textSecondary)
    }

    // MARK: Intake

    private var intakeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Eaten")
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer(minLength: 8)
                if let average = model.averageKcal {
                    Text("Average")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                    Text(verbatim: NutritionFormat.kcalUnit(average))
                        .font(StrandFont.subhead.weight(.semibold).monospacedDigit())
                        .foregroundStyle(StrandPalette.textPrimary)
                }
            }
            Chart {
                ForEach(model.loggedDays) { day in
                    BarMark(x: .value("Day", day.date, unit: .day),
                            y: .value("kcal", day.eaten?.kcal ?? 0))
                        .foregroundStyle(StrandPalette.intakeColor)
                        .cornerRadius(3)
                }
                if let goal = model.goalKcal {
                    RuleMark(y: .value("Goal", goal))
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .chartXScale(domain: xDomain)
            .chartXAxis { dayAxis }
            .chartYAxis { valueAxis }
            .frame(height: 130)
            if let goal = model.goalKcal {
                legendLine(tint: StrandPalette.textSecondary,
                           text: Text("Current goal: \(NutritionFormat.kcalUnit(goal))"))
            }
        }
    }

    // MARK: Macros

    private var macroSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Macros")
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(StrandPalette.textPrimary)
            Chart {
                ForEach(NutritionMacro.allCases, id: \.self) { macro in
                    ForEach(model.loggedDays) { day in
                        LineMark(x: .value("Day", day.date, unit: .day),
                                 y: .value("g", day.eaten.map { macro.grams($0) } ?? 0),
                                 series: .value("Macro", seriesId(macro, day)))
                            .foregroundStyle(macro.tint)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        PointMark(x: .value("Day", day.date, unit: .day),
                                  y: .value("g", day.eaten.map { macro.grams($0) } ?? 0))
                            .foregroundStyle(macro.tint)
                            .symbolSize(range == .week ? 24 : 10)
                    }
                }
            }
            .chartXScale(domain: xDomain)
            .chartXAxis { dayAxis }
            .chartYAxis { valueAxis }
            .frame(height: 120)
            ForEach(NutritionMacro.allCases, id: \.self) { macro in
                macroAverageRow(macro)
            }
        }
    }

    /// One line per unbroken run of logged days: a hole lifts the pen instead of joining its neighbours.
    private func seriesId(_ macro: NutritionMacro, _ day: NutritionHistoryDay) -> String {
        let index = model.days.firstIndex(where: { $0.dayKey == day.dayKey }) ?? 0
        let holesBefore = model.days[..<index].filter { !$0.isLogged }.count
        return "\(macro.title)-\(holesBefore)"
    }

    private func macroAverageRow(_ macro: NutritionMacro) -> some View {
        let goal = macroGoal(macro)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            NutritionMacroDot(macro: macro)
            Text(verbatim: macro.title)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textPrimary)
            Spacer(minLength: 8)
            if let average = model.averageGrams({ macro.grams($0) }) {
                Text(verbatim: NutritionFormat.gramsUnit(Int(average.rounded())))
                    .font(StrandFont.subhead.weight(.semibold).monospacedDigit())
                    .foregroundStyle(StrandPalette.textPrimary)
            }
            if let goal {
                Text(verbatim: "/ " + NutritionFormat.gramsUnit(goal))
                    .font(StrandFont.footnote.monospacedDigit())
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    private func macroGoal(_ macro: NutritionMacro) -> Int? {
        switch macro {
        case .protein: return model.proteinGoalG
        case .carbs: return model.carbsGoalG
        case .fat: return model.fatGoalG
        }
    }

    // MARK: Balance

    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Estimated balance")
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer(minLength: 8)
                if let average = model.averageBalanceKcal {
                    Text("Average")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                    Text(verbatim: NutritionFormat.signedKcalUnit(average))
                        .font(StrandFont.subhead.weight(.semibold).monospacedDigit())
                        .foregroundStyle(StrandPalette.textPrimary)
                }
            }
            if model.days.contains(where: { $0.balanceKcal != nil }) {
                Chart {
                    ForEach(model.days.filter { $0.balanceKcal != nil }) { day in
                        BarMark(x: .value("Day", day.date, unit: .day),
                                y: .value("kcal", day.balanceKcal ?? 0))
                            .foregroundStyle(StrandPalette.restColor)
                            .cornerRadius(3)
                    }
                    RuleMark(y: .value("Zero", 0))
                        .foregroundStyle(StrandPalette.hairline)
                }
                .chartXScale(domain: xDomain)
                .chartXAxis { dayAxis }
                .chartYAxis { valueAxis }
                .frame(height: 110)
            } else {
                Text("No expenditure measured on the days written down.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    // MARK: Axes

    /// The whole range, logged or not, so a hole keeps its place on the axis.
    private var xDomain: ClosedRange<Date> {
        let cal = Calendar.current
        let first = model.days.first.map { cal.startOfDay(for: $0.date) } ?? Date()
        let lastStart = model.days.last.map { cal.startOfDay(for: $0.date) } ?? first
        let end = cal.date(byAdding: .day, value: 1, to: lastStart) ?? lastStart
        return first...max(end, first.addingTimeInterval(1))
    }

    private var dayAxis: some AxisContent {
        let format: Date.FormatStyle = range == .week
            ? .dateTime.weekday(.narrow)
            : .dateTime.day().month(.defaultDigits)
        return AxisMarks(values: .stride(by: .day, count: range == .week ? 1 : 7)) { _ in
            AxisValueLabel(format: format, centered: true)
                .foregroundStyle(StrandPalette.textTertiary)
                .font(StrandFont.caption2)
        }
    }

    private var valueAxis: some AxisContent {
        AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
            AxisGridLine().foregroundStyle(StrandPalette.hairline.opacity(0.5))
            AxisValueLabel()
                .foregroundStyle(StrandPalette.textTertiary)
                .font(StrandFont.caption2)
        }
    }

    private func legendLine(tint: Color, text: Text) -> some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(tint)
                .frame(width: 14, height: NoopMetrics.hairlineWidth * 2)
                .accessibilityHidden(true)
            text
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
        }
    }
}
