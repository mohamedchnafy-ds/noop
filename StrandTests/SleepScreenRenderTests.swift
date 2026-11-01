import XCTest
import SwiftUI
import AppKit
@testable import Strand
import StrandDesign
import WhoopStore

/// Renders the redesigned Sleep tab to PNG at iPhone width, in dark mode — the visual check against the
/// mockups (canvas "NOOP – Écran Sommeil", direction A) before an .ipa is built (personal fork).
///
/// The values are the night of Sat 31 Oct → Sun 1 Nov 2026 as the app showed it: asleep 01:51 → 06:04,
/// 3h 41m asleep in 4h 12m in bed, score 66, deep 47m / REM 1h 07m / light 1h 48m / awake 31m, lowest
/// heart rate 57 bpm, 17.8 breaths a minute, a 2h 23m debt against an 8 h need, one night recorded. The
/// stage timeline and the curves are shaped after that night; the views, their layout and their tokens
/// are the real ones.
///
/// Always rendered, so a screen that cannot be drawn fails here. The PNGs are written only when
/// `NOOP_RENDER_DIR` is set — by the fork's render workflow, which publishes them.
@MainActor
final class SleepScreenRenderTests: XCTestCase {

    private let width: CGFloat = 390

    // MARK: The night

    private var onset: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 1, minute: 51)) ?? Date()
    }
    private var wake: Date { onset.addingTimeInterval(253 * 60) }

    /// Minutes from onset, shaped after the night's ribbon chart.
    private let segments: [(SleepStage, Double, Double)] = [
        (.awake, 0, 6), (.deep, 6, 40), (.light, 40, 62), (.deep, 62, 69), (.light, 69, 85),
        (.rem, 85, 90), (.light, 90, 104), (.deep, 104, 110), (.rem, 110, 128), (.awake, 128, 138),
        (.rem, 138, 160), (.light, 160, 170), (.rem, 170, 192), (.awake, 192, 197),
        (.light, 197, 243), (.awake, 243, 253),
    ]

    private var intervals: [SleepInterval] {
        segments.map { SleepInterval(stage: $0.0, start: $0.1 * 60, end: $0.2 * 60) }
    }

    private var heartRate: [HRBucket] {
        let shape: [(Double, Double)] = [
            (0, 100), (1, 104), (3, 98), (6, 90), (10, 94), (15, 92), (20, 93), (25, 91), (30, 92), (35, 90),
            (40, 95), (42, 85), (45, 78), (50, 80), (55, 76), (60, 79), (65, 74), (70, 77), (75, 72), (80, 76),
            (85, 70), (88, 78), (92, 74), (96, 76), (100, 73), (105, 75), (110, 74), (115, 76), (118, 70),
            (121, 62), (123, 57), (125, 63), (128, 80), (131, 90), (134, 84), (137, 78), (140, 76), (145, 79),
            (150, 74), (155, 77), (160, 68), (163, 72), (166, 64), (170, 70), (173, 63), (176, 66), (180, 60),
            (183, 64), (186, 61), (190, 66), (195, 68), (200, 72), (205, 70), (210, 74), (215, 73), (220, 77),
            (225, 75), (230, 78), (235, 76), (240, 80), (245, 77), (250, 79), (253, 76),
        ]
        let start = Int(onset.timeIntervalSince1970)
        return shape.map { HRBucket(ts: start + Int($0.0 * 60), bpm: $0.1, minBpm: $0.1, maxBpm: $0.1) }
    }

    private func stage(at minute: Double) -> SleepStage {
        segments.first { minute >= $0.1 && minute < $0.2 }?.0 ?? .light
    }

    /// Illustrative curves (the night's own were not captured): rMSSD follows the stages, the skin
    /// temperature rises after sleep onset and settles.
    private var hrv: [TrendPoint] {
        stride(from: 0.0, through: 253, by: 4).map { m in
            let table: [SleepStage: Double] = [.deep: 70, .light: 50, .rem: 38, .awake: 30]
            let base = table[stage(at: m)] ?? 50
            return TrendPoint(date: onset.addingTimeInterval(m * 60), value: base + 6 * sin(m / 5))
        }
    }

    private var skinTemp: [TrendPoint] {
        stride(from: 0.0, through: 253, by: 4).map { m in
            let dip = stage(at: m) == .awake ? -0.35 : 0
            return TrendPoint(date: onset.addingTimeInterval(m * 60),
                              value: 33.0 + 1.5 * (1 - exp(-m / 55)) + dip + 0.08 * sin(m / 9))
        }
    }

    private var motion: [Double] {
        (0..<507).map { i in
            let m = Double(i) / 2
            let spikes: [Double: Double] = [0: 0.9, 3: 1, 7: 0.95, 92: 0.8, 99: 0.7, 113: 0.45, 175: 0.95, 218: 0.3]
            return spikes[m.rounded()] ?? 0.04
        }
    }

    // MARK: Pieces

    private func top() -> SleepTopSection {
        SleepTopSection(
            data: SleepTopSection.Model(
                nightLabel: String(localized: "Last night"), dateLabel: "sam. 31 oct.",
                canGoBack: false, canGoForward: false, onset: onset, wake: wake, intervals: intervals,
                palette: .oura, score: 66, scoreWord: String(localized: "Fair"), asleepMinutes: 221,
                deepMinutes: 47, remMinutes: 67, lightMinutes: 108, needMinutes: 480,
                timesEdited: false, canEditTimes: true, tonight: (needMinutes: 480, debtMinutes: 143)),
            actions: SleepTopSection.Actions(alarms: {}, customize: {}, previous: {}, next: {}, editTimes: {}))
    }

    private func phases(hr: Bool = true, hrvOn: Bool = false, temp: Bool = false, motionOn: Bool = false) -> SleepPhasesCard {
        SleepPhasesCard(
            subtitle: "\(String(localized: "\(SleepDurationText.format(252)) in bed · \(SleepDurationText.format(221)) asleep"))\n\(String(localized: "Stages estimated on the device"))",
            source: String(localized: "On-device"),
            intervals: intervals, nightStart: onset, palette: .oura,
            stages: [
                .init(stage: .awake, minutes: 31, percent: 12, typicalMinutes: nil),
                .init(stage: .rem, minutes: 67, percent: 27, typicalMinutes: nil),
                .init(stage: .light, minutes: 108, percent: 43, typicalMinutes: nil),
                .init(stage: .deep, minutes: 47, percent: 18, typicalMinutes: nil),
            ],
            typicalProgress: (count: 1, needed: 5),
            curves: SleepPhasesCard.Curves(heartRate: heartRate, hrv: hrv, skinTemp: skinTemp, motion: motion),
            selectedStage: .constant(nil),
            showHeartRate: .constant(hr), showHRV: .constant(hrvOn),
            showSkinTemp: .constant(temp), showMotion: .constant(motionOn),
            whyButton: AnyView(Label("Why this sleep?", systemImage: "info.circle")
                .font(StrandFont.footnote).foregroundStyle(StrandPalette.restBright).frame(minHeight: 44)),
            addNap: {})
    }

    private func indicators() -> SleepIndicatorsCard {
        SleepIndicatorsCard(tiles: [
            SleepIndicatorTile(id: "efficiency", symbol: "bed.double.fill", tint: StrandPalette.restBright,
                               label: String(localized: "Efficiency"), value: "88", unit: "%",
                               caption: String(localized: "\(SleepDurationText.format(252)) in bed"), usual: nil),
            SleepIndicatorTile(id: "restorative", symbol: "sparkles", tint: StrandPalette.sleepREM,
                               label: String(localized: "Restorative"), value: "51", unit: "%",
                               caption: String(localized: "\(SleepDurationText.format(114)) deep + REM"), usual: nil),
            SleepIndicatorTile(id: "respiratory", symbol: "lungs.fill", tint: StrandPalette.metricCyan,
                               label: String(localized: "Respiratory"), value: NightDetailCard.oneDecimal(17.8),
                               unit: String(localized: "/min"), caption: String(localized: "breaths while asleep"),
                               usual: nil),
            SleepIndicatorTile(id: "lowestHR", symbol: "heart.fill", tint: StrandPalette.liquidHeart,
                               label: String(localized: "Lowest HR"), value: "57", unit: String(localized: "bpm"),
                               caption: String(localized: "at \(AppClock.hourMinuteFormatter().string(from: onset.addingTimeInterval(123 * 60)))"),
                               usual: nil),
        ], regularity: .progress(done: 1, needed: 3))
    }

    private func nights() -> SleepNightsCard {
        let day = SleepNightsData.dayKey(Calendar.current.startOfDay(for: wake).addingTimeInterval(12 * 3600))
        return SleepNightsCard(data: SleepNightsData(
            debtMinutes: 143, isDebt: true, needMinutes: 480, lastShortfallMinutes: 259,
            recent: [.init(day: day, minutes: 221)], month: [.init(day: day, minutes: 221)]))
    }

    // MARK: Renders

    func testRendersTheSleepTab() throws {
        // The first screen: the top section and the start of the stages card, cut at the iPhone height.
        try render(VStack(spacing: NoopMetrics.sectionSpacing) {
            top()
            phases()
        }
        .padding(.horizontal, NoopMetrics.screenHPadding)
        .padding(.top, 62), height: 844, clipped: true, name: "1-premier-ecran")

        // The rest of the scroll.
        try render(VStack(spacing: NoopMetrics.sectionSpacing) {
            phases()
            indicators()
            nights()
        }
        .padding(.horizontal, NoopMetrics.screenHPadding)
        .padding(.vertical, 24), height: nil, clipped: false, name: "2-suite")

        // The curves: heart rate + rMSSD, then skin temperature with movement.
        try render(VStack(spacing: NoopMetrics.sectionSpacing) {
            phases(hr: true, hrvOn: true)
            phases(hr: false, temp: true, motionOn: true)
        }
        .padding(.horizontal, NoopMetrics.screenHPadding)
        .padding(.vertical, 24), height: nil, clipped: false, name: "3-courbes")
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
            try png.write(to: folder.appendingPathComponent("sommeil-\(name).png"))
        }
    }
}
