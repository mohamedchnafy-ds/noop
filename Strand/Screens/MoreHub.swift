import SwiftUI
import StrandDesign

// MARK: - More hub (fork)
//
// The iPhone More tab used to be one long index of ~30 rows in four collapsible sections. It is now six
// groups (Training, Nutrition, Health & recovery, Analysis, Data, App settings); each opens its own
// screen, or a screen listing the entries it holds. Nothing was removed: every former row lives in one
// group. The group model and the row label are shared (not iOS-only) so the hub renders to PNG in the
// macOS test target; the navigation itself stays in `RootTabView`.

/// One of the six groups of the More tab, with the copy and the colour its row shows.
enum MoreHubGroup: String, CaseIterable, Hashable, Identifiable {
    case training, nutrition, healthRecovery, analysis, data, appSettings

    var id: String { rawValue }

    /// The group's name, used for its row and as the title of the screen it opens.
    var title: LocalizedStringKey {
        switch self {
        case .training: return "Training"
        case .nutrition: return "Nutrition"
        case .healthRecovery: return "Health & recovery"
        case .analysis: return "Analysis"
        case .data: return "Data"
        case .appSettings: return "App settings"
        }
    }

    /// One line naming what the group holds, under the title (and as the subtitle of its screen).
    var summary: LocalizedStringKey {
        switch self {
        case .training: return "Calendar, Lift Log, activities, intervals, live heart rate"
        case .nutrition: return "Meal journal, goals, barcodes"
        case .healthRecovery: return "Health, stress, breathing, rhythm, lab book"
        case .analysis: return "What moves you, intelligence, insights, explore, compare"
        case .data: return "Fused data, Apple Health, Mi Band, sources, backup, export"
        case .appSettings: return "Alarms, automations, Siri, power saving, test centre, settings"
        }
    }

    /// SF Symbol drawn, alone and tinted, at the head of the row.
    var icon: String {
        switch self {
        case .training: return "dumbbell.fill"
        case .nutrition: return "fork.knife"
        case .healthRecovery: return "heart.text.square.fill"
        case .analysis: return "chart.line.uptrend.xyaxis"
        case .data: return "cylinder.split.1x2.fill"
        case .appSettings: return "slider.horizontal.3"
        }
    }

    /// The icon's colour: each group takes the colour of the world it opens (Effort blue for training,
    /// the activity gold of Calories for nutrition, the heart rose for health, the HRV teal for
    /// analysis); the two utility groups stay neutral grey (fork chantier 7 mockup « Plus »).
    var tint: Color {
        switch self {
        case .training: return StrandPalette.effortColor
        case .nutrition: return StrandPalette.caloriesActivity
        case .healthRecovery: return StrandPalette.liquidHeart
        case .analysis: return StrandPalette.metricCyan
        case .data, .appSettings: return StrandPalette.textSecondary
        }
    }
}

/// The label of one group row in the More hub: the tinted icon alone (no tile behind it, fork chantier 7),
/// the group name, its one-line summary and a trailing chevron. A hairline closes every row but the last
/// of the card.
struct MoreHubRowLabel: View {
    let group: MoreHubGroup
    var showsDivider = true

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: group.icon)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(group.tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.title)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(group.summary)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(StrandPalette.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(StrandPalette.hairline)
                    .frame(height: 1)
            }
        }
        .padding(.horizontal, 18)
        .contentShape(Rectangle())
    }
}

/// The More hub's single card: the six group rows in order. `row` wraps each label in the caller's
/// navigation link (the tab's `NavigationPath` values live in `RootTabView`); the render test passes the
/// bare label.
struct MoreHubCard<Row: View>: View {
    @ViewBuilder let row: (MoreHubGroup, _ isLast: Bool) -> Row

    var body: some View {
        NoopCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(MoreHubGroup.allCases) { group in
                    row(group, group == MoreHubGroup.allCases.last)
                }
            }
            .padding(.vertical, 2)
            .clipShape(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        }
    }
}
