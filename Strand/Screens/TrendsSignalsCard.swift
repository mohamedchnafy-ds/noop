import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Signals against the personal normal (fork chantier 16)
//
// One row per nightly signal — HRV, resting HR, respiration, skin temperature, sleep — read the way an
// endurance coach reads them: the period's mean against the wearer's OWN normal band (mean ± half a
// standard deviation over a longer window, `TrendsOverview.band`), not against a population. Replaces
// the HRV and resting-HR line charts; each row still opens its full metric detail.
struct TrendsSignalsCard: View {
    let data: TrendsPeriodData

    /// One signal: how it is read from a day, how it is printed, and which way is good.
    private struct Signal {
        let metricKey: String
        let title: LocalizedStringKey
        let tint: Color
        let higherIsBetter: Bool?
        let value: (DailyMetric) -> Double?
        let format: (Double) -> String
        let formatDelta: (Double) -> String
    }

    private var signals: [Signal] {
        [
            Signal(metricKey: "hrv", title: "HRV", tint: StrandPalette.metricPurple, higherIsBetter: true,
                   value: { $0.avgHrv },
                   format: { "\(TrendsFormat.int($0)) ms" },
                   formatDelta: { TrendsFormat.signed($0) }),
            Signal(metricKey: "rhr", title: "Resting HR", tint: StrandPalette.metricRose, higherIsBetter: false,
                   value: { $0.restingHr.map(Double.init) },
                   format: { "\(TrendsFormat.int($0)) bpm" },
                   formatDelta: { TrendsFormat.signed($0) }),
            Signal(metricKey: "resp_rate", title: "Respiration", tint: StrandPalette.metricCyan, higherIsBetter: nil,
                   value: { $0.respRateBpm },
                   format: { "\(UnitFormatter.decimal($0, places: 1)) / min" },
                   formatDelta: { TrendsFormat.signed($0, places: 1) }),
            Signal(metricKey: "skin_temp", title: "Skin temp.", tint: StrandPalette.metricAmber, higherIsBetter: nil,
                   value: { $0.skinTempDevC },
                   format: { "\(TrendsFormat.signed($0, places: 1)) °C" },
                   formatDelta: { TrendsFormat.signed($0, places: 1) }),
            Signal(metricKey: "sleep_total_min", title: "Sleep", tint: StrandPalette.restColor, higherIsBetter: true,
                   value: { $0.totalSleepMin },
                   format: { SleepDurationText.format($0) },
                   formatDelta: { ($0 < 0 ? "−" : "+") + SleepDurationText.format(abs($0)) }),
        ]
    }

    var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                TrendsCardHeader(
                    title: "Signals vs your normal", overline: bandOverline,
                    infoLabel: "How it is computed",
                    infoText: "The band is your own normal: the mean over a longer window (30 days for a week, up to a year for longer periods), plus or minus half a standard deviation. The dot is this period's mean; the chip is its change against the previous period. Sleep is compared with your sleep need.")
                .padding(.bottom, NoopMetrics.space1)
                ForEach(Array(signals.enumerated()), id: \.offset) { _, s in
                    row(s)
                }
                Divider().overlay(StrandPalette.hairline)
                legend
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var bandOverline: LocalizedStringKey {
        switch data.range {
        case .week: return "Period mean · band = your normal over 30 days"
        case .month: return "Period mean · band = your normal over 90 days"
        case .quarter: return "Period mean · band = your normal over 6 months"
        case .half, .year, .all: return "Period mean · band = your normal over a year"
        }
    }

    // MARK: Row

    @ViewBuilder
    private func row(_ s: Signal) -> some View {
        let mean = TrendsOverview.mean(data.current, s.value)
        let previous = TrendsOverview.mean(data.previous, s.value)
        let band = TrendsOverview.band(data.bandDays.compactMap(s.value))
        let isSleep = s.metricKey == "sleep_total_min"
        let deviation: TrendsOverview.Deviation? = {
            guard let mean, let band else { return nil }
            return TrendsOverview.deviation(mean, band: band)
        }()
        let dotColor = deviationColor(deviation, higherIsBetter: s.higherIsBetter, tint: s.tint)
        let position: Double = {
            guard let mean, let band else { return 0.5 }
            return TrendsOverview.axisPosition(mean, band: band)
        }()
        NavigationLink(value: TabRoute.metric(s.metricKey)) {
            HStack(spacing: NoopMetrics.rowSpacing) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.title)
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .lineLimit(1)
                    Text(valueLine(mean: mean, signal: s, isSleep: isSleep))
                        .font(StrandFont.captionNumber)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(width: 108, alignment: .leading)
                TrendsBandTrack(
                    position: position,
                    bandRange: band.map { TrendsOverview.axisPosition($0.low, band: $0)...TrendsOverview.axisPosition($0.high, band: $0) },
                    bandTint: s.tint,
                    dotColor: mean == nil ? StrandPalette.surfaceOverlay : dotColor)
                chip(mean: mean, previous: previous, signal: s, isSleep: isSleep)
                    .frame(width: 64, alignment: .trailing)
            }
            .frame(minHeight: NoopMetrics.controlHeight - 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(LiquidPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(s.title))
        .accessibilityValue(Text(accessibilityValue(mean: mean, deviation: deviation, signal: s)))
    }

    /// "47 ms" — or, for sleep, "7h 10m · need 7h 50m" when the need is known.
    private func valueLine(mean: Double?, signal s: Signal, isSleep: Bool) -> String {
        guard let mean else { return String(localized: "No reading") }
        if isSleep, let need = data.sleepNeedMin {
            return String(localized: "\(s.format(mean)) · need \(SleepDurationText.format(need))")
        }
        return s.format(mean)
    }

    /// The change chip: the signed change against the previous period, coloured by whether the move is
    /// good for this signal. Sleep compares with the need instead (a shortfall is what matters at night).
    @ViewBuilder
    private func chip(mean: Double?, previous: Double?, signal s: Signal, isSleep: Bool) -> some View {
        if let mean, isSleep, let need = data.sleepNeedMin {
            let gap = mean - need
            TrendChip(text: s.formatDelta(gap),
                      color: TrendsFormat.changeColor(gap, higherIsBetter: true))
        } else if let change = TrendsOverview.change(current: mean, previous: previous) {
            TrendChip(text: s.formatDelta(change.delta),
                      color: TrendsFormat.changeColor(change.delta, higherIsBetter: s.higherIsBetter))
        } else {
            TrendChip(text: "—", color: StrandPalette.textTertiary)
        }
    }

    /// Inside the band: the signal's own tint. Outside: green when that side is the good one, amber when
    /// not, amber either side for a signal with no good direction (an unusual respiration or skin
    /// temperature is worth a look whichever way it went).
    private func deviationColor(_ deviation: TrendsOverview.Deviation?, higherIsBetter: Bool?, tint: Color) -> Color {
        guard let deviation else { return tint }
        switch deviation {
        case .inside: return tint
        case .above:
            guard let better = higherIsBetter else { return StrandPalette.metricAmber }
            return better ? StrandPalette.statusPositive : StrandPalette.metricAmber
        case .below:
            guard let better = higherIsBetter else { return StrandPalette.metricAmber }
            return better ? StrandPalette.metricAmber : StrandPalette.statusPositive
        }
    }

    private func accessibilityValue(mean: Double?, deviation: TrendsOverview.Deviation?, signal s: Signal) -> String {
        guard let mean else { return String(localized: "No reading") }
        let v = s.format(mean)
        switch deviation {
        case .inside?: return String(localized: "\(v), inside your normal")
        case .above?: return String(localized: "\(v), above your normal")
        case .below?: return String(localized: "\(v), below your normal")
        case nil: return v
        }
    }

    private var legend: some View {
        HStack(spacing: NoopMetrics.space4) {
            HStack(spacing: NoopMetrics.space1 + 2) {
                Capsule().fill(StrandPalette.metricPurple.opacity(0.22)).frame(width: 22, height: 8)
                Text("your normal (± ½ SD)")
            }
            HStack(spacing: NoopMetrics.space1 + 2) {
                Circle().fill(StrandPalette.metricAmber).frame(width: 10, height: 10)
                Text("outside it")
            }
        }
        .font(StrandFont.footnote)
        .foregroundStyle(StrandPalette.textTertiary)
        .accessibilityHidden(true)
    }
}
