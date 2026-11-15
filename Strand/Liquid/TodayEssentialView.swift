import SwiftUI
import StrandDesign

// MARK: - Today, essential mode (personal fork, chantier 20)
//
// The four rings in the middle of the screen, the live heart rate going round them as an electrocardiogram
// (one spike per heartbeat, the heart in the centre beating with it), then the four figures in small. A
// figure tapped lights its ring alone and writes it in the centre. Every number is the hero card's own
// (`TodayHeroModel.heroRings`, `ringText`, `activityText`), so the two layouts cannot disagree.

struct TodayEssentialView: View {
    var model: TodayHeroModel
    var animated: Bool
    /// The grey date line of the normal header, e.g. « FRIDAY 13 NOVEMBER ».
    var dateLine: String
    /// False for a past day: the live heart rate belongs to today alone, so neither the trace nor the
    /// centre's number is drawn.
    var isToday: Bool = true

    @State var selected: Int?

    private static let ringsDiameter: CGFloat = 248
    private static let ringsLine: CGFloat = 17
    private static let traceDiameter: CGFloat = 340
    private static let traceRadius: CGFloat = 141

    /// The four figures, in the rings' order (outside to inside).
    private struct Figure {
        var label: String
        var tint: Color
        var value: String
        var unit: String?
    }

    private var figures: [Figure] {
        let calUnit: String = {
            guard let goal = model.calories.goal, goal > 0 else { return String(localized: "kcal") }
            return "/ " + Int(goal.rounded()).formatted(.number.locale(AppLanguage.activeLocale))
        }()
        return [
            Figure(label: String(localized: "Activity"), tint: StrandPalette.caloriesActivity,
                   value: model.activityText ?? "—", unit: calUnit),
            Figure(label: model.charge.label, tint: model.chargeTint,
                   value: TodayHeroModel.ringText(model.charge) ?? "—", unit: model.charge.caption),
            Figure(label: model.effort.label, tint: StrandPalette.effortColor,
                   value: TodayHeroModel.ringText(model.effort) ?? "—", unit: model.effort.caption),
            Figure(label: model.rest.label, tint: StrandPalette.restRing,
                   value: TodayHeroModel.ringText(model.rest) ?? "—", unit: model.rest.caption)
        ]
    }

    /// The rings, the others dimmed while one is picked.
    private var rings: [TodayRing] {
        model.heroRings.enumerated().map { (index: Int, ring: TodayRing) -> TodayRing in
            guard let selected, selected != index else { return ring }
            var dim = ring
            dim.tint = ring.tint.opacity(0.22)
            dim.deep = ring.deep.map { $0.opacity(0.22) }
            return dim
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            EssentialHeader(caption: dateLine)
            Spacer(minLength: NoopMetrics.space3)
            ZStack {
                if isToday {
                    EssentialHeartTrace(diameter: Self.traceDiameter, radius: Self.traceRadius,
                                        ringsEdge: Self.ringsDiameter / 2 + 4)
                }
                TodayConcentricRings(rings: rings, diameter: Self.ringsDiameter, lineWidth: Self.ringsLine,
                                     spacing: 6, animated: animated, drawKey: "essential.today.rings")
                    .animation(.easeOut(duration: 0.25), value: selected)
                center
            }
            .frame(width: Self.traceDiameter, height: Self.traceDiameter)
            .accessibilityElement(children: .contain)
            HStack(spacing: 4) {
                ForEach(Array(figures.enumerated()), id: \.offset) { index, figure in
                    EssentialFigure(label: figure.label, tint: figure.tint, value: figure.value,
                                    selected: selected == index,
                                    onTap: { pick(index) })
                }
            }
            .padding(.top, NoopMetrics.space2)
            Spacer(minLength: NoopMetrics.space3)
        }
        .frame(maxWidth: .infinity, minHeight: 600)
    }

    @ViewBuilder private var center: some View {
        if let selected, selected < figures.count {
            let figure = figures[selected]
            VStack(spacing: 0) {
                Text(verbatim: figure.label)
                    .font(StrandFont.caption.weight(.semibold))
                    .foregroundStyle(figure.tint)
                Text(verbatim: figure.value)
                    .font(StrandFont.number(24, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                if let unit = figure.unit {
                    Text(verbatim: unit)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
            .frame(width: 86)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .transition(.opacity)
        } else if isToday {
            EssentialHeartCenter()
                .transition(.opacity)
        }
    }

    private func pick(_ index: Int) {
        StrandHaptic.selection.play()
        withAnimation(.easeOut(duration: 0.2)) { selected = selected == index ? nil : index }
    }
}
