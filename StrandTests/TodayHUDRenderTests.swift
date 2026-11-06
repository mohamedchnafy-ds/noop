import XCTest
import SwiftUI
import AppKit
@testable import Strand
import StrandDesign
import WhoopStore
import StrandAnalytics

/// Renders the HUD drawing of Today (fork chantier 13, canvas « NOOP – Instrument (Aujourd'hui) », page
/// « HUD holographique ») to PNG, dark and light « plan », at 390 and 375 points, with data, while the Charge
/// calibrates and with nothing measured yet. The views, layout and tokens are the real ones; the values are
/// made up (a morning with Charge 72, Effort 4.6 against a 12–14 target, Rest 81 after 6 h 08).
///
/// Always rendered, so a panel that cannot be drawn fails here. The PNGs are written only when
/// `NOOP_RENDER_DIR` is set (the fork's render workflow).
@MainActor
final class TodayHUDRenderTests: XCTestCase {

    private var dayStart: Int {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 6)) ?? Date()
        return Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970)
    }

    // MARK: Models

    private enum State { case data, calibration, empty }

    private func heroModel(_ state: State) -> TodayHeroModel {
        let empty = state == .empty
        let calibrating = state == .calibration
        return TodayHeroModel(
            charge: .init(label: String(localized: "Charge"), score: empty || calibrating ? nil : 72,
                          tint: StrandPalette.chargeColor,
                          caption: calibrating ? String(localized: "calibration") : nil,
                          calibration: calibrating ? (done: 2, of: 4) : nil, route: nil, guide: .charge),
            effort: .init(label: String(localized: "Effort"), score: empty ? nil : 4.6,
                          tint: StrandPalette.effortColor, maxValue: 21, decimals: 1,
                          caption: empty || calibrating ? nil : String(localized: "target \(12)–\(14)"),
                          targetRange: empty || calibrating ? nil : 12...14, route: nil, guide: .effort),
            rest: .init(label: String(localized: "Rest"), score: empty ? nil : 81, tint: StrandPalette.restRing,
                        caption: empty ? nil : SleepDurationText.format(368), route: nil, guide: .rest),
            calories: (empty ? nil : TodayEnergy.Split(restingKcal: 760, activityKcal: 185), 480),
            restingHR: empty ? nil : .init(value: 58, low: 52, high: 66, normal: calibrating ? nil : 55...61),
            hrv: empty ? nil : .init(value: 64, low: 44, high: 80, normal: calibrating ? nil : 52...70),
            sourceLabel: nil,
            nutrition: empty ? nil : .init(eatenKcal: 1240, balanceKcal: -410, proteinG: 92, proteinGoalG: 190))
    }

    private func header(empty: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TodayHeaderLayout(date: "jeudi 6 novembre", title: String(localized: "Today"), onTitleTap: {}) {
                HStack(spacing: NoopMetrics.space1) {
                    ForEach(["battery.75percent", "plus", "person.crop.circle.fill"], id: \.self) { symbol in
                        Image(systemName: symbol)
                            .font(StrandFont.headline)
                            .foregroundStyle(NoopHUDStyle.chrome)
                            .frame(width: NoopMetrics.compactControlSize, height: NoopMetrics.compactControlSize)
                            .overlay(Circle().strokeBorder(NoopHUDStyle.frameSoft, lineWidth: 1))
                    }
                }
            }
            TodayHUDStatusText(syncing: false,
                               lastSyncedAt: empty ? nil : Date().timeIntervalSince1970 - 4 * 60)
        }
    }

    // MARK: Heart rate

    private func dayBpm(_ m: Double) -> Double {
        if m < 364 { return 57 - 4 * sin(.pi * m / 364) + 1.2 * sin(m / 7) }
        if m < 450 { return 58 + (m - 364) / 86 * 14 }
        if m < 500 { return 72 + 55 * sin(.pi * (m - 450) / 50) }
        return 74 + 8 * sin((m - 500) / 45)
    }

    /// Midnight → 14:35 in 5-minute buckets.
    private var dayInput: TodayHRDayInput {
        let start = dayStart
        var ts: [Int] = [], bpm: [Double] = []
        for i in 0..<176 {
            ts.append(start + i * 300)
            bpm.append(dayBpm(Double(i * 5)))
        }
        var habitual: [Int: Double] = [:]
        for slot in 0..<288 {
            let h = Double(slot) / 12
            habitual[slot] = h < 6 ? 57 : 64 + 10 * sin(.pi * (h - 6) / 13)
        }
        return TodayHRDayInput(bucketTs: ts, bucketBpm: bpm,
                               segments: hrGapSegments(bucketTs: ts, bucketSeconds: 300),
                               dayStart: start, domainEnd: start + 175 * 300, isToday: true,
                               habitual: habitual, restingHR: 58, awakeFloor: 50,
                               sleep: [start...(start + 364 * 60)])
    }

    private func heartCard() -> some View {
        let day = dayInput
        let chart = TodayHRCardLogic.dayChart(day, zone: .current)
        return VStack(alignment: .leading, spacing: 8) {
            TodayHRSectionHead(mode: .constant(.day), liveEnabled: true)
            TodayHRCardBody(
                tint: StrandPalette.liquidHeart, bpm: 72,
                subtitle: String(localized: "5-minute average · since midnight"),
                chart: chart, lineWidth: 2, emptyText: "",
                caption: [.init(text: String(localized: "your usual day"), swatch: .usualDay),
                          .init(text: String(localized: "sleep"), swatch: .sleep)]
                    + TodayHRCardLogic.dayZoneCaption(chart, habitual: true),
                stats: (day.bucketBpm.min(), day.bucketBpm.reduce(0, +) / Double(day.bucketBpm.count),
                        day.bucketBpm.max()))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .modifier(TodayHUDCardSurface(hud: true, accent: StrandPalette.liquidHeart))
        .environment(\.todayHUDStyle, true)
    }

    private func page(_ state: State) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(empty: state == .empty)
            TodayHUDHero(model: heroModel(state), animated: false, onGuide: { _ in })
            if state != .empty { heartCard() }
        }
        .padding(.horizontal, NoopMetrics.screenHPadding)
        .padding(.top, 60)
        .padding(.bottom, 24)
    }

    // MARK: Renders

    func testRendersTheHUD() throws {
        try render(page(.data), width: 390, dark: true, name: "1-sombre")
        try render(page(.data), width: 390, dark: false, name: "2-clair")
        try render(page(.data), width: 375, dark: true, name: "3-petit-375")
        try render(page(.calibration), width: 390, dark: true, name: "4-calibration")
        try render(page(.empty), width: 390, dark: false, name: "5-vide-clair")
        try render(page(.empty), width: 390, dark: true, name: "6-vide-sombre")
    }

    func testTheHUDOrderPutsTheSynthesisAboveTheHeartRateWithoutRewritingTheRest() {
        XCTAssertEqual(TodayHUDOrder.hudSectionOrder([.hero, .heartRate, .synthesis, .stress, .keyMetrics]),
                       [.hero, .synthesis, .heartRate, .stress, .keyMetrics])
        XCTAssertEqual(TodayHUDOrder.hudSectionOrder([.hero, .synthesis, .heartRate, .stress]),
                       [.hero, .synthesis, .heartRate, .stress])
        XCTAssertEqual(TodayHUDOrder.hudSectionOrder([.hero, .stress, .keyMetrics]), [.hero, .stress, .keyMetrics])
    }

    func testTheHUDCellsReadTheHeroResolvers() {
        let model = heroModel(.data)
        let dials = TodayHUDHero(model: model, animated: false, onGuide: { _ in }).dials
        XCTAssertEqual(dials.map(\.index), ["01", "02", "03", "04"])
        XCTAssertEqual(dials[0].fraction, model.activityFraction, accuracy: 1e-9)
        XCTAssertEqual(dials[1].value, TodayHeroModel.valueText(of: model.charge))
        XCTAssertEqual(dials[2].value, TodayHeroModel.valueText(of: model.effort))
        XCTAssertEqual(dials[2].unit, "/ 21")
        XCTAssertEqual(dials[3].fraction, TodayHeroModel.fraction(of: model.rest), accuracy: 1e-9)
        XCTAssertEqual(dials[2].band, model.effortBandFraction)
    }

    private func render<V: View>(_ content: V, width: CGFloat, dark: Bool, name: String) throws {
        let screen = content
            .frame(width: width, alignment: .top)
            .fixedSize(horizontal: false, vertical: true)
            .background(NoopHUDStyle.canvas)
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.locale, Locale(identifier: "fr_FR"))

        let renderer = ImageRenderer(content: screen)
        renderer.scale = 3
        var image: NSImage?
        // The palette's light/dark pairs resolve through the drawing appearance, not the SwiftUI scheme.
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) ?? NSAppearance.currentDrawing()
        appearance.performAsCurrentDrawingAppearance {
            image = renderer.nsImage
        }
        let rendered = try XCTUnwrap(image, "\(name) did not render")
        let cg = try XCTUnwrap(rendered.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 10_000, "\(name) rendered next to nothing")

        if let dir = ProcessInfo.processInfo.environment["NOOP_RENDER_DIR"], !dir.isEmpty {
            let folder = URL(fileURLWithPath: dir, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: folder.appendingPathComponent("aujourdhui-hud-\(name).png"))
        }
    }
}
