import XCTest
import SwiftUI
import AppKit
@testable import Strand
import StrandDesign
import WhoopStore

/// Renders the redesigned Today screen to PNG at iPhone width, in dark mode — the visual check against
/// the mockups (canvas "NOOP – Écran Aujourd'hui", final version) before an .ipa is built (personal fork).
///
/// The values are a morning like Sun 1 Nov 2026: Charge calibrating (1 of 4 nights), Effort 0 with a 12–14
/// target, Rest 66 after 3h 41m asleep, resting heart rate 62 and HRV 41 against made-up 30-night ranges,
/// a 2h 23m debt against an 8 h need. The views, their layout and their tokens are the real ones; only the
/// header's round controls are stand-ins (the real ones read the strap and the router).
///
/// Always rendered, so a screen that cannot be drawn fails here. The PNGs are written only when
/// `NOOP_RENDER_DIR` is set — by the fork's render workflow, which publishes them.
@MainActor
final class TodayScreenRenderTests: XCTestCase {

    private let width: CGFloat = 390

    private var dayStart: Int {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 1)) ?? Date()
        return Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970)
    }

    // MARK: Pieces

    private func header() -> some View {
        TodayHeaderLayout(date: "dimanche 1 novembre", title: String(localized: "Today"), onTitleTap: {}) {
            HStack(spacing: NoopMetrics.space1) {
                ForEach(["person.crop.circle.fill", "plus", "battery.75percent", "slider.horizontal.3"], id: \.self) { symbol in
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .frame(width: NoopMetrics.compactControlSize, height: NoopMetrics.compactControlSize)
                        .background(Circle().fill(StrandPalette.surfaceOverlay))
                        .overlay(Circle().strokeBorder(StrandPalette.hairline, lineWidth: NoopMetrics.hairlineWidth))
                }
            }
        }
    }

    private var heroModel: TodayHeroModel {
        TodayHeroModel(
            charge: .init(label: String(localized: "Charge"), score: nil, tint: StrandPalette.chargeColor,
                          caption: String(localized: "calibration"), calibration: (done: 1, of: 4),
                          route: nil, guide: .charge),
            effort: .init(label: String(localized: "Effort"), score: 0, tint: StrandPalette.effortColor,
                          maxValue: 21, decimals: 1, caption: String(localized: "target \(12)–\(14)"),
                          targetRange: 12...14, route: nil, guide: .effort),
            rest: .init(label: String(localized: "Rest"), score: 66, tint: StrandPalette.restColor,
                        caption: SleepDurationText.format(221), route: nil, guide: .rest),
            calories: (TodayEnergy.Split(restingKcal: 760, activityKcal: 185), 480),
            restingHR: .init(value: 62, low: 57, high: 66, normal: 58...64),
            hrv: .init(value: 41, low: 32, high: 58, normal: 38...50),
            sourceLabel: "WHOOP")
    }

    private func hero() -> some View {
        TodayHeroCard(model: heroModel, animated: false, onGuide: { _ in })
    }

    private func liveBpm(_ t: Double, alert: Bool) -> Double {
        if alert {
            let rise: Double = 13 * (1 - exp(-t / 30))
            let ripple: Double = 2 * sin(t / 4)
            return 86 + rise + ripple
        }
        let wave: Double = 6 * sin(t / 9) - 4 * cos(t / 23)
        let climb: Double = t > 70 ? (t - 70) * 0.3 : 0
        return 69 + wave + climb
    }

    private func liveSamples(alert: Bool) -> [(ts: Int, bpm: Double)] {
        let now = dayStart + 10 * 3600
        var out: [(ts: Int, bpm: Double)] = []
        for i in 0..<90 {
            out.append((ts: now - 89 + i, bpm: liveBpm(Double(i), alert: alert)))
        }
        return out
    }

    private func hrCard<Card: View>(mode: TodayHRMode, @ViewBuilder card: () -> Card) -> some View {
        VStack(spacing: 8) {
            TodayHRSectionHead(mode: .constant(mode), liveEnabled: true)
            card()
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NoopPanelSurface(cornerRadius: 22))
        }
    }

    private func liveCard() -> some View {
        let samples = liveSamples(alert: false)
        let values = samples.map(\.bpm)
        return hrCard(mode: .live) {
            TodayHRCardBody(
                tint: StrandPalette.liquidHeart, bpm: 75, showsBeat: true,
                subtitle: String(localized: "Live · resting zone"),
                chart: TodayHRCardLogic.liveChart(samples: samples, band: 62...71, alert: nil),
                lineWidth: 2.5, emptyText: "",
                caption: [.init(text: String(localized: "rest \(62) → usual \(71)"))],
                stats: (values.min(), values.reduce(0, +) / Double(values.count), values.max()))
        }
    }

    private func alertCard() -> some View {
        let samples = liveSamples(alert: true)
        let values = samples.map(\.bpm)
        let crossing = TodayHRAlert.Crossing(side: .high, threshold: 91, sinceTs: samples[samples.count - 1].ts - 240)
        return hrCard(mode: .live) {
            TodayHRCardBody(
                tint: StrandPalette.statusWarning, bpm: 98, showsBeat: true,
                subtitle: String(localized: "Higher than usual at rest · \(4) min"), subtitleIsWarning: true,
                chart: TodayHRCardLogic.liveChart(samples: samples, band: 62...71, alert: crossing),
                lineWidth: 2.5, emptyText: "",
                caption: [.init(text: String(localized: "rest \(62) → usual \(71)")),
                          .init(text: String(localized: "threshold \(91)"), isWarning: true)],
                stats: (values.min(), values.reduce(0, +) / Double(values.count), values.max()))
        }
    }

    /// The made-up night at minute `m` after midnight: awake until 01:51, asleep to 06:04, a spike at waking.
    private func dayBpm(_ m: Double) -> Double {
        if m < 111 {
            let drift: Double = m / 40
            return 66 - drift + 3 * sin(m / 9)
        }
        if m < 364 {
            let slow: Double = 3 * sin((m - 111) / 60)
            return 60 - slow + 1.5 * sin(m / 7)
        }
        if m < 375 { return 104 - (m - 364) * 3 }
        return 72 + 4 * sin(m / 6)
    }

    /// The made-up usual day at hour `h`.
    private func usualBpm(_ h: Double) -> Double {
        if h < 1.5 { return 68 - h * 5 }
        if h < 6.3 { return 59.5 }
        return h < 6.6 ? 66 : 70
    }

    /// Midnight → 06:50 in 5-minute buckets.
    private var dayInput: TodayHRDayInput {
        let start = dayStart
        var ts: [Int] = [], bpm: [Double] = []
        for i in 0..<83 {
            ts.append(start + i * 300)
            bpm.append(dayBpm(Double(i * 5)))
        }
        var habitual: [Int: Double] = [:]
        for slot in 0..<288 {
            habitual[slot] = usualBpm(Double(slot) / 12)
        }
        return TodayHRDayInput(bucketTs: ts, bucketBpm: bpm,
                               segments: hrGapSegments(bucketTs: ts, bucketSeconds: 300),
                               dayStart: start, domainEnd: start + 82 * 300, isToday: true,
                               habitual: habitual, restingHR: 62, awakeFloor: 54,
                               sleep: [(start + 111 * 60)...(start + 364 * 60)])
    }

    private func dayCard() -> some View {
        let day = dayInput
        return hrCard(mode: .day) {
            TodayHRCardBody(
                tint: StrandPalette.liquidHeart, bpm: 75,
                subtitle: String(localized: "5-minute average · since midnight"),
                chart: TodayHRCardLogic.dayChart(day, zone: .current), lineWidth: 2, emptyText: "",
                caption: [.init(text: String(localized: "your usual day"), swatch: .usualDay),
                          .init(text: String(localized: "sleep"), swatch: .sleep),
                          .init(text: String(localized: "rest \(62)"))],
                stats: (day.bucketBpm.min(), day.bucketBpm.reduce(0, +) / Double(day.bucketBpm.count),
                        day.bucketBpm.max()))
        }
    }

    private func synthesis() -> some View {
        let nights = SleepNightsData(debtMinutes: 143, isDebt: true, needMinutes: 480, lastShortfallMinutes: 259,
                                     recent: [.init(day: "2026-11-01", minutes: 221)], month: [])
        var rows = [
            TodaySynthesisLogic.debtRow(nights),
            TodaySynthesisLogic.sessionRow(.init(name: "Full body A", state: .next, supersets: 4, singles: 1,
                                                 typicalMinutes: 50), route: nil),
            TodaySynthesisLogic.bedtimeRow(wakeMinutes: 6 * 60 + 4, needMinutes: 480, format: TodaySynthesisLogic.clock),
        ]
        for i in rows.indices { rows[i].route = nil }   // no NavigationStack in a one-pass render
        return TodaySynthesisCard(rows: rows)
    }

    private func keyMetrics() -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("KEY METRICS").font(StrandFont.overline).tracking(1.6).foregroundStyle(StrandPalette.textTertiary)
                Spacer()
                Text(String(localized: "Edit").uppercased()).font(StrandFont.overlineScaled(11)).tracking(1.0)
                    .foregroundStyle(StrandPalette.accent)
            }
            .padding(.horizontal, 2)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: NoopMetrics.gap), count: 2),
                      spacing: NoopMetrics.gap) {
                LiquidKeyMetricTile(label: String(localized: "Respiratory"), icon: "lungs.fill", value: "17,8",
                                    unit: "rpm", tint: StrandPalette.accent, frac: 17.8 / 24)
                LiquidKeyMetricTile(label: String(localized: "Blood Oxygen"), icon: "drop.fill",
                                    value: LiquidTodayView.noValueDash, unit: "%", tint: StrandPalette.metricCyan, frac: nil)
                LiquidKeyMetricTile(label: String(localized: "Steps"), icon: "figure.walk",
                                    value: LiquidTodayView.noValueDash, unit: "", tint: StrandPalette.chargeColor, frac: nil)
            }
            LiquidFullWidthNavigationAction("Show all metrics")
        }
    }

    private func yourCards() -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("YOUR CARDS").font(StrandFont.overline).tracking(1.6).foregroundStyle(StrandPalette.textTertiary)
                Spacer()
                Text(String(localized: "Edit").uppercased()).font(StrandFont.overlineScaled(11)).tracking(1.0)
                    .foregroundStyle(StrandPalette.accent)
            }
            .padding(.horizontal, 2)
            LiquidCardRow(title: DashboardCard.stress.title, sub: DashboardCard.stress.subtitle,
                          value: String(localized: "Calibrating"), tint: StrandPalette.accent, frac: nil)
            LiquidCardRow(title: DashboardCard.fitnessAge.title, sub: DashboardCard.fitnessAge.subtitle,
                          value: LiquidTodayView.noValueDash, tint: StrandPalette.chargeColor, frac: 0.5)
            LiquidCardRow(title: DashboardCard.vitality.title, sub: DashboardCard.vitality.subtitle,
                          value: "44", tint: StrandPalette.metricPurple, frac: 0.44)
        }
    }

    private func calorieStates() -> some View {
        HStack(alignment: .top, spacing: NoopMetrics.space1) {
            TodayCaloriesTile(split: .init(restingKcal: 680, activityKcal: 45), goal: 480)
            TodayCaloriesTile(split: .init(restingKcal: 980, activityKcal: 310), goal: 480)
            TodayCaloriesTile(split: .init(restingKcal: 1440, activityKcal: 560), goal: 480)
        }
        .padding(.vertical, NoopMetrics.space4)
        .padding(.horizontal, NoopMetrics.space3)
        .background(NoopPanelSurface(cornerRadius: 26, elevated: true))
    }

    // MARK: Renders

    func testRendersTheTodayScreen() throws {
        // The first screen: header, rings and half-gauges, heart rate (live), the start of the synthesis.
        try render(VStack(alignment: .leading, spacing: 12) {
            header()
            hero()
            liveCard()
            synthesis()
        }
        .padding(.horizontal, NoopMetrics.screenHPadding)
        .padding(.top, 60), height: 844, clipped: true, name: "1-premier-ecran")

        // The rest of the scroll: synthesis, start session, key metrics, your cards.
        try render(VStack(alignment: .leading, spacing: 12) {
            synthesis()
            LiquidSessionStartRow()
            keyMetrics()
            yourCards()
        }
        .padding(.horizontal, NoopMetrics.screenHPadding)
        .padding(.vertical, 24), height: nil, clipped: false, name: "2-suite")

        // The heart-rate card on its Day tab, then past its threshold while still.
        try render(dayCard()
            .padding(.horizontal, NoopMetrics.screenHPadding)
            .padding(.vertical, 24), height: nil, clipped: false, name: "3-fc-journee")
        try render(alertCard()
            .padding(.horizontal, NoopMetrics.screenHPadding)
            .padding(.vertical, 24), height: nil, clipped: false, name: "4-fc-seuil")

        // The calories half-gauge in the morning, after a session and past its goal.
        try render(calorieStates()
            .padding(.horizontal, NoopMetrics.screenHPadding)
            .padding(.vertical, 24), height: nil, clipped: false, name: "5-calories")
    }

    private func render<V: View>(_ content: V, height: CGFloat?, clipped: Bool, name: String) throws {
        let screen = content
            .frame(width: width, height: height, alignment: .top)
            .fixedSize(horizontal: false, vertical: height == nil)
            .background(StrandPalette.surfaceBase)
            .clipped()
            .environment(\.colorScheme, .dark)
            .environment(\.locale, Locale(identifier: "fr_FR"))

        let renderer = ImageRenderer(content: screen)
        renderer.scale = 3
        var image: NSImage?
        // The palette's light/dark pairs resolve through the drawing appearance, not the SwiftUI scheme.
        (NSAppearance(named: .darkAqua) ?? NSAppearance.currentDrawing()).performAsCurrentDrawingAppearance {
            image = renderer.nsImage
        }
        let rendered = try XCTUnwrap(image, "\(name) did not render")
        let cg = try XCTUnwrap(rendered.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 10_000, "\(name) rendered next to nothing")

        if let dir = ProcessInfo.processInfo.environment["NOOP_RENDER_DIR"], !dir.isEmpty {
            let folder = URL(fileURLWithPath: dir, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: folder.appendingPathComponent("aujourdhui-\(name).png"))
        }
    }
}
