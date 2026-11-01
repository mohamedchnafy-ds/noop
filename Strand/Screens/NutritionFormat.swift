import SwiftUI
import StrandDesign
import WhoopStore

// Personal fork, Nutrition: how the Nutrition screens write their numbers, and the small pieces they share
// (the arc gauge, the coloured dot of a macro, the origin icon of a meal). Numbers follow the app language
// ("1 495", "2,0"); a deficit is written with a true minus sign ("−605").

enum NutritionFormat {

    private static var locale: Locale { AppLanguage.activeLocale }

    /// Whole kcal or grams with the language's grouping: "1 495".
    static func whole(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    /// A gram amount to the whole gram: "22".
    static func grams(_ value: Double) -> String {
        whole(Int(value.rounded()))
    }

    /// "160 g".
    static func gramsUnit(_ value: Int) -> String { whole(value) + " g" }

    /// "1 844 kcal".
    static func kcalUnit(_ value: Int) -> String { whole(value) + " kcal" }

    /// "650 kcal · P 40 · G 80 · L 18".
    static func kcalAndMacros(_ n: MealNutrients) -> String { kcalUnit(n.kcal) + " · " + macroLine(n) }

    /// Up to one decimal, no grouping, for a field the wearer edits: "28", "28,5".
    static func editable(_ value: Double) -> String {
        MealMath.tenth(value).formatted(.number.precision(.fractionLength(0...1)).grouping(.never).locale(locale))
    }

    /// Exactly one decimal: "2,0", "1,10".
    static func oneDecimalText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).grouping(.never).locale(locale))
    }

    /// The goal factor `1 + percent / 100` with two decimals: "1,10", "0,95".
    static func factor(_ percent: Int) -> String {
        (1 + Double(percent) / 100).formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(locale))
    }

    /// A formula coefficient as published, without trailing zeros: "88,362", "13,397".
    static func coefficient(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...4)).grouping(.never).locale(locale))
    }

    /// "−605", "+120", "0".
    static func signedKcal(_ value: Int) -> String {
        if value < 0 { return "\u{2212}" + whole(-value) }
        if value > 0 { return "+" + whole(value) }
        return whole(0)
    }

    /// A share in percent with the language's spacing: "25 %".
    static func percentText(_ value: Int) -> String {
        (Double(value) / 100).formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    /// A signed goal percentage: "−10 %", "+10 %".
    static func signedPercent(_ value: Int) -> String {
        let magnitude = percentText(abs(value))
        if value < 0 { return "\u{2212}" + magnitude }
        if value > 0 { return "+" + magnitude }
        return magnitude
    }

    /// Hours and minutes in the app language: "07:40".
    static func mealClock(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(locale))
    }

    /// "dimanche 1 novembre".
    static func longDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
    }

    /// The protein / carbs / fat line of a meal: "P 22 · G 82 · L 11" in French.
    static func macroLine(_ n: MealNutrients) -> String {
        String(localized: "P \(grams(n.proteinG)) · C \(grams(n.carbsG)) · F \(grams(n.fatG))")
    }

    /// The meal's name, with the quantity when it is one food weighed: "Skyr nature · 150 g".
    static func mealTitle(_ entry: MealEntry) -> String {
        if entry.items.count == 1, let g = entry.items[0].grams {
            let quantity = (entry.items[0].gramsEstimated ? "≈ " : "") + editable(g) + " g"
            return entry.meal.name + " · " + quantity
        }
        return entry.meal.name
    }

    /// The meal's energy, "≈ 650" when a quantity was estimated from a photo.
    static func mealKcal(_ entry: MealEntry) -> String {
        let text = whole(entry.mealTotals.kcal)
        return entry.items.contains(where: \.gramsEstimated) ? "≈ " + text : text
    }

    /// "07:40 · estimate · P 40 · G 80 · L 18".
    static func mealDetail(_ entry: MealEntry) -> String {
        var parts = [mealClock(Date(timeIntervalSince1970: TimeInterval(entry.meal.eatenAt)))]
        if entry.items.contains(where: \.gramsEstimated) { parts.append(String(localized: "estimate")) }
        parts.append(macroLine(entry.mealTotals))
        return parts.joined(separator: " · ")
    }
}

/// Where a meal came from: its icon and what VoiceOver says.
enum NutritionOrigin {
    static func symbol(_ origin: MealOrigin) -> String {
        switch origin {
        case .manual: return "pencil"
        case .barcode: return "barcode"
        case .photo: return "camera"
        case .voice: return "mic"
        }
    }

    static func spoken(_ origin: MealOrigin) -> String {
        switch origin {
        case .manual: return String(localized: "typed by hand")
        case .barcode: return String(localized: "barcode")
        case .photo: return String(localized: "estimated from a photo")
        case .voice: return String(localized: "dictated to the Coach")
        }
    }
}

/// The macro colours, the same ones the Coach's meal card uses.
enum NutritionMacro: CaseIterable {
    case protein, carbs, fat

    var tint: Color {
        switch self {
        case .protein: return StrandPalette.metricCyan
        case .carbs: return StrandPalette.metricAmber
        case .fat: return StrandPalette.metricPurple
        }
    }

    var title: String {
        switch self {
        case .protein: return String(localized: "Protein")
        case .carbs: return String(localized: "Carbs")
        case .fat: return String(localized: "Fat")
        }
    }

    func grams(_ n: MealNutrients) -> Double {
        switch self {
        case .protein: return n.proteinG
        case .carbs: return n.carbsG
        case .fat: return n.fatG
        }
    }
}

/// The small coloured dot in front of a macro's name.
struct NutritionMacroDot: View {
    let macro: NutritionMacro
    var size: CGFloat = 8

    var body: some View {
        Circle().fill(macro.tint).frame(width: size, height: size).accessibilityHidden(true)
    }
}

/// A meal's origin in a tinted disc (pencil, barcode, camera, microphone).
struct NutritionOriginIcon: View {
    let origin: MealOrigin

    var body: some View {
        Image(systemName: NutritionOrigin.symbol(origin))
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(StrandPalette.onDarkSecondary)
            .frame(width: 34, height: 34)
            .background(StrandPalette.onDarkSecondary.opacity(0.14), in: Circle())
            .accessibilityLabel(Text(NutritionOrigin.spoken(origin)))
    }
}

/// The big 180° gauge of the day's intake: eaten against the goal, full when the goal is reached; past
/// it the scale stretches to what was eaten and a mark keeps the goal visible. No goal, no fill.
struct NutritionIntakeGauge: View {
    var eatenKcal: Int
    var goalKcal: Int?

    static let radius: CGFloat = 90
    static let lineWidth: CGFloat = 12

    /// Fill and goal mark as fractions of the arc.
    static func intakeArc(eaten: Int, goal: Int?) -> (fill: Double, goalMark: Double?) {
        guard let goal, goal > 0 else { return (0, nil) }
        let scale = Double(max(goal, eaten))
        return (Double(max(eaten, 0)) / scale, eaten > goal ? Double(goal) / scale : nil)
    }

    var body: some View {
        let arc = Self.intakeArc(eaten: eatenKcal, goal: goalKcal)
        let width = 2 * Self.radius + Self.lineWidth + 8
        let height = Self.radius + Self.lineWidth + 10
        ZStack(alignment: .bottom) {
            Canvas { ctx, size in
                let center = CGPoint(x: size.width / 2, y: size.height - Self.lineWidth / 2 - 4)
                func point(_ t: Double, _ r: CGFloat) -> CGPoint {
                    let a = Double.pi * (1 + min(1, max(0, t)))
                    return CGPoint(x: center.x + r * CGFloat(cos(a)), y: center.y + r * CGFloat(sin(a)))
                }
                func arcPath(_ from: Double, _ to: Double) -> Path {
                    var p = Path()
                    let steps = max(2, Int((to - from) * 96))
                    for i in 0...steps {
                        let pt = point(from + (to - from) * Double(i) / Double(steps), Self.radius)
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                    return p
                }
                ctx.stroke(arcPath(0, 1), with: .color(StrandPalette.surfaceInset),
                           style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                if arc.fill > 0.002 {
                    ctx.stroke(arcPath(0, arc.fill), with: .color(StrandPalette.onDarkSecondary),
                               style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                }
                if let mark = arc.goalMark {
                    var tick = Path()
                    tick.move(to: point(mark, Self.radius - Self.lineWidth))
                    tick.addLine(to: point(mark, Self.radius + Self.lineWidth))
                    ctx.stroke(tick, with: .color(StrandPalette.textPrimary.opacity(0.85)),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
            VStack(spacing: 0) {
                Text(verbatim: NutritionFormat.whole(eatenKcal))
                    .font(StrandFont.number(36, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("kcal eaten")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            .frame(width: Self.radius * 1.4)
            .padding(.bottom, 2)
        }
        .frame(width: width, height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(goalKcal.map {
            String(localized: "\(NutritionFormat.whole(eatenKcal)) kcal eaten of a \(NutritionFormat.whole($0)) kcal goal")
        } ?? String(localized: "\(NutritionFormat.whole(eatenKcal)) kcal eaten")))
    }
}
