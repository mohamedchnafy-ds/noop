import XCTest
import SwiftUI
import AppKit
@testable import Strand
import StrandDesign
import WhoopStore

/// Renders the Training screen's parts to PNG at iPhone width, in dark mode — the visual check against
/// the « NOOP – Entraînement et Plus » mockup (artboards 2, 3 and 4) before an .ipa is built (personal
/// fork). Sample week: Full body A / B / C planned Monday, Wednesday and Friday; today is Monday 2
/// November 2026; on Sunday 1 November Full body B was done and a walk was detected. The screen's own
/// scroll view and navigation are not drawn; its parts are, in order. PNGs are written only when
/// `NOOP_RENDER_DIR` is set.
@MainActor
final class TrainingRenderTests: XCTestCase {

    private let width: CGFloat = 390
    private var calendar: Calendar { .current }

    private func date(_ day: Int, _ hour: Int = 0, month: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func ts(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 11) -> Int {
        Int(date(day, hour, month: month).timeIntervalSince1970) + minute * 60
    }

    private func line(_ program: String, _ ord: Int, _ name: String, _ sets: Int, _ group: String?) -> LiftProgramItemRow {
        LiftProgramItemRow(id: "\(program)\(ord)", deviceId: "d", programId: program, ord: ord, exercise: name,
                           targetSets: sets, targetRepsLow: 8, targetRepsHigh: 10, targetRpe: nil,
                           targetWeightKg: nil, restSec: 90, note: nil, supersetGroup: group)
    }

    private var summaries: [TrainingProgramSummary] {
        let a = [line("A", 0, "Squat barre", 4, "A"), line("A", 1, "Tirage horizontal", 4, "A"),
                 line("A", 2, "Développé couché", 3, "B"), line("A", 3, "Fentes", 3, "B"),
                 line("A", 4, "Développé militaire", 3, "C"), line("A", 5, "Rowing haltère", 3, "C"),
                 line("A", 6, "Curl incliné", 3, "D"), line("A", 7, "Extension triceps", 3, "D"),
                 line("A", 8, "Gainage", 2, "E"), line("A", 9, "Mollets", 2, "E")]
        let b = a.map { item -> LiftProgramItemRow in var copy = item; copy.programId = "B"; return copy }
        let c = a.map { item -> LiftProgramItemRow in var copy = item; copy.programId = "C"; return copy }
        let done = (startTs: ts(26, 18, month: 10), endTs: ts(26, 18, 55, month: 10))
        return [
            TrainingDays.programSummary(id: "A", name: "Full body A", items: a, finished: [done]),
            TrainingDays.programSummary(id: "B", name: "Full body B", items: Array(b.prefix(9)),
                                        finished: [(startTs: ts(1, 14, 5), endTs: ts(1, 14, 57))]),
            TrainingDays.programSummary(id: "C", name: "Full body C", items: c, finished: []),
        ]
    }

    private var plan: TrainingWeekPlan {
        TrainingWeekPlan(programs: ["1": "A", "3": "B", "5": "C"], since: "2026-11-02")
    }

    private var lifts: [TrainingLiftDone] {
        [TrainingLiftDone(sessionId: "s1", programId: "B", name: "Full body B", startTs: ts(1, 14, 5),
                          endTs: ts(1, 14, 57), workingSets: 18, effort: "58")]
    }

    private var activities: [TrainingActivityDone] {
        [TrainingActivityDone(sport: "Marche rapide", source: "détectée", startTs: ts(1, 18, 30),
                              endTs: ts(1, 18, 55), kcal: 140)]
    }

    private func days(_ dates: [Date]) -> [TrainingDay] {
        TrainingDays.buildTrainingDays(dates, plan: plan, lifts: lifts, activities: activities,
                                       now: date(2, 9), calendar: calendar)
    }

    private func header(_ subtitle: String, mode: TrainingViewMode) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Training")
                    .font(StrandFont.rounded(28))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: subtitle)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            Spacer(minLength: 0)
            TrainingModeSwitch(mode: .constant(mode))
        }
    }

    func testRenderWeek() throws {
        let week = days(TrainingCalendar.weekDates(from: date(2), calendar: calendar))
        let tally = TrainingDays.sessionTally(week)
        let all = summaries
        let screen = VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            header(TrainingText.weekTitle(monday: date(2), calendar: calendar), mode: .week)
            VStack(alignment: .leading, spacing: 10) {
                TrainingPeriodBar(label: TrainingText.tallyLine(done: tally.done, planned: tally.planned,
                                                                current: String(localized: "This week")),
                                  onPrevious: {}, onNext: {})
                TrainingWeekStrip(days: week, selectedKey: "2026-11-02",
                                  weekdays: TrainingText.shortWeekdays(calendar)) { _ in }
                TrainingLegend()
            }
            TrainingDaySection(day: week[0], planned: all[0], others: Array(all.dropFirst()), isRunning: false)
            TrainingProgramsCard(programs: all, plan: plan, weekdays: TrainingText.shortWeekdays(calendar),
                                 loaded: true)
            TrainingProgressSummaryCard(data: LiftProgressData()) { EmptyView() }
            VStack(alignment: .leading, spacing: 10) {
                Text("Other activities").strandOverline()
                NoopCard(padding: 0) {
                    VStack(spacing: 0) {
                        TrainingActivityRowLabel(title: "Start an activity",
                                                 detail: "Run, ride, walk… with the strap's heart rate",
                                                 symbol: "figure.run", tint: StrandPalette.metricRose)
                        TrainingActivityRowLabel(title: "Intervals", detail: "Work / recovery timer",
                                                 symbol: "timer", tint: StrandPalette.metricRose)
                        TrainingActivityRowLabel(title: "Live HR", detail: "Zones, curve and banner",
                                                 symbol: "waveform.path.ecg", tint: StrandPalette.liquidHeart,
                                                 showsDivider: false)
                    }
                }
            }
        }
        try render(AnyView(screen), name: "2-semaine")
    }

    func testRenderMonth() throws {
        let cells = TrainingCalendar.monthCells(containing: date(1), calendar: calendar)
        let monthDays = days(cells.compactMap { $0 })
        let byKey = Dictionary(uniqueKeysWithValues: monthDays.map { ($0.key, $0) })
        let tally = TrainingDays.sessionTally(monthDays)
        let totals = TrainingDays.periodTotals(monthDays)
        let sunday = monthDays[0]
        let screen = VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            header(TrainingText.monthTitle(date(1)), mode: .month)
            VStack(alignment: .leading, spacing: 10) {
                TrainingPeriodBar(label: TrainingText.tallyLine(done: tally.done, planned: tally.planned,
                                                                current: String(localized: "This month")),
                                  onPrevious: {}, onNext: {})
                NoopCard(padding: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        TrainingMonthGrid(cells: cells.map { cell in
                                              cell.flatMap { byKey[TrainingCalendar.trainingDayKey($0, calendar: calendar)] }
                                          },
                                          selectedKey: "2026-11-01",
                                          weekdays: TrainingText.narrowWeekdays(calendar)) { _ in }
                        TrainingLegend().padding(.horizontal, 6)
                    }
                }
                TrainingMonthTotals(done: tally.done, planned: tally.planned,
                                    activities: totals.activities, minutes: totals.minutes)
            }
            TrainingDaySection(day: sunday, planned: nil, others: [], isRunning: false)
        }
        try render(AnyView(screen), name: "3-mois")
    }

    func testRenderPlanForm() throws {
        let form = VStack(alignment: .leading, spacing: 16) {
            Text("Plan the week")
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(maxWidth: .infinity)
            TrainingPlanForm(programs: summaries, draft: .constant(plan))
        }
        try render(AnyView(form), name: "4-planifier")
    }

    private func render(_ content: AnyView, name: String) throws {
        let screen = content
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.vertical, 24)
            .frame(width: width, alignment: .top)
            .fixedSize(horizontal: false, vertical: true)
            .background(StrandPalette.surfaceBase)
            .environment(\.colorScheme, .dark)
            .environment(\.locale, Locale(identifier: "fr_FR"))

        let renderer = ImageRenderer(content: screen)
        renderer.scale = 3
        var image: NSImage?
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
            try png.write(to: folder.appendingPathComponent("entrainement-\(name).png"))
        }
    }
}
