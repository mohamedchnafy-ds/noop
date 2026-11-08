import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore
import Foundation

// MARK: - Trends (fork chantier 16)
//
// The longitudinal screen, rebuilt around one question — how is the body holding up against the
// training — instead of one line chart per metric. One period control drives the whole page (a
// range plus a stepper that walks that range back in whole periods), and five cards read it:
//
//   1. Bilan          — the three scores once, against the previous period, with one sentence.
//   2. Equilibre      — each day as a point on the Charge / Effort plane, in four quadrants.
//   3. Forme          — condition (42 d) · fatigue (7 d) · form, the page's only line chart, plus the
//                       acute / chronic ratio and monotony. Compact while the model is still building.
//   4. Signaux        — HRV, resting HR, respiration, skin temperature and sleep, each against the
//                       wearer's own normal band, one row per signal.
//   5. Jour par jour  — a heat grid, one column per day / week / month, one row per measure.
//
// Every per-metric line chart is still one tap away (a row opens its `MetricDetailView`; the footer
// opens Explore). The pure half — windows, quadrants, bands, grid columns — lives in `TrendsOverview`
// and is pinned by `TrendsOverviewTests`. The cards are split into their own files so no single body
// sits near the iOS type-check budget.
struct TrendsView: View {
    @EnvironmentObject var repo: Repository
    @Environment(\.locale) private var locale
    // NOTE: deliberately does NOT observe LiveState — Trends shows historical data only, and
    // observing it forced a full re-render of this subtree on every ~1 Hz live-HR tick.

    // The shared range control: W(7) / M(30) / 3M(90) / 6M(180) / 1Y(365) / ALL. `.all` is kept for the
    // Today host cards' widening fallback (`HostedTrendData`); the page itself offers the five stepped
    // ranges (`pills`), since "all history" has no previous period to compare with or step through.
    enum Range: Int, CaseIterable, Identifiable {
        case week = 7, month = 30, quarter = 90, half = 180, year = 365, all = 0
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .week:    return String(localized: "W")
            case .month:   return String(localized: "M")
            case .quarter: return String(localized: "3M")
            case .half:    return String(localized: "6M")
            case .year:    return String(localized: "1Y")
            case .all:     return String(localized: "ALL")
            }
        }
        /// Trailing-day window, or nil for "all history".
        var days: Int? { self == .all ? nil : rawValue }

        /// The ranges the page's selector offers.
        static let pills: [Range] = [.week, .month, .quarter, .half, .year]

        /// This range plus every LARGER range, ascending — the auto-expand search
        /// order when the selected window holds zero points.
        var widening: [Range] {
            let order: [Range] = [.week, .month, .quarter, .half, .year, .all]
            guard let i = order.firstIndex(of: self) else { return [.all] }
            return Array(order[i...])
        }
    }

    @State private var range: Range = .week
    /// Whole periods stepped back from the one containing today (0 = current). Reset on a range change.
    @State private var offset = 0

    // #436 — shareable offline trends report (PDF over a date range). The sheet owns its
    // own range picker; this just presents it with the loaded history.
    @State private var showingReport = false
    /// Current appearance, passed into the off-screen Bilan render so the shared PNG matches the app.
    @Environment(\.colorScheme) private var colorScheme

    /// Rest's per-day series, keyed by "yyyy-MM-dd". Rest is the sleep_performance COMPOSITE (the same
    /// number the Today Rest score shows, #614 / #732), loaded once and keyed by day.
    @State private var sleepPerfByDay: [String: Double] = [:]
    /// The sleep need the Signals card prints beside the period's sleep, from the shared synthesis.
    @State private var sleepNeedMin: Double?

    // Effort display scale (#268) — routes every Effort number on the page. Display-only.
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    private var today: String { Repository.localDayKey(Date()) }

    // MARK: Period

    private var window: TrendsOverview.Window? {
        TrendsOverview.window(range: range, offset: offset, today: today)
    }

    private var maxOffset: Int {
        TrendsOverview.maxOffset(range: range, earliestDay: repo.days.first?.day, today: today)
    }

    /// Everything the cards read, resolved once per body from the current period.
    private var periodData: TrendsPeriodData {
        let w = window
        let current = TrendsOverview.days(repo.days, in: w)
        let previous = w.map { TrendsOverview.days(repo.days, in: TrendsOverview.previous($0)) } ?? []
        let bandWindow = w.map { TrendsOverview.bandWindow(for: $0, range: range) }
        let band = bandWindow.map { TrendsOverview.days(repo.days, in: $0) } ?? repo.days
        return TrendsPeriodData(range: range, window: w, current: current, previous: previous,
                                bandDays: band, restByDay: sleepPerfByDay, sleepNeedMin: sleepNeedMin,
                                effortScale: effortScale, today: today)
    }

    var body: some View {
        // On macOS the .trends detail pane has NO enclosing NavigationStack (RootView), so — exactly like
        // MetricExplorerView (#753) — wrap the scaffold in one here so the row pushes get Back chrome.
        #if os(macOS)
        NavigationStack { scaffold.tabRouteDestinations() }
        #else
        scaffold
        #endif
    }

    private var scaffold: some View {
        ScreenScaffold(title: "Trends", subtitle: "Form, balance and signals over time.",
                       onRefresh: { await repo.refresh() },
                       lazy: true,
                       trailing: { shareButton },
                       content: {
            if repo.days.isEmpty {
                ComingSoon(what: repo.loaded
                    ? "Trends need history to draw. Import your WHOOP export in Data Sources to see weeks, months and years instantly."
                    : "Loading your history…")
            } else {
                let data = periodData
                VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                    Group {
                        periodControl
                            .staggeredAppear(index: 0)
                        if data.current.isEmpty {
                            DataPendingNote(
                                title: "No readings in this period",
                                message: "Step to another period with the arrows above to see its review.")
                            .staggeredAppear(index: 1)
                        } else {
                            TrendsBilanCard(data: data, comparisonLabel: comparisonLabel)
                                .staggeredAppear(index: 1)
                            TrendsBalanceCard(data: data)
                                .staggeredAppear(index: 2)
                        }
                        // Long-horizon by nature: the model runs over the FULL history and the card only
                        // frames the period, so it stays on the page even when the period itself is empty.
                        TrendsFormeCard(days: repo.days, window: data.window)
                            .staggeredAppear(index: 3)
                        if !data.current.isEmpty {
                            TrendsSignalsCard(data: data)
                                .staggeredAppear(index: 4)
                            TrendsGridCard(data: data)
                                .staggeredAppear(index: 5)
                        }
                        footerRows
                            .staggeredAppear(index: 6)
                    }
                }
            }
        })
        // #436 — present the offline trends-report exporter (range picker + PDF export).
        .sheet(isPresented: $showingReport) {
            TrendsReportSheet(days: repo.days)
        }
        // #732 — load the resolved sleep_performance series so Rest reads the SAME composite the Today
        // Rest score uses (not raw efficiency), plus the sleep need the Signals card prints. Keyed on the
        // day count so a newly-banked/-scored night refreshes both reactively.
        .task(id: repo.days.count) {
            let s = await repo.exploreSeries(key: "sleep_performance", source: "my-whoop")
            sleepPerfByDay = Dictionary(s.map { ($0.day, $0.value) }, uniquingKeysWith: { _, last in last })
            sleepNeedMin = await repo.sleepSynthesisFigures()?.needMin
        }
        .onChange(of: range) { _ in offset = 0 }
    }

    // MARK: Header share

    /// Shares the Bilan as an image: the same off-screen render path as the old weekly recap, so the
    /// PNG is the card the page shows. Hidden while there is nothing to share.
    @ViewBuilder
    private var shareButton: some View {
        if !repo.days.isEmpty, !periodData.current.isEmpty {
            Button {
                let data = periodData
                let page = TrendsBilanCard(data: data, comparisonLabel: comparisonLabel)
                    .frame(width: 380)
                    .padding(24)
                    .background(StrandPalette.surfaceBase)
                    .environment(\.colorScheme, colorScheme)
                let stamp = data.window?.end ?? today
                TrendsReportRenderer.exportPNG(page: page, suggestedName: "noop-bilan-\(stamp).png")
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .frame(width: NoopMetrics.compactControlSize, height: NoopMetrics.compactControlSize)
            }
            .nativeLiquidGlassHeaderButton()
            .accessibilityLabel("Share the summary")
        }
    }

    // MARK: Period control

    /// The range pills plus a stepper that walks the chosen range back in whole periods. ONE clock for
    /// the whole page: every card below reads `window`, so a week's Bilan, its points, its signals and
    /// its grid are the same seven days.
    private var periodControl: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            SegmentedPillControl(Range.pills, selection: $range,
                                 adaptsToAvailableWidth: true, fillsAvailableWidth: true) { $0.label }
            HStack(spacing: NoopMetrics.cardInnerSpacing) {
                Button { offset = min(maxOffset, offset + 1) } label: {
                    Image(systemName: "chevron.left").font(StrandFont.headline.weight(.semibold))
                        .frame(width: NoopMetrics.controlHeight - 4, height: NoopMetrics.controlHeight - 4)
                }
                .buttonStyle(.plain)
                .foregroundStyle(offset >= maxOffset ? StrandPalette.textTertiary : StrandPalette.accent)
                .disabled(offset >= maxOffset)
                .accessibilityLabel("Previous period")

                Spacer(minLength: 0)
                VStack(spacing: 2) {
                    Text(periodTitle)
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(periodSubtitle)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .multilineTextAlignment(.center)
                Spacer(minLength: 0)

                Button { offset = max(0, offset - 1) } label: {
                    Image(systemName: "chevron.right").font(StrandFont.headline.weight(.semibold))
                        .frame(width: NoopMetrics.controlHeight - 4, height: NoopMetrics.controlHeight - 4)
                }
                .buttonStyle(.plain)
                .foregroundStyle(offset <= 0 ? StrandPalette.textTertiary : StrandPalette.accent)
                .disabled(offset <= 0)
                .accessibilityLabel("Next period")
            }
            .accessibilityElement(children: .contain)
        }
    }

    /// "This week" / "Last week" / "3 weeks ago" for weeks; "Last 30 days" style for the other ranges,
    /// their stepped periods named by their dates.
    private var periodTitle: String {
        switch range {
        case .week:
            if offset == 0 { return String(localized: "This week") }
            if offset == 1 { return String(localized: "Last week") }
            return String(localized: "\(offset) weeks ago")
        case .all:
            return String(localized: "All history")
        default:
            if offset == 0, let n = range.days { return String(localized: "Last \(n) days") }
            return window.map(TrendsFormat.dateRange) ?? ""
        }
    }

    /// The dates and how many of the period's days hold a reading.
    private var periodSubtitle: String {
        guard let w = window else { return String(localized: "\(repo.days.count) days") }
        let n = TrendsOverview.days(repo.days, in: w).count
        let days = String(localized: "\(n)/\(w.dayCount) days")
        if range != .week, offset > 0 { return days }
        return "\(TrendsFormat.dateRange(w)) · \(days)"
    }

    /// The Bilan's comparison caption: what the deltas are measured against.
    private var comparisonLabel: String {
        switch range {
        case .week: return String(localized: "vs previous week")
        case .month: return String(localized: "vs previous 30 days")
        case .quarter: return String(localized: "vs previous 3 months")
        case .half: return String(localized: "vs previous 6 months")
        case .year: return String(localized: "vs previous year")
        case .all: return ""
        }
    }

    // MARK: Footer — what moved one level down

    /// The per-metric charts and the PDF report, as two plain rows: still here, no longer on the page.
    private var footerRows: some View {
        NoopCard(padding: 0) {
            VStack(spacing: 0) {
                NavigationLink(value: TabRoute.metricExplorer) {
                    footerRow(icon: "chart.xyaxis.line", title: "Explore a metric",
                              detail: "The full curve of Charge, HRV, resting HR, Effort and more.")
                }
                .buttonStyle(.plain)
                Divider().overlay(StrandPalette.hairline).padding(.leading, NoopMetrics.space10 + NoopMetrics.space3)
                Button { showingReport = true } label: {
                    footerRow(icon: "doc.richtext", title: "Export the report",
                              detail: "A one-page PDF over the chosen range, saved on your \(Platform.deviceNoun).")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func footerRow(icon: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(spacing: NoopMetrics.space3) {
            Image(systemName: icon)
                .font(StrandFont.title2)
                .foregroundStyle(StrandPalette.accent)
                .frame(width: NoopMetrics.space10)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: NoopMetrics.spaceHalf) {
                Text(title).font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                Text(detail).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: NoopMetrics.space2)
            Image(systemName: "chevron.right")
                .font(StrandFont.footnote.weight(.semibold))
                .foregroundStyle(StrandPalette.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, NoopMetrics.cardInnerPadding)
        .padding(.vertical, NoopMetrics.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - Shared period data

/// Everything the Trends cards read, resolved once per body by `TrendsView` so the five cards cannot
/// disagree about which days a period covers (AGENTS.md: two readouts of one fact must not be able to
/// disagree — one funnel, one clock).
struct TrendsPeriodData {
    let range: TrendsView.Range
    /// nil = all history.
    let window: TrendsOverview.Window?
    /// The period's banked days, oldest first.
    let current: [DailyMetric]
    /// The previous period's days (empty for all-history).
    let previous: [DailyMetric]
    /// The days the personal normal band is folded from (`TrendsOverview.bandWindow`).
    let bandDays: [DailyMetric]
    /// sleep_performance by day key (the Rest composite).
    let restByDay: [String: Double]
    let sleepNeedMin: Double?
    let effortScale: EffortScale
    let today: String

    func rest(_ d: DailyMetric) -> Double? { restByDay[d.day] }
}

// MARK: - Formatting shared by the cards

enum TrendsFormat {
    /// Day keys are banked as `yyyy-MM-dd` in UTC; parsing them any other way shifts every date.
    static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func date(_ day: String) -> Date? { dayParser.date(from: day) }

    private static func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = AppClock.activeLocale
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    /// "2–8 Nov" when both ends share a month, "26 Oct–1 Nov" otherwise, in the app's locale.
    static func dateRange(_ w: TrendsOverview.Window) -> String {
        guard let a = date(w.start), let b = date(w.end) else { return "\(w.start)–\(w.end)" }
        let dayMonth = formatter("d MMM")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? cal.timeZone
        let sameMonth = cal.isDate(a, equalTo: b, toGranularity: .month)
        if sameMonth {
            return "\(formatter("d").string(from: a))–\(dayMonth.string(from: b))"
        }
        return "\(dayMonth.string(from: a))–\(dayMonth.string(from: b))"
    }

    /// "Mon 2 Nov" for a grid column's selected day.
    static func longDay(_ day: String) -> String {
        guard let d = date(day) else { return day }
        return formatter("EEE d MMM").string(from: d)
    }

    /// "nov." style month label.
    static func shortMonth(_ day: String) -> String {
        guard let d = date(day) else { return day }
        return formatter("MMM").string(from: d)
    }

    /// The weekday's narrow letter ("M", "L"), for the week grid's header.
    static func weekdayLetter(_ day: String) -> String {
        guard let d = date(day) else { return "" }
        return formatter("EEEEE").string(from: d)
    }

    static func int(_ v: Double) -> String { "\(Int(v.rounded()))" }

    /// "+4" / "−9", to `places` decimals in the app's locale.
    static func signed(_ v: Double, places: Int = 0) -> String {
        let magnitude = places == 0 ? int(abs(v)) : UnitFormatter.decimal(abs(v), places: places)
        if abs(v) < (places == 0 ? 0.5 : 0.05) { return magnitude }
        return (v < 0 ? "−" : "+") + magnitude
    }

    /// "+22 %" / "−15 %" in the app's locale (the locale decides the space before the sign).
    static func signedPercent(_ p: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .percent
        f.maximumFractionDigits = 0
        f.locale = AppClock.activeLocale
        let magnitude = f.string(from: NSNumber(value: abs(p) / 100)) ?? "\(Int(abs(p).rounded()))%"
        if abs(p) < 0.5 { return magnitude }
        return (p < 0 ? "−" : "+") + magnitude
    }

    /// The chip colour of a change: green when it moved the way this metric likes, rose when not,
    /// neutral when the metric has no direction (Effort) or did not move.
    static func changeColor(_ delta: Double, higherIsBetter: Bool?) -> Color {
        guard let better = higherIsBetter, abs(delta) > 0.0001 else { return StrandPalette.textTertiary }
        return (delta > 0) == better ? StrandPalette.statusPositive : StrandPalette.metricRose
    }
}

#if DEBUG
@MainActor
private func previewRepo() -> Repository {
    let repo = Repository(deviceId: "preview")
    let cal = Calendar(identifier: .gregorian)
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.timeZone = TimeZone(identifier: "UTC")
    fmt.dateFormat = "yyyy-MM-dd"
    let today = Date()
    var seeded: [DailyMetric] = []
    let span = 365 * 3
    for i in stride(from: span - 1, through: 0, by: -1) {
        guard let d = cal.date(byAdding: .day, value: -i, to: today) else { continue }
        let phase = Double(span - 1 - i)
        let rec = 55 + 28 * sin(phase / 11.0) + Double((Int(phase) * 31) % 17) - 8
        let hrv = 58 + 16 * sin(phase / 9.0) + Double((Int(phase) * 13) % 11) - 5
        let rhr = 52 + 4 * sin(phase / 7.0) + Double((Int(phase) * 7) % 5) - 2
        let strain = 45 + 30 * sin(phase / 5.0 + 1.2) + Double((Int(phase) * 5) % 4) - 2
        let gap = Int(phase) % 23 == 0
        seeded.append(DailyMetric(
            day: fmt.string(from: d),
            totalSleepMin: 420 + 30 * sin(phase / 3), efficiency: 0.9, deepMin: 90, remMin: 110, lightMin: 200,
            disturbances: 6, restingHr: gap ? nil : Int(rhr.rounded()),
            avgHrv: gap ? nil : max(15, hrv), recovery: gap ? nil : max(2, min(99, rec)),
            strain: gap ? nil : max(0, min(100, strain)), exerciseCount: 1
        ))
    }
    repo.days = seeded
    repo.loaded = true
    return repo
}

#Preview("Trends") {
    TrendsView()
        .environmentObject(previewRepo())
        .environmentObject(LiveState())
        .frame(width: 960, height: 960)
        .preferredColorScheme(.dark)
}
#endif
