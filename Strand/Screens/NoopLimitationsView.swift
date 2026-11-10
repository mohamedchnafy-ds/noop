import SwiftUI
import StrandDesign

// MARK: - NoopLimitationsView — "what NOOP can (and can't) read off each strap"
//
// The iOS/macOS twin of Android's NoopLimitationsScreen: a plain tri-state capability grid listing every
// metric NOOP surfaces and whether it comes live off a WHOOP 4.0 vs a 5.0/MG. Marks mirror the
// decoder/analytics truth (Interpreter / AnalyticsEngine / HistoricalStreams): full = read live; partial =
// an on-device estimate or an experimental / firmware-gated read; none = not off the strap (SpO₂ % is
// import-only on both; blood pressure has no path). A legend carries the meaning in place of per-row prose.
// Rendered through the shared ScreenScaffold like every other destination — reached from the iOS More tab
// (Data group) and the macOS sidebar (Data & App); navigation chrome (back / tab bar) handles dismissal.

struct NoopLimitationsView: View {

    /// Tri-state support for a metric on a given strap — honest, never overstated.
    private enum LimitState {
        case full, partial, none

        /// SF Symbol glyph shown in the strap column.
        var glyph: String {
            switch self {
            case .full:    return "checkmark"
            case .partial: return "minus"
            case .none:    return "xmark"
            }
        }

        var tint: Color {
            switch self {
            case .full:    return StrandPalette.statusPositive
            case .partial: return StrandPalette.statusWarning
            case .none:    return StrandPalette.textTertiary
            }
        }

        /// Spoken label for the row's accessibility description.
        var spoken: String {
            switch self {
            case .full:    return String(localized: "Yes")
            case .partial: return String(localized: "Partly")
            case .none:    return String(localized: "No")
            }
        }
    }

    /// One row: a metric, and how it reads on a 4.0 vs a 5.0/MG. No note — the legend carries the meaning.
    private struct LimitRow: Identifiable {
        let feature: String
        let spokenFeature: String
        let whoop4: LimitState
        let whoop5: LimitState
        var id: String { spokenFeature }
    }

    private let rows: [LimitRow] = [
        LimitRow(feature: String(localized: "Live heart rate"), spokenFeature: "Live heart rate", whoop4: .full, whoop5: .full),
        LimitRow(feature: String(localized: "HRV (rMSSD)"), spokenFeature: "HRV", whoop4: .full, whoop5: .full),
        LimitRow(feature: String(localized: "Sleep staging"), spokenFeature: "Sleep staging", whoop4: .full, whoop5: .full),
        LimitRow(feature: String(localized: "Recovery & strain"), spokenFeature: "Recovery and strain", whoop4: .full, whoop5: .full),
        // `.partial` on BOTH generations: the displayed respiratory rate is always
        // `SleepStager.respRateFromRR` — an on-device RSA estimate off the R-R stream, which is what
        // `.partial` means — computed with NO family branch (`AnalyticsEngine`'s `respRateDaily`). The
        // 5.0/MG v18 wire carries no respiratory channel at all (`Whoop5HistoricalTests…` pins
        // `resp_rate_raw` nil); the 4.0 v24 layout DOES carry `resp_rate_raw`, but it is a raw ADC stored
        // unconverted (schema: "resp rate computed server-side", `HistoricalStreams` keeps it as a raw
        // `RespSample`) and never becomes the shown value. Neither is "read live off the strap" (`.full`)
        // — which is also why an over-counted-R-R 4.0 night (#1331) blanks it.
        LimitRow(feature: String(localized: "Respiratory rate"), spokenFeature: "Respiratory rate", whoop4: .partial, whoop5: .partial),
        LimitRow(feature: String(localized: "Stress (on-device)"), spokenFeature: "Stress", whoop4: .full, whoop5: .full),
        LimitRow(feature: String(localized: "Workout detection"), spokenFeature: "Workout detection", whoop4: .full, whoop5: .full),
        LimitRow(feature: String(localized: "Skin temperature"), spokenFeature: "Skin temperature", whoop4: .partial, whoop5: .full),
        LimitRow(feature: String(localized: "Steps"), spokenFeature: "Steps", whoop4: .partial, whoop5: .full),
        LimitRow(feature: String(localized: "Blood oxygen (SpO₂ %)"), spokenFeature: "Blood oxygen", whoop4: .none, whoop5: .none),
        LimitRow(feature: String(localized: "ECG"), spokenFeature: "ECG", whoop4: .none, whoop5: .partial),
        LimitRow(feature: String(localized: "Blood pressure"), spokenFeature: "Blood pressure", whoop4: .none, whoop5: .none),
    ]

    /// The strap whose column is shown: the connected family (the same key the Settings rows read).
    @AppStorage("selectedWhoopModel") private var selectedWhoopModelRaw = WhoopModel.whoop4.rawValue

    private var isFiveMG: Bool { selectedWhoopModelRaw == WhoopModel.whoop5mg.rawValue }

    var body: some View {
        // Fork chantier 17: ONE list, the one of the active strap, instead of a 4.0 / 5.0-MG table.
        ScreenScaffold(title: "What NOOP reads",
                       subtitle: isFiveMG ? "What your WHOOP 5.0/MG sends." : "What your WHOOP 4.0 sends.") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                SettingsListGroup(caption: String(localized: "Measures")) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                        if idx > 0 { SettingsListDivider() }
                        let state = isFiveMG ? row.whoop5 : row.whoop4
                        SettingsListValue(title: row.feature, value: state.spoken, tint: state.tint)
                    }
                }
                legendCard
            }
        }
        .noopEntranceRoot()
    }

    // MARK: - Cards

    private var legendCard: some View {
        SettingsListGroup(note: String(localized: "The list follows the active strap: with a 5.0/MG the lines change by themselves.")) {
            VStack(alignment: .leading, spacing: 10) {
                legendRow(.full, "Read live off the strap")
                legendRow(.partial, "On-device estimate, or experimental / firmware-gated")
                legendRow(.none, "Not from the strap. SpO₂ can be filled by importing a WHOOP or Health export.")
            }
            .padding(.vertical, NoopMetrics.space3)
        }
    }

    private func legendRow(_ state: LimitState, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            supportCell(state)
            Text(label).font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func supportCell(_ state: LimitState) -> some View {
        Image(systemName: state.glyph)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(state.tint)
            .frame(width: 52)
            .accessibilityHidden(true)
    }
}
