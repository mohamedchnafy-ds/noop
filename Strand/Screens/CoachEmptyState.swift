import SwiftUI
import StrandDesign

/// A round header button face of the Coach screen (personal fork, Coach mockup 1): the history, a new
/// conversation and the ⋯ menu all share it, so the three read as one row.
struct CoachHeaderIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(StrandFont.headline)
            .foregroundStyle(StrandPalette.textPrimary)
            .frame(width: 44, height: 44)
            .background(StrandPalette.surfaceInset, in: Circle())
            .overlay(Circle().strokeBorder(StrandPalette.hairline, lineWidth: 1))
            .contentShape(Circle())
    }
}

/// What an empty conversation shows (personal fork, Coach mockup 1): the brief on demand, the suggested
/// questions theme by theme, what the coach reads, and when anything is sent.
///
/// Nothing here sends on its own. The brief runs only when its card is tapped, and a suggestion is asked
/// only when it is tapped, both through the callbacks the screen hands in (`beginBriefIfNeeded` and
/// `submit` on the engine).
struct CoachEmptyState: View {
    /// Whether the brief can run: it reads the wearer's data, so it needs "Use my data".
    let briefAvailable: Bool
    let providerName: String
    let onBrief: () -> Void
    let onAsk: (String) -> Void
    let onShowData: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            briefCard
            ForEach(CoachPrompts.Theme.allCases) { theme in
                themeSection(theme)
            }
            footer
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Brief

    /// The brief card. Without "Use my data" the brief cannot read anything, so the card says so and
    /// opens "What the coach reads", where the switch is.
    private var briefCard: some View {
        Button {
            if briefAvailable { onBrief() } else { onShowData() }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "sun.max.fill")
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.metricAmber)
                    .frame(width: 34, height: 34)
                    .background(StrandPalette.metricAmber.opacity(0.16), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today's brief")
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Group {
                        if briefAvailable {
                            Text("Readiness, session and recovery in 3 lines")
                        } else {
                            Text("Turn on “Use my data” first")
                        }
                    }
                    .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if briefAvailable {
                    Text("Generate")
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.accent)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 32)
                        .overlay(Capsule(style: .continuous)
                            .strokeBorder(StrandPalette.accent.opacity(0.5), lineWidth: 1))
                } else {
                    Image(systemName: "chevron.right")
                        .font(StrandFont.caption.weight(.semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 64)
            .background(NoopPanelSurface(cornerRadius: 22))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(LiquidPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(briefAvailable ? Text("Generates today’s brief")
                                          : Text("Opens what the coach reads"))
    }

    // MARK: Suggestions

    private func themeSection(_ theme: CoachPrompts.Theme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(themeTitle(theme))
                    .font(StrandFont.overline)
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(StrandPalette.textSecondary)
            } icon: {
                Image(systemName: themeSymbol(theme))
                    .font(StrandFont.caption.weight(.semibold))
                    .foregroundStyle(themeTint(theme))
            }
            .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(theme.prompts.enumerated()), id: \.element) { index, prompt in
                    if index > 0 {
                        Rectangle().fill(StrandPalette.hairline).frame(height: 1)
                    }
                    promptRow(prompt)
                }
            }
            .padding(.horizontal, 16)
            .background(NoopPanelSurface(cornerRadius: 22))
        }
    }

    private func promptRow(_ prompt: String) -> some View {
        Button {
            onAsk(prompt)
        } label: {
            HStack(spacing: 10) {
                Text(prompt)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right")
                    .font(StrandFont.caption.weight(.semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 12)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Suggested question: \(prompt)"))
    }

    private func themeTitle(_ theme: CoachPrompts.Theme) -> LocalizedStringKey {
        switch theme {
        case .session: return "Session"
        case .recovery: return "Recovery and sleep"
        case .nutrition: return "Nutrition"
        }
    }

    private func themeSymbol(_ theme: CoachPrompts.Theme) -> String {
        switch theme {
        case .session: return "dumbbell.fill"
        case .recovery: return "moon.fill"
        case .nutrition: return "fork.knife"
        }
    }

    private func themeTint(_ theme: CoachPrompts.Theme) -> Color {
        switch theme {
        case .session: return StrandPalette.effortColor
        case .recovery: return StrandPalette.restBright
        case .nutrition: return StrandPalette.metricAmber
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onShowData) {
                HStack(spacing: 7) {
                    Image(systemName: "eye")
                        .accessibilityHidden(true)
                    Text("What the coach reads: profile, today, 14 days, Lift Log")
                        .multilineTextAlignment(.leading)
                    Image(systemName: "chevron.right")
                        .font(StrandFont.overline)
                        .accessibilityHidden(true)
                }
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .frame(minHeight: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Label {
                Text("Sent to \(providerName) only when you ask")
            } icon: {
                Image(systemName: "lock")
            }
            .font(StrandFont.footnote)
            .foregroundStyle(StrandPalette.textTertiary)
            .accessibilityElement(children: .combine)
        }
        .padding(.top, -4)
    }
}

/// A flow of chips that wraps onto the next line instead of scrolling sideways (personal fork, the
/// follow-ups under the last answer in Coach mockup 2). A sideways row fought the swipe between tabs.
struct CoachChipFlow: Layout {
    var spacing: CGFloat

    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let lines = chipLines(maxWidth: width, subviews: subviews)
        let height = lines.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(lines.count - 1, 0))
        let widest = lines.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in chipLines(maxWidth: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in line.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                let fitted = CGSize(width: min(size.width, bounds.width), height: size.height)
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                      proposal: ProposedViewSize(fitted))
                x += fitted.width + spacing
            }
            y += line.height + spacing
        }
    }

    /// One line of the flow: which subviews it holds, and how wide and tall it is.
    private struct ChipLine {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// Subviews in order, each moved to a new line once it would overflow `maxWidth`. A chip wider than
    /// the whole width gets a line of its own.
    private func chipLines(maxWidth: CGFloat, subviews: Subviews) -> [ChipLine] {
        var lines: [ChipLine] = []
        var current = ChipLine()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let chipWidth = min(size.width, maxWidth)
            let needed = current.indices.isEmpty ? chipWidth : current.width + spacing + chipWidth
            if needed > maxWidth, !current.indices.isEmpty {
                lines.append(current)
                current = ChipLine()
            }
            current.width = current.indices.isEmpty ? chipWidth : current.width + spacing + chipWidth
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { lines.append(current) }
        return lines
    }
}
