import XCTest
import SwiftUI
import AppKit
@testable import Strand
import StrandDesign
import WhoopStore

/// Renders the Nutrition screens to PNG at iPhone width, in dark mode — the visual check against the
/// « NOOP – Nutrition » mockups before an .ipa is built (personal fork). The day of the mockups (homme,
/// 30 ans, 178 cm, 80 kg; four meals; 2 330 kcal spent on average, +10 %) drawn by the real parts with
/// the real tokens. PNGs are written only when `NOOP_RENDER_DIR` is set.
@MainActor
final class NutritionRenderTests: XCTestCase {

    private let width: CGFloat = 390

    private func at(_ hour: Int, _ minute: Int) -> Int {
        let cal = Calendar.current
        let day = cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: hour, minute: minute))!
        return Int(day.timeIntervalSince1970)
    }

    private func meal(_ id: String, _ name: String, _ origin: MealOrigin, at time: Int,
                      lines: [(String, Double?, Bool, MealNutrients)]) -> MealEntry {
        MealEntry(meal: MealRow(id: id, day: "2026-11-01", eatenAt: time, name: name, origin: origin,
                                favorite: false, createdAt: time, updatedAt: time),
                  items: lines.enumerated().map { index, line in
                      MealItemRow(id: "\(id)-\(index)", mealId: id, ord: index, name: line.0, grams: line.1,
                                  gramsEstimated: line.2, nutrients: line.3)
                  })
    }

    private var meals: [MealEntry] {
        [
            meal("1", "Flocons d'avoine, lait, banane", .manual, at: at(7, 40),
                 lines: [("Flocons d'avoine, lait, banane", nil, false, MealNutrients(kcal: 520, proteinG: 22, carbsG: 82, fatG: 11))]),
            meal("2", "Skyr nature", .barcode, at: at(10, 30),
                 lines: [("Skyr nature", 150, false, MealNutrients(kcal: 95, proteinG: 17, carbsG: 6, fatG: 0.3))]),
            meal("3", "Poulet, riz, légumes", .photo, at: at(13, 5),
                 lines: [("Poulet rôti", 180, true, MealNutrients(kcal: 300, proteinG: 33, carbsG: 0, fatG: 12)),
                         ("Riz blanc cuit", 200, true, MealNutrients(kcal: 260, proteinG: 5, carbsG: 57, fatG: 0.6)),
                         ("Légumes", 150, true, MealNutrients(kcal: 90, proteinG: 2, carbsG: 23, fatG: 5.4))]),
            meal("4", "Shaker whey + lait", .voice, at: at(18, 15),
                 lines: [("Shaker whey + lait", nil, false, MealNutrients(kcal: 230, proteinG: 32, carbsG: 14, fatG: 5))]),
        ]
    }

    private var plan: NutritionGoals.Plan {
        NutritionGoals.intakePlan(weightKg: 80, proteinTenths: 20, fatTenths: 10, goalPercent: 10,
                                  reference: NutritionGoals.Reference(kcal: 2_330, days: 14))
    }

    private var summary: NutritionDaySummary {
        NutritionDaySummary(dayKey: "2026-11-01", meals: meals,
                            spent: TodayEnergy.Split(restingKcal: 1_580, activityKcal: 520))
    }

    func testRendersTheNutritionScreens() throws {
        let day = summary
        let journal = VStack(alignment: .leading, spacing: 12) {
            NutritionBalanceCard(model: NutritionBalanceModel(summary: day, plan: plan))
            Text("Meals").strandOverline().padding(.top, 14).padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(day.meals.enumerated()), id: \.element.meal.id) { index, entry in
                    NutritionMealRow(entry: entry, isFirst: index == 0, isLast: index == day.meals.count - 1)
                }
            }
        }
        try render(AnyView(journal), name: "1-journal")

        let empty = NutritionDaySummary(dayKey: "2026-11-01", meals: [], spent: TodayEnergy.Split(restingKcal: 900, activityKcal: 120))
        let emptyJournal = VStack(alignment: .leading, spacing: 12) {
            NutritionBalanceCard(model: NutritionBalanceModel(summary: empty, plan: plan))
            NutritionEmptyMeals()
        }
        try render(AnyView(emptyJournal), name: "2-journal-vide")

        let goals = NutritionGoalsContent(
            wearer: NutritionGoals.Body(sex: "male", weightKg: 80, heightCm: 178, age: 30), age: 30, weightKg: 80,
            reference: NutritionGoals.Reference(kcal: 2_330, days: 14),
            proteinTenthsRaw: .constant(20), fatTenthsRaw: .constant(10), goalPercentRaw: .constant(10))
        try render(AnyView(goals), name: "3-objectifs")

        let noReference = NutritionGoalsContent(
            wearer: NutritionGoals.Body(sex: "male", weightKg: 80, heightCm: 178, age: 30), age: 30, weightKg: 80,
            reference: nil,
            proteinTenthsRaw: .constant(20), fatTenthsRaw: .constant(10), goalPercentRaw: .constant(0))
        try render(AnyView(noReference), name: "4-objectifs-sans-depense")

        let line = TodayNutritionLine.Model(eatenKcal: day.eaten.kcal, balanceKcal: day.balanceKcal,
                                            proteinG: Int(day.eaten.proteinG.rounded()), proteinGoalG: plan.proteinG)
        try render(AnyView(TodayHeroCard(model: heroModel(nutrition: line), animated: false, onGuide: { _ in })),
                   name: "5-aujourdhui-ligne")

        let rice = MealPer100(kcal: 155, proteinG: 3.3, carbsG: 33.2, fatG: 0.7)
        let chicken = MealPer100(kcal: 189, proteinG: 29.8, carbsG: 0, fatG: 7.8)
        let vegetables = MealPer100(kcal: 36, proteinG: 1.6, carbsG: 4.4, fatG: 0.4)
        let proposal = CoachMealProposal(
            name: "Poulet, riz, légumes", eatenAt: at(13, 5), origin: .photo,
            lines: [.init(name: "Poulet rôti", ciqualCode: 36032, grams: 180, estimated: true, per100: chicken),
                    .init(name: "Riz blanc cuit", ciqualCode: 9104, grams: 200, estimated: true, per100: rice),
                    .init(name: "Légumes", ciqualCode: 20199, grams: 150, estimated: true, per100: vegetables)],
            mealId: nil)
        var saved = proposal
        saved.mealId = "saved"
        let cards = VStack(spacing: 16) {
            CoachMealCard(proposal: proposal, busy: false, onAdd: {}, onEdit: {})
            CoachMealCard(proposal: saved, busy: false, onAdd: {}, onEdit: {})
        }
        try render(AnyView(cards), name: "6-coach-repas")

        // Nutrition 4d: the product card the Coach makes from a label, and the scanner's two panels
        // (mockups 8, 7 and 9), without the camera.
        let skyr = MealPer100(kcal: 63, proteinG: 11, carbsG: 4, fatG: 0.2)
        let product = CoachMealProposal(
            name: "Skyr nature 0 %", eatenAt: at(10, 30), origin: .barcode,
            lines: [.init(name: "Skyr nature 0 %", ciqualCode: nil, grams: 150, estimated: false, per100: skyr)],
            mealId: nil, barcode: "3017620422003")
        try render(AnyView(CoachMealCard(proposal: product, busy: false, onAdd: {}, onEdit: {})),
                   name: "7-coach-etiquette")
        let unknown = VStack(spacing: 24) {
            BarcodeUnknownPanel(barcode: "3017620422003", canReadLabel: true, onPhoto: {}, onManual: {})
            BarcodeUnknownPanel(barcode: "3017620422003", canReadLabel: false, onPhoto: {}, onManual: {})
        }
        try render(AnyView(unknown), name: "8-code-barres-inconnu")
        let known = BarcodeProduct(barcode: "3017620422003", name: "Skyr nature 0 %", per100: skyr,
                                   lastGrams: 150, lastEatenAt: at(10, 30))
        try render(AnyView(BarcodeKnownPanel(product: known, grams: .constant(150), saving: false,
                                             onReread: {}, onAdd: {})),
                   name: "9-code-barres-connu")

        // A new barcode looked up on Open Food Facts: found (values to check before adding), or missing.
        var online = BarcodeProduct(barcode: "3017620422003", name: "Skyr nature 0 % · Siggi's", per100: skyr,
                                    lastGrams: nil, lastEatenAt: 0)
        online.source = .openFoodFacts
        let openFoodFacts = VStack(spacing: 24) {
            BarcodeKnownPanel(product: online, grams: .constant(100), saving: false, onReread: {}, onAdd: {})
            BarcodeUnknownPanel(barcode: "3017620422003", canReadLabel: true, miss: .notFound,
                                onPhoto: {}, onManual: {})
        }
        try render(AnyView(openFoodFacts), name: "12-code-barres-open-food-facts")

        // Dictate and Photo without the Coach screen: the capture sheet listening, then finding the foods
        // (the text field itself is a native control the renderer cannot draw). The proposal opens in the
        // meal editor.
        let said = "150 g de riz basmati, un blanc de poulet grillé et une pomme"
        let capture = VStack(alignment: .leading, spacing: 32) {
            NutritionCaptureBody(mode: .voice, text: .constant(said), isListening: true)
            NutritionCaptureBody(mode: .voice, text: .constant(said), phase: .working, isListening: false)
        }
        try render(AnyView(capture), name: "10-dicter")

        XCTAssertEqual(day.eaten.kcal, 1_495)
        XCTAssertEqual(day.balanceKcal, -605)
        XCTAssertEqual(plan.intakeKcal, 2_560)
    }

    private func heroModel(nutrition: TodayNutritionLine.Model) -> TodayHeroModel {
        TodayHeroModel(
            charge: .init(label: String(localized: "Charge"), score: 72, tint: StrandPalette.recoveryColor(72),
                          caption: nil, route: nil, guide: .charge),
            effort: .init(label: String(localized: "Effort"), score: 9.4, tint: StrandPalette.effortColor,
                          maxValue: 21, decimals: 1, caption: String(localized: "target \(12)–\(14)"),
                          targetRange: 12...14, route: nil, guide: .effort),
            rest: .init(label: String(localized: "Rest"), score: 81, tint: StrandPalette.restColor,
                        caption: SleepDurationText.format(442), route: nil, guide: .rest),
            calories: (TodayEnergy.Split(restingKcal: 1_580, activityKcal: 520), 480),
            restingHR: .init(value: 62, low: 57, high: 66, normal: 58...64),
            hrv: .init(value: 41, low: 32, high: 58, normal: 38...50),
            sourceLabel: "WHOOP",
            nutrition: nutrition)
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
            try png.write(to: folder.appendingPathComponent("nutrition-\(name).png"))
        }
    }
}
