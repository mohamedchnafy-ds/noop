import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Your nights: sleep debt + hours per night (#today-hosted-cards)
//
// The Sleep tab's debt card, a standalone view so the Today tab can host it too. Both surfaces render
// THIS view from the SAME `SleepModel`, so the recency-weighted estimate can never differ between them
// (the parity contract). Nothing is recomputed here: the ledger and the 30-day series come from
// `SleepModel.build`.
//
// Personal fork: the ledger and the 30-day hours trend are one card. The headline is the debt with one
// plain sentence on how it is counted (a share of each shortfall carries to the next night), then the
// hours of each night as bars against the need, over 14 nights or 30 days.

struct SleepDebtLedgerCard: View {
    let model: SleepModel

    var body: some View {
        SleepNightsCard(data: SleepNightsData(ledger: model.sleepDebtLedger, month: model.trendPoints))
    }
}

/// What the card draws, built from the ledger and the 30-day series without new arithmetic beyond
/// lining nights up by day.
struct SleepNightsData {
    struct Night: Equatable {
        let day: String
        let minutes: Double
    }

    var debtMinutes: Double
    var isDebt: Bool
    var needMinutes: Double
    /// How far the latest counted night fell short of the need, when it did.
    var lastShortfallMinutes: Double?
    var recent: [Night]
    var month: [Night]

    init(debtMinutes: Double, isDebt: Bool, needMinutes: Double, lastShortfallMinutes: Double?,
         recent: [Night], month: [Night]) {
        self.debtMinutes = debtMinutes
        self.isDebt = isDebt
        self.needMinutes = needMinutes
        self.lastShortfallMinutes = lastShortfallMinutes
        self.recent = recent
        self.month = month
    }

    init(ledger: SleepDebtLedger, month: [TrendPoint]) {
        let last = ledger.nights.last
        self.init(debtMinutes: ledger.magnitudeMin,
                  isDebt: ledger.isDebt && ledger.magnitudeMin >= SleepDebt.onTargetBandMin,
                  needMinutes: ledger.needMin,
                  lastShortfallMinutes: last.flatMap { $0.deltaMin < 0 ? -$0.deltaMin : nil },
                  recent: ledger.nights.map { Night(day: $0.day, minutes: $0.sleptMin) },
                  month: month.map { Night(day: SleepNightsData.dayKey($0.date), minutes: $0.value * 60) })
    }

    var nightCount: Int { recent.count }

    /// `n` calendar days ending on the newest night of either series, each with its minutes or nil.
    func slots(_ n: Int, from nights: [Night]) -> [(day: String, minutes: Double?)] {
        let newest = (recent.map(\.day) + month.map(\.day)).max()
        guard let newest, let end = Self.parser.date(from: newest) else { return [] }
        let byDay = Dictionary(nights.map { ($0.day, $0.minutes) }, uniquingKeysWith: { _, b in b })
        return (0..<n).reversed().map { back in
            let date = Self.utc.date(byAdding: .day, value: -back, to: end) ?? end
            let key = Self.dayKey(date)
            return (key, byDay[key])
        }
    }

    static func dayKey(_ date: Date) -> String { parser.string(from: date) }

    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        return c
    }()

    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

struct SleepNightsCard: View {
    enum Span: Hashable { case nights14, days30 }

    let data: SleepNightsData
    @State var range: Span = .nights14

    private var carryPercent: Int { Int((SleepDebt.debtCarryFactor * 100).rounded()) }

    var body: some View {
        NoopCard(tint: StrandPalette.restColor) {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                HStack(spacing: NoopMetrics.space2) {
                    Text("Your nights").strandOverline()
                    Spacer(minLength: NoopMetrics.space2)
                    SegmentedPillControl([Span.nights14, Span.days30], selection: $range) {
                        $0 == .nights14 ? String(localized: "14 nights") : String(localized: "30 days")
                    }
                    .fixedSize()
                }
                if data.recent.isEmpty && data.month.isEmpty {
                    Text("No nights with sleep data yet. Your ledger fills in as you wear the strap to bed.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    headline
                    let n = range == .nights14 ? 14 : 30
                    let slots = data.slots(n, from: range == .nights14 ? data.recent : data.month)
                    SleepNightsBars(slots: slots.map { $0.minutes }, needMinutes: data.needMinutes)
                        .frame(height: 132)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(barsSummary(slots.compactMap { $0.minutes }, of: n)))
                    dateRow(slots.map { $0.day })
                    stats(slots.compactMap { $0.minutes }, of: n)
                }
            }
        }
    }

    // MARK: Parts

    @ViewBuilder
    private var headline: some View {
        VStack(alignment: .leading, spacing: 4) {
            if data.isDebt {
                (Text("Sleep debt").foregroundColor(StrandPalette.textPrimary)
                 + Text(verbatim: " ").foregroundColor(StrandPalette.textPrimary)
                 + Text(approximately(data.debtMinutes)).foregroundColor(StrandPalette.restBright))
                    .font(StrandFont.rounded(20, weight: .semibold))
                if let short = data.lastShortfallMinutes {
                    Text("You were \(SleepDurationText.format(short)) short of \(SleepDurationText.format(data.needMinutes)) on the last night. \(carryPercent)% of a shortfall carries over to the next night: that is your debt.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("\(carryPercent)% of a shortfall carries over to the next night. Sleeping your need plus the debt clears it.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("No sleep debt")
                    .font(StrandFont.rounded(20, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("Your recent nights covered your \(SleepDurationText.format(data.needMinutes)) of need.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "≈ 2h 23m": the debt is an estimate, and says so.
    private func approximately(_ minutes: Double) -> String {
        String(localized: "≈ \(SleepDurationText.format(minutes))")
    }

    private func dateRow(_ days: [String]) -> some View {
        HStack {
            Text(days.first.map(SleepModel.shortDayLabel) ?? "")
            Spacer()
            Text(days.isEmpty ? "" : SleepModel.shortDayLabel(days[days.count / 2]))
            Spacer()
            Text(days.last.map(SleepModel.shortDayLabel) ?? "")
        }
        .font(StrandFont.caption)
        .foregroundStyle(StrandPalette.textSecondary)
        .accessibilityHidden(true)
    }

    private func stats(_ values: [Double], of n: Int) -> some View {
        let mean = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        return VStack(spacing: NoopMetrics.space3) {
            Divider().overlay(StrandPalette.hairline)
            HStack(alignment: .top) {
                stat(String(localized: "Average"), mean.map(SleepDurationText.format) ?? "—")
                stat(String(localized: "Need"), SleepDurationText.format(data.needMinutes))
                stat(String(localized: "Nights"), String(localized: "\(values.count) / \(n)"))
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
            Text(value)
                .font(StrandFont.number(15))
                .foregroundStyle(StrandPalette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func barsSummary(_ values: [Double], of n: Int) -> String {
        let mean = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        return String(localized: "Hours asleep per night: \(values.count) of \(n) nights recorded, average \(SleepDurationText.format(mean)), need \(SleepDurationText.format(data.needMinutes))")
    }
}

/// The bars: one slot per day, the minutes asleep as a bar, the need as a dashed line, the part of the
/// need a night did not cover as a dashed outline, an empty day as a dot.
struct SleepNightsBars: View {
    let slots: [Double?]
    let needMinutes: Double

    var body: some View {
        Canvas { ctx, size in
            guard !slots.isEmpty else { return }
            let top: CGFloat = 16
            let maxMin = max(needMinutes * 1.3, (slots.compactMap { $0 }.max() ?? 0) * 1.08, 60)
            func y(_ m: Double) -> CGFloat { size.height - CGFloat(m / maxMin) * (size.height - top) }
            let slot = size.width / CGFloat(slots.count)
            let barW = min(14, slot * 0.6)

            var base = Path()
            base.move(to: CGPoint(x: 0, y: size.height - 0.5))
            base.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
            ctx.stroke(base, with: .color(StrandPalette.hairline), lineWidth: 1)

            let needY = y(needMinutes)
            var needLine = Path()
            needLine.move(to: CGPoint(x: 0, y: needY))
            needLine.addLine(to: CGPoint(x: size.width, y: needY))
            ctx.stroke(needLine, with: .color(StrandPalette.textSecondary.opacity(0.7)),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            let needText = ctx.resolve(Text("need \(SleepDurationText.format(needMinutes))")
                .font(StrandFont.caption).foregroundColor(StrandPalette.textSecondary))
            ctx.draw(needText, at: CGPoint(x: 0, y: needY - 3), anchor: .bottomLeading)

            for (i, value) in slots.enumerated() {
                let cx = slot * (CGFloat(i) + 0.5)
                guard let value, value > 0 else {
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - 2, y: size.height - 6, width: 4, height: 4)),
                             with: .color(StrandPalette.hairlineStrong))
                    continue
                }
                if value < needMinutes {
                    let gap = CGRect(x: cx - barW / 2, y: needY, width: barW, height: max(0, y(value) - needY))
                    ctx.stroke(Path(roundedRect: gap, cornerRadius: 3), with: .color(StrandPalette.textSecondary.opacity(0.8)),
                               style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
                let bar = CGRect(x: cx - barW / 2, y: y(value), width: barW, height: size.height - y(value))
                ctx.fill(Path(roundedRect: bar, cornerRadius: 3), with: .color(StrandPalette.restBright))
            }
        }
    }
}
