import SwiftUI
import StrandDesign

// MARK: - The day picker of the tab roots (personal fork, 5 Nov.)
//
// Sleep and Nutrition each step through days, and each drew its own picker: a grey caption over the date
// between plain chevrons on Sleep, « Yesterday · Wednesday 4 November » between round glass buttons on
// Nutrition. One look for both now: the caption (« Last night », « Yesterday »…) in small grey over the
// date in semibold, centred, between plain ‹ › that dim when there is nowhere to go.

struct DayPickerRow: View {
    /// The relative name of the day (« Last night », « Today »), or nil when the date says it all.
    var caption: String?
    var title: String
    var canGoBack: Bool
    var canGoForward: Bool
    var backLabel: LocalizedStringKey = "Previous day"
    var forwardLabel: LocalizedStringKey = "Next day"
    /// Read out on ‹ when it is dimmed, to say why there is no earlier day.
    var backDisabledHint: Text? = nil
    var onBack: () -> Void
    var onForward: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            chevron("chevron.left", enabled: canGoBack, label: backLabel, action: onBack)
                .accessibilityHint(canGoBack ? Text("") : (backDisabledHint ?? Text("")))
            Spacer(minLength: NoopMetrics.space2)
            VStack(spacing: 1) {
                // The caption's line stays when there is none, so the row keeps one height day to day.
                Text(verbatim: caption ?? " ")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
                Text(verbatim: title)
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: NoopMetrics.space2)
            chevron("chevron.right", enabled: canGoForward, label: forwardLabel, action: onForward)
        }
    }

    private func chevron(_ symbol: String, enabled: Bool, label: LocalizedStringKey,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(StrandPalette.textSecondary.opacity(enabled ? 1 : 0.35))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(LiquidPressStyle())
        .disabled(!enabled)
        .accessibilityLabel(Text(label))
    }
}
