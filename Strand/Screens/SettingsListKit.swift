import SwiftUI
import StrandDesign

// MARK: - Settings list kit (fork chantier 17, step 2)
//
// The rows the rebuilt Settings screens share (Automations, Power saving, Siri & Shortcuts, What NOOP
// reads, the Shortcuts export): a 52 pt row with its name on the left and its control on the right, the
// explanation in an info popover instead of a paragraph in the page, a small mark for « Experimental »
// or « Alert ». Same look as the domain rows in `SettingsView`; design tokens only.

/// The small mark next to a row's name.
enum SettingsRowBadge {
    case experimental, alert

    var label: LocalizedStringKey {
        switch self {
        case .experimental: return "Experimental"
        case .alert: return "Alert"
        }
    }

    var tint: Color {
        switch self {
        case .experimental: return StrandPalette.deviationOrange
        case .alert: return StrandPalette.stressHigh
        }
    }
}

/// The ⓘ of a row: a popover with its explanation, which is already a localized string.
struct SettingsInfoPopover: View {
    let text: String
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Image(systemName: "info.circle")
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textTertiary)
                .frame(width: NoopMetrics.compactControlSize, height: NoopMetrics.compactControlSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Explanation")
        .popover(isPresented: $showing, arrowEdge: .top) {
            Text(verbatim: text)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(NoopMetrics.cardInnerPadding)
                .frame(maxWidth: 320)
                .background(NoopPanelSurface(cornerRadius: NoopVisualStyle.compactRadius, elevated: true))
                .trendsPopoverAdaptation()
        }
    }
}

/// A grey caption over one card of rows; an optional footnote under it. Rows inside are separated by
/// `SettingsListDivider`.
struct SettingsListGroup<Content: View>: View {
    var caption: String? = nil
    var note: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let caption {
                Text(verbatim: caption)
                    .font(StrandFont.footnote.weight(.semibold))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .padding(.horizontal, 4)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.horizontal, NoopMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
            if let note {
                Text(verbatim: note)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

struct SettingsListDivider: View {
    var body: some View {
        Rectangle()
            .fill(StrandPalette.hairline)
            .frame(height: 1)
    }
}

/// One row: name (with ⓘ and mark) on the left, the control on the right.
struct SettingsListRow<Trailing: View>: View {
    let title: String
    var info: String? = nil
    var badge: SettingsRowBadge? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: NoopMetrics.space3) {
            HStack(spacing: NoopMetrics.space2) {
                Text(verbatim: title)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let info {
                    SettingsInfoPopover(text: info)
                }
                if let badge {
                    Text(badge.label)
                        .font(StrandFont.caption)
                        .foregroundStyle(badge.tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(badge.tint.opacity(0.5), lineWidth: 1)
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
                .layoutPriority(1)
        }
        .frame(minHeight: 52)
    }
}

/// A switch row.
struct SettingsListToggle: View {
    let title: String
    var info: String? = nil
    var badge: SettingsRowBadge? = nil
    @Binding var isOn: Bool

    var body: some View {
        SettingsListRow(title: title, info: info, badge: badge) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .tint(StrandPalette.switchOn)
        }
    }
}

/// A menu row: the current choice on the right.
struct SettingsListMenu<T: Hashable>: View {
    let title: String
    var info: String? = nil
    @Binding var selection: T
    let options: [(String, T)]

    var body: some View {
        SettingsListRow(title: title, info: info) {
            Picker(title, selection: $selection) {
                ForEach(options.indices, id: \.self) { index in
                    Text(verbatim: options[index].0).tag(options[index].1)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(StrandPalette.textSecondary)
        }
    }
}

/// A −/+ row with its value in words.
struct SettingsListStepper: View {
    let title: String
    var info: String? = nil
    @Binding var value: Int
    let suffix: String
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        SettingsListRow(title: title, info: info) {
            HStack(spacing: 10) {
                Text(verbatim: "\(value) \(suffix)")
                    .font(StrandFont.bodyNumber)
                    .foregroundStyle(StrandPalette.textPrimary)
                Stepper(title, value: $value, in: range, step: step)
                    .labelsHidden()
            }
        }
    }
}

/// A row that only shows a value (no control).
struct SettingsListValue: View {
    let title: String
    var info: String? = nil
    let value: String
    var tint: Color = StrandPalette.textSecondary

    var body: some View {
        SettingsListRow(title: title, info: info) {
            Text(verbatim: value)
                .font(StrandFont.body)
                .foregroundStyle(tint)
        }
    }
}
