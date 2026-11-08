import SwiftUI
import StrandDesign

// MARK: - « Nights of fasting » (personal fork, chantier 15 PR C)
//
// Under the history of the Jeûne page: HRV, resting heart rate and sleep of the nights a fast of 12 h or
// more was running at bedtime, against the other nights of the last 90 days, with the Map's « Ce qui
// ressort » rule. Every figure arrives resolved (`FastingNights.Report`); nothing is computed here.

struct FastingNightsCard: View {
    let report: FastingNights.Report?

    private var fastingCount: Int { report?.fastingCount ?? 0 }
    private var otherCount: Int { report?.otherCount ?? 0 }

    var body: some View {
        NoopCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Nights of fasting")
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer(minLength: 8)
                    Text("Last 90 days · \(fastingCount) nights vs \(otherCount)")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                if let report {
                    HStack(spacing: 8) {
                        ForEach(report.figures) { figure in
                            tile(figure)
                        }
                    }
                    if report.waiting {
                        Text("Waiting for \(report.missingFasting) more fasting nights and \(report.missingOthers) other nights before comparing.")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Reading the nights…")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .frame(height: 72)
                }
                Text("A fasting night: a fast of 12 h or more was running at bedtime; compared with the other nights. A difference shows only beyond its margin of error, « — » otherwise.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func title(_ metric: FastingNightMetric) -> Text {
        switch metric {
        case .hrv: return Text("HRV")
        case .restingHr: return Text("Resting HR")
        case .sleep: return Text("Sleep")
        }
    }

    /// « + 7 ms », « − 2 bpm », « + 23 min »; « — » within the margin or with too few nights.
    private func deltaText(_ figure: FastingNightFigure) -> String {
        guard figure.verdict == .better || figure.verdict == .worse, let delta = figure.delta else { return "—" }
        let magnitude = Int(abs(delta).rounded())
        let unit: String
        switch figure.metric {
        case .hrv: unit = String(localized: "\(magnitude) ms")
        case .restingHr: unit = String(localized: "\(magnitude) bpm")
        case .sleep: unit = String(localized: "\(magnitude) min")
        }
        return (delta >= 0 ? "+ " : "− ") + unit
    }

    /// « 68 vs 61 », « in the margin », « too few ».
    private func detailText(_ figure: FastingNightFigure) -> String {
        switch figure.verdict {
        case .tooFew: return String(localized: "too few")
        case .close: return String(localized: "in the margin")
        case .better, .worse:
            guard let a = figure.fastingMean, let b = figure.otherMean else { return "" }
            return String(localized: "\(value(figure.metric, a)) vs \(value(figure.metric, b))")
        }
    }

    private func value(_ metric: FastingNightMetric, _ raw: Double) -> String {
        switch metric {
        case .sleep: return FastingFormat.duration(minutes: Int(raw.rounded()))
        case .hrv, .restingHr: return "\(Int(raw.rounded()))"
        }
    }

    private func color(_ verdict: FastingNightVerdict) -> Color {
        switch verdict {
        case .better: return StrandPalette.fastingDone
        case .worse: return StrandPalette.deviationOrange
        case .close, .tooFew: return StrandPalette.textSecondary
        }
    }

    private func tile(_ figure: FastingNightFigure) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            title(figure.metric)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1)
            Text(verbatim: deltaText(figure))
                .font(StrandFont.rounded(20))
                .foregroundStyle(color(figure.verdict))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(verbatim: detailText(figure))
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
