import SwiftUI
import StrandDesign

// The pared-down Training screen (fork chantier 18, maquette 2 « Écran Entraînement épuré »): the screen answers
// « what do I do today? ». The title with an « i » for the legend and a calendar button for the month; the week
// as a compact strip with no arrows and no count (a swipe moves it, « Today » brings it back); the day's
// session in large; then one line each for Progression, Programs (the list, New, Import, Plan the week), the
// « Start » sheet for any other session, and the history.

/// The header: « Training », then « Today » when the week or month shown is not the current one, the « i »
/// that shows the legend, the calendar button that switches to the month and back, and the More avatar in
/// the iOS tab shell. In the month, ‹ month › under it.
struct TrainingCompactHeader: View {
    @Binding var mode: TrainingViewMode
    @Binding var showsLegend: Bool
    /// The period shown is not the one holding today: « Today » brings it back.
    let isAwayFromToday: Bool
    /// "November 2026", shown with ‹ › in the month.
    let monthTitle: String
    var onToday: () -> Void = {}
    var onPrevious: () -> Void = {}
    var onNext: () -> Void = {}
    /// Not `private`: that would make the memberwise initializer the screen calls private too.
    @Environment(\.showsMoreAvatar) var showsMoreAvatar

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            HStack(alignment: .center, spacing: NoopMetrics.space2) {
                Text("Training")
                    .font(StrandFont.screenTitle)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if isAwayFromToday {
                    Button(action: onToday) {
                        Text("Today")
                            .font(StrandFont.subhead.weight(.semibold))
                            .foregroundStyle(StrandPalette.accent)
                            .padding(.horizontal, NoopMetrics.space3)
                            .frame(minHeight: NoopMetrics.compactControlSize)
                    }
                    .buttonStyle(.plain)
                }
                circleButton(showsLegend ? "info.circle.fill" : "info.circle",
                             label: Text("Legend")) { showsLegend.toggle() }
                circleButton(mode == .month ? "calendar.circle.fill" : "calendar",
                             label: mode == .month ? Text("Week") : Text("Month")) {
                    mode = mode == .month ? .week : .month
                }
                if showsMoreAvatar {
                    // The ◎ button keeps this week's ring and today's Start (personal fork, chantier 20).
                    EssentialModeButton()
                    MoreAvatarButton()
                }
            }
            if mode == .month {
                HStack(spacing: 0) {
                    TrainingPeriodArrow(symbol: "chevron.left", label: "Previous", action: onPrevious)
                    Text(verbatim: monthTitle)
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                    TrainingPeriodArrow(symbol: "chevron.right", label: "Next", action: onNext)
                }
            }
        }
    }

    private func circleButton(_ symbol: String, label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(width: NoopMetrics.compactControlSize, height: NoopMetrics.compactControlSize)
                .background(StrandPalette.surfaceRaised, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// One line of the Training screen: a title, a grey line under it, an optional mark before the chevron.
struct TrainingLineLabel: View {
    let title: Text
    let detail: Text?
    var mark: Image? = nil
    var markTint: Color = StrandPalette.chargeColor

    var body: some View {
        HStack(spacing: NoopMetrics.space3) {
            VStack(alignment: .leading, spacing: NoopMetrics.spaceHalf) {
                title
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                if let detail {
                    detail
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: NoopMetrics.space2)
            if let mark {
                mark
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(markTint)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, NoopMetrics.space4)
        .padding(.vertical, NoopMetrics.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoopPanelSurface())
        .contentShape(Rectangle())
    }
}
