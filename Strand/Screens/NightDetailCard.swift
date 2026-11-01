import SwiftUI
import StrandAnalytics
import StrandDesign
import WhoopStore

// MARK: - Night detail (#today-hosted-cards)
//
// The Sleep tab's "Night detail" indicators, a standalone view so the Today tab can host it too. Both
// surfaces render THIS view from the SAME `SleepModel`, so a value can never differ between them (the
// parity contract).
//
// Personal fork: four coloured tiles, each in the colour of what it measures (sleep blue for efficiency,
// the REM colour for restorative sleep, cyan for breathing, the heart colour for the lowest heart rate),
// with a plain description under the value instead of a "vs typical" that compares a first night with
// itself. The usual value joins the description once there are enough nights. The score and the hours
// against the need are not repeated here: the dial at the top of the tab already shows them, and the
// sleep debt has its own card.

/// The night's lowest sleeping heart rate and when it happened. Only the Sleep tab has it (it loads the
/// night's heart rate); the Today host passes nil and gets the regularity tile in its place.
struct SleepLowestHR: Equatable {
    let bpm: Double
    let at: Date
}

struct NightDetailCard: View {
    let model: SleepModel
    var lowestHR: SleepLowestHR? = nil

    var body: some View {
        SleepIndicatorsCard(tiles: tiles, regularity: regularity)
    }

    // MARK: Tiles

    private var tiles: [SleepIndicatorTile] {
        let s = model.night.stages
        var out: [SleepIndicatorTile] = [
            SleepIndicatorTile(
                id: "efficiency", symbol: "bed.double.fill", tint: StrandPalette.restBright,
                label: String(localized: "Efficiency"),
                value: model.efficiency.latest.map { "\(Int($0.rounded()))" } ?? "—",
                unit: model.efficiency.latest == nil ? "" : "%",
                caption: caption(model.efficiency,
                                 String(localized: "\(SleepDurationText.format(model.night.timeInBed)) in bed")),
                usual: usual(model.efficiency) { "\(Int($0.rounded()))%" }),
            SleepIndicatorTile(
                id: "restorative", symbol: "sparkles", tint: StrandPalette.sleepREM,
                label: String(localized: "Restorative"),
                value: model.restorative.latest.map { "\(Int($0.rounded()))" } ?? "—",
                unit: model.restorative.latest == nil ? "" : "%",
                caption: caption(model.restorative,
                                 String(localized: "\(SleepDurationText.format(s.deep + s.rem)) deep + REM")),
                usual: usual(model.restorative) { "\(Int($0.rounded()))%" }),
            SleepIndicatorTile(
                id: "respiratory", symbol: "lungs.fill", tint: StrandPalette.metricCyan,
                label: String(localized: "Respiratory"),
                value: model.respiratory.latest.map(Self.oneDecimal) ?? "—",
                unit: model.respiratory.latest == nil ? "" : String(localized: "/min"),
                caption: caption(model.respiratory, String(localized: "breaths while asleep")),
                usual: usual(model.respiratory) { Self.oneDecimal($0) }),
        ]
        if let lowestHR {
            out.append(SleepIndicatorTile(
                id: "lowestHR", symbol: "heart.fill", tint: StrandPalette.liquidHeart,
                label: String(localized: "Lowest HR"),
                value: "\(Int(lowestHR.bpm.rounded()))", unit: String(localized: "bpm"),
                caption: String(localized: "at \(AppClock.hourMinuteFormatter().string(from: lowestHR.at))"),
                usual: nil))
        } else {
            out.append(regularityTile)
        }
        return out
    }

    private var regularityTile: SleepIndicatorTile {
        SleepIndicatorTile(
            id: "consistency", symbol: "clock.fill", tint: StrandPalette.restColor,
            label: String(localized: "Consistency"),
            value: model.consistency.latest.map { "\(Int($0.rounded()))" } ?? "—",
            unit: model.consistency.latest == nil ? "" : "%",
            caption: model.consistency.latest == nil
                ? String(localized: "from 3 nights")
                : caption(model.consistency, String(localized: "bedtime regularity")),
            usual: nil)
    }

    /// With the lowest heart rate in the grid, regularity gets the row under it: the tile once it has a
    /// value, the progress toward it before.
    private var regularity: SleepIndicatorsCard.Regularity? {
        guard lowestHR != nil else { return nil }
        if model.consistency.latest != nil { return .tile(regularityTile) }
        return .progress(done: min(model.sleepDebtLedger.nightCount, 3), needed: 3)
    }

    // MARK: Formatting

    /// A carried (stale) value says so; otherwise the plain description.
    private func caption(_ metric: SleepModel.Metric, _ description: String) -> String {
        SleepModel.carriedMetricCaption(latestDay: metric.latestDay, latest: metric.latest) ?? description
    }

    /// The usual value, only from the fifth night on — before that "usual" is the night itself.
    private func usual(_ metric: SleepModel.Metric, _ format: (Double) -> String) -> String? {
        guard metric.series.count >= 5, let typical = metric.typical else { return nil }
        return String(localized: "usual \(format(typical))")
    }

    static func oneDecimal(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(1)).locale(AppLanguage.activeLocale))
    }
}

struct SleepIndicatorTile: Identifiable {
    let id: String
    let symbol: String
    let tint: Color
    let label: String
    let value: String
    let unit: String
    let caption: String
    let usual: String?
}

/// The indicators card itself, pure, so the render test draws it without a model.
struct SleepIndicatorsCard: View {
    enum Regularity {
        case tile(SleepIndicatorTile)
        case progress(done: Int, needed: Int)
    }

    let tiles: [SleepIndicatorTile]
    var regularity: Regularity? = nil

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        NoopCard(tint: StrandPalette.restColor) {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                Text("Indicators").strandOverline()
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(tiles) { SleepIndicatorTileView(tile: $0) }
                }
                switch regularity {
                case .tile(let tile):
                    SleepIndicatorTileView(tile: tile)
                case .progress(let done, let needed):
                    ProgressNote(text: String(localized: "Bedtime regularity from \(needed) nights"),
                                 done: done, total: needed)
                case nil:
                    EmptyView()
                }
            }
        }
    }
}

struct SleepIndicatorTileView: View {
    let tile: SleepIndicatorTile

    /// One height for every tile, so a two-line caption does not make its row uneven.
    static let minHeight: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: NoopMetrics.space2) {
                Image(systemName: tile.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tile.tint)
                    .frame(width: 26, height: 26)
                    .background(tile.tint.opacity(0.16), in: Circle())
                    .accessibilityHidden(true)
                Text(tile.label)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(tile.value)
                    .font(StrandFont.number(24))
                    .foregroundStyle(tile.value == "—" ? StrandPalette.textSecondary : tile.tint)
                if !tile.unit.isEmpty {
                    Text(tile.unit)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
            .monospacedDigit()
            Text(tile.caption)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let usual = tile.usual {
                Text(usual)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Self.minHeight, alignment: .topLeading)
        .padding(12)
        .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius,
                                                                      style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(tile.label): \(tile.value) \(tile.unit), \(tile.caption)"))
    }
}
