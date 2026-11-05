import XCTest
import SwiftUI
import AppKit
@testable import Strand
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Renders the three day widgets — today's session, nutrition and sleep, small and medium — to PNG in dark mode,
/// the visual check against the mockup ("NOOP – Bannières et widgets", artboards 7 and 8) before an .ipa is built
/// (personal fork, chantier 6). The faces are the extension's own (`StrandiOSShared/DayWidgetViews.swift`), the
/// sections are worded by `DayWidgetsContent` from the mockup's values, so the words are the app's, in French.
///
/// Always rendered, so a face that cannot be drawn fails here. The PNGs are written only when `NOOP_RENDER_DIR`
/// is set — by the fork's render workflow, which publishes them.
@MainActor
final class DayWidgetsRenderTests: XCTestCase {

    private let small = CGSize(width: 162, height: 162)
    private let medium = CGSize(width: 346, height: 162)

    private var calendar: Calendar { .current }

    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)) ?? Date()
    }

    private func ts(_ date: Date) -> Int { Int(date.timeIntervalSince1970) }

    // MARK: Inputs (the mockup's values)

    private func item(_ ord: Int, _ exercise: String, group: String) -> LiftProgramItemRow {
        LiftProgramItemRow(id: "\(ord)", deviceId: "d", programId: "a", ord: ord, exercise: exercise,
                           targetSets: 3, targetRepsLow: 8, targetRepsHigh: 10, targetRpe: nil,
                           targetWeightKg: 60, restSec: 120, note: nil, supersetGroup: group)
    }

    private var programItems: [LiftProgramItemRow] {
        [item(0, "Squat barre", group: "A"), item(1, "Tirage", group: "A"),
         item(2, "Développé couché", group: "B"), item(3, "Fentes", group: "B"),
         item(4, "Soulevé de terre roumain", group: "C"), item(5, "Pompes", group: "C"),
         item(6, "Développé militaire", group: "D"), item(7, "Curl incliné", group: "D"),
         item(8, "Extension triceps", group: "E"), item(9, "Gainage", group: "E")]
    }

    private func liftRow(_ id: String, _ start: Date, minutes: Int) -> LiftSessionRow {
        LiftSessionRow(id: id, deviceId: "d", startTs: ts(start), endTs: ts(start) + minutes * 60, sport: "lift",
                       programId: "a", programName: "Full body A", sessionRpe: nil, note: nil)
    }

    /// Wednesday 4 November: Monday's session done, a run on Tuesday, today and Friday still to do.
    private func resolution(_ session: TodaySynthesisLogic.Session, doneToday: Bool) -> TodaySessionResolution {
        var performed = [(row: liftRow("mon", date(2, 18), minutes: 55), workingSets: 15)]
        if doneToday { performed.append((row: liftRow("wed", date(4, 7), minutes: 52), workingSets: 15)) }
        let run = WorkoutRow(startTs: ts(date(3, 7)), endTs: ts(date(3, 7, 40)), sport: "Running", source: "manual",
                             durationS: 2_400, energyKcal: 380, avgHr: 145, maxHr: 172, strain: 45, distanceM: nil,
                             zonesJSON: nil, notes: nil, steps: nil)
        return TodaySessionResolution(
            session: session, programId: "a", programItems: programItems, hasPrograms: true, performed: performed,
            liftWorkouts: [:], otherWorkouts: [run],
            plan: TrainingWeekPlan(programs: ["1": "a", "3": "a", "5": "a"], since: "2026-10-26"))
    }

    private var nextSession: DayWidgetsSnapshot.Session {
        DayWidgetsContent.sessionSection(
            resolution(TodaySynthesisLogic.Session(name: "Full body A", state: .next, supersets: 5, singles: 0,
                                                   typicalMinutes: 55), doneToday: false),
            today: date(4), calendar: calendar)
    }

    private var doneSession: DayWidgetsSnapshot.Session {
        DayWidgetsContent.sessionSection(
            resolution(TodaySynthesisLogic.Session(name: "Full body B", state: .done(minutes: 52), supersets: 5,
                                                   singles: 0, typicalMinutes: nil), doneToday: true),
            today: date(4), calendar: calendar)
    }

    private var restSession: DayWidgetsSnapshot.Session {
        var rest = resolution(TodaySynthesisLogic.Session(name: String(localized: "Rest"), state: .rest, supersets: 0,
                                                          singles: 0, typicalMinutes: nil), doneToday: false)
        rest.programId = nil
        rest.programItems = []
        return DayWidgetsContent.sessionSection(rest, today: date(5), calendar: calendar)
    }

    private var nutrition: DayWidgetsSnapshot.Nutrition {
        func meal(_ id: String, _ hour: Int, _ n: MealNutrients) -> MealEntry {
            let at = ts(date(4, hour))
            return MealEntry(meal: MealRow(id: id, day: "2026-11-04", eatenAt: at, name: id, origin: .manual,
                                           createdAt: at, updatedAt: at),
                             items: [MealItemRow(id: id, mealId: id, ord: 0, name: id, grams: nil, nutrients: n)])
        }
        let meals = [meal("1", 8, MealNutrients(kcal: 420, proteinG: 28, carbsG: 52, fatG: 12)),
                     meal("2", 13, MealNutrients(kcal: 650, proteinG: 40, carbsG: 80, fatG: 18)),
                     meal("3", 17, MealNutrients(kcal: 425, proteinG: 30, carbsG: 30, fatG: 22))]
        let plan = NutritionGoals.intakePlan(body: NutritionGoals.Body(sex: "male", weightKg: 80, heightCm: 178, age: 30),
                                             settings: NutritionGoals.Settings(mode: .kcal, manualKcal: 2_560))
        return DayWidgetsContent.nutritionSection(
            NutritionDaySummary(dayKey: "2026-11-04", meals: meals,
                                spent: TodayEnergy.Split(restingKcal: 1_580, activityKcal: 520)),
            plan: plan)
    }

    private var sleep: DayWidgetsSnapshot.Sleep {
        let start = ts(date(3, 23, 52))
        var segments: [StageSegment] = []
        var at = start
        for (stage, minutes) in [("light", 54), ("deep", 27), ("light", 42), ("rem", 21), ("wake", 6),
                                 ("light", 48), ("deep", 18), ("rem", 30), ("wake", 9), ("light", 153)] {
            segments.append(StageSegment(start: at, end: at + minutes * 60, stage: stage))
            at += minutes * 60
        }
        let night = CachedSleepSession(startTs: start, endTs: ts(date(4, 6, 40)), efficiency: 0.92, restingHr: 52,
                                       avgHrv: 46, stagesJSON: AnalyticsEngine.encodeStages(segments))
        let figures = SleepSynthesisFigures(needMin: 480, debtMin: 72, isDebt: true, lastShortfallMin: 32,
                                            usualWakeMin: 6 * 60 + 50)
        return DayWidgetsContent.sleepSection(nightMinutes: 408, figures: figures, night: night)
    }

    // MARK: Renders

    func testRendersTheDayWidgets() throws {
        let labels = DayWidgetsContent.widgetLabels()

        let smalls = VStack(spacing: 22) {
            HStack(spacing: 22) {
                widget(DaySessionWidgetFace(session: nextSession, labels: labels, size: .small), size: small)
                widget(DayNutritionWidgetFace(nutrition: nutrition, labels: labels, size: .small), size: small)
            }
            HStack(spacing: 22) {
                widget(DaySleepWidgetFace(sleep: sleep, labels: labels, size: .small), size: small)
                widget(DaySessionWidgetFace(session: doneSession, labels: labels, size: .small), size: small)
            }
        }
        .padding(22)
        try render(smalls, width: 390, name: "widgets-1-petits")

        let mediums = VStack(spacing: 22) {
            widget(DaySessionWidgetFace(session: nextSession, labels: labels, size: .medium), size: medium)
            widget(DayNutritionWidgetFace(nutrition: nutrition, labels: labels, size: .medium), size: medium)
            widget(DaySleepWidgetFace(sleep: sleep, labels: labels, size: .medium), size: medium)
        }
        .padding(22)
        try render(mediums, width: 390, name: "widgets-2-moyens")

        // A rest day of the plan, and a day the app has not published yet (or that is over): "no data".
        let empty = VStack(spacing: 22) {
            HStack(spacing: 22) {
                widget(DaySessionWidgetFace(session: restSession, labels: labels, size: .small), size: small)
                widget(DaySessionWidgetFace(session: nil, labels: labels, size: .small), size: small)
            }
            HStack(spacing: 22) {
                widget(DayNutritionWidgetFace(nutrition: nil, labels: labels, size: .small), size: small)
                widget(DaySleepWidgetFace(sleep: nil, labels: labels, size: .small), size: small)
            }
            widget(DaySessionWidgetFace(session: restSession, labels: labels, size: .medium), size: medium)
        }
        .padding(22)
        try render(empty, width: 390, name: "widgets-3-repos-sans-donnee")
    }

    // MARK: Widgets v2 (mockup « NOOP – Widgets v2 », 5 Nov.)

    /// Wednesday 4 November with Full body A and 30 minutes of walking planned; `liftDone` once the session is
    /// over (then the walk is the resolver's session).
    private func plannedResolution(liftDone: Bool) -> TodaySessionResolution {
        let session = liftDone
            ? TodaySynthesisLogic.Session(name: "Walking", state: .next, supersets: 0, singles: 0,
                                          typicalMinutes: nil, cardioMinutes: 30)
            : TodaySynthesisLogic.Session(name: "Full body A", state: .next, supersets: 5, singles: 0,
                                          typicalMinutes: 55, alsoPlanned: ["Walking · 30 min"])
        var r = resolution(session, doneToday: liftDone)
        if liftDone {
            r.programId = nil
            r.programItems = []
        }
        r.plan = TrainingWeekPlan(days: ["1": [.program("a")], "3": [.program("a"), .cardio(sport: "Walking", minutes: 30)],
                                         "5": [.program("a")]], since: "2026-10-26")
        r.programNames = ["a": "Full body A"]
        return r
    }

    private var heartPoints: [DayHeartPoint] {
        let values = [82, 84, 83, 88, 92, 79, 81, 84, 88, 93, 91, 87, 85, 85, 86, 87, 86, 85, 84, 66, 64, 72, 95, 100,
                      97, 104, 119, 127, 121, 114, 110]
        let end = ts(date(4, 16))
        return values.enumerated().map { DayHeartPoint(ts: end - (values.count - 1 - $0.offset) * 360, bpm: $0.element) }
    }

    private var heart: DayWidgetsSnapshot.Heart? {
        var habitual: [Int: Double] = [:]
        for slot in 0..<288 { habitual[slot] = 82 + 12 * sin(Double(slot) / 288 * .pi) }
        return DayWidgetsContent.heartSection(habitual: habitual, awakeFloor: 68, restingHR: 52, sleep: [])
    }

    private var stressModel: TodayStressModel {
        let dayStart = ts(date(4))
        let levels: [Double?] = [2.9, 2.6, 1.9, nil, nil, 2.0, 2.2, 2.4, 2.5, 2.4, 2.6, 2.7, nil, 2.8, 2.8, 2.2, 2.4,
                                 2.6, 3.0, 2.9]
        var points: [TodayStressModel.Point] = []
        var run = 0
        for (i, level) in levels.enumerated() {
            guard let level else {
                if points.last?.run == run { run += 1 }
                continue
            }
            points.append(.init(x: Double(i) * 0.5 / 16, level: level, run: run))
        }
        let latest = dayStart + 15 * 3_600 + 1_800
        return TodayStressModel(points: points, moving: [(1.25 / 16)...(2.25 / 16), (5.75 / 16)...(6.25 / 16)],
                                latestLevel: 2.9, latestStartTs: latest, latestIsNow: true, highMinutes: 330,
                                mean: 2.4, peakStartTs: dayStart + 15 * 3_600, dayStart: dayStart)
    }

    private var dayV2: DayWidgetsSnapshot {
        DayWidgetsContent.daySnapshot(
            dayStart: date(4), calendar: calendar,
            session: DayWidgetsContent.sessionSection(plannedResolution(liftDone: false), today: date(4),
                                                      calendar: calendar),
            nutrition: nutrition, sleep: sleep,
            rings: DayWidgetsContent.ringsSection(activity: TodayEnergy.Split(restingKcal: 1_580, activityKcal: 420),
                                                  activityGoal: 600, charge: 19, effortStored: 18.6,
                                                  effortScale: .whoop, rest: 76, nightMinutes: 311),
            heart: heart,
            stress: DayWidgetsContent.stressSection(stressModel, dayStart: ts(date(4))))
    }

    func testRendersTheWidgetsV2() throws {
        let day = dayV2
        let labels = DayWidgetsContent.widgetLabels()
        let end = ts(date(4, 16))
        let axis = [end - 10_800, end - 5_400, end].map {
            AppClock.hourMinuteFormatter().string(from: Date(timeIntervalSince1970: TimeInterval($0)))
        }
        let mediums = VStack(spacing: 22) {
            widget(DayRingsWidgetFace(rings: day.rings, noData: labels.noData), size: medium)
            widget(DayHeartWidgetFace(points: heartPoints, bpm: 110, stale: false, windowEnd: end, windowSec: 10_800,
                                      day: day, axis: axis), size: medium)
            widget(DayStressWidgetFace(day: day, now: end), size: medium)
            widget(DaySleepWidgetFaceV2(sleep: day.sleep, labels: labels), size: medium)
            widget(DaySessionWidgetFaceV2(session: day.session, day: day, labels: labels), size: medium)
            widget(DayNutritionWidgetFaceV2(nutrition: day.nutrition, day: day, labels: labels), size: medium)
        }
        .padding(22)
        try render(mediums, width: 390, name: "widgets-4-v2")

        // The session widget once the lift is done, on a rest day, and before the app has published.
        let done = DayWidgetsContent.sessionSection(plannedResolution(liftDone: true), today: date(4), calendar: calendar)
        let sessions = VStack(spacing: 22) {
            widget(DaySessionWidgetFaceV2(session: done, day: day, labels: labels), size: medium)
            widget(DaySessionWidgetFaceV2(session: restSession, day: day, labels: labels), size: medium)
            widget(DaySessionWidgetFaceV2(session: nil, day: nil, labels: labels), size: medium)
            widget(DayStressWidgetFace(day: nil, now: end), size: medium)
        }
        .padding(22)
        try render(sessions, width: 390, name: "widgets-5-v2-seance")
    }

    /// A widget as the Home Screen draws it: the raised surface, its corner, and the system's content margin.
    private func widget<Face: View>(_ face: Face, size: CGSize) -> some View {
        face
            .padding(.horizontal, size.width > 200 ? 16 : 14)
            .padding(.vertical, 14)
            .frame(width: size.width, height: size.height)
            .background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func render<Content: View>(_ content: Content, width: CGFloat, name: String) throws {
        let view = content
            .frame(width: width)
            .background(StrandPalette.surfaceBase)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        var image: NSImage?
        // The palette's light/dark pairs resolve through the drawing appearance, not the SwiftUI scheme.
        (NSAppearance(named: .darkAqua) ?? NSAppearance.currentDrawing()).performAsCurrentDrawingAppearance {
            image = renderer.nsImage
        }
        let rendered = try XCTUnwrap(image, "\(name) did not render")
        let cg = try XCTUnwrap(rendered.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 5_000, "\(name) rendered next to nothing")

        if let dir = ProcessInfo.processInfo.environment["NOOP_RENDER_DIR"], !dir.isEmpty {
            let folder = URL(fileURLWithPath: dir, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: folder.appendingPathComponent("\(name).png"))
        }
    }
}
