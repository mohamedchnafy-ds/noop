import SwiftUI
import StrandDesign

/// A round header button face of the Coach screen (personal fork, Coach mockup 1): the history, a new
/// conversation and the ⋯ menu all share it, so the three read as one row. Fork chantier 7: only the
/// symbol; the caller wraps it in the Liquid Glass circle (`nativeLiquidGlassButtonChrome`), the same
/// chrome as the Today and Sleep header buttons.
struct CoachHeaderIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(StrandFont.headline)
            .foregroundStyle(StrandPalette.textPrimary)
            .frame(width: NoopMetrics.compactControlSize, height: NoopMetrics.compactControlSize)
            .contentShape(Circle())
    }
}

/// What an empty conversation shows (fork chantier 9, Coach mockup « Coach vide »): in the middle of the
/// screen the Coach's mark, « Hello Mohamed » (the first name typed in « What the coach should know about
/// you », « Hello » without one), one sentence and ONE white button, « Today's brief ». The suggested
/// questions are the six chips above the composer (`CoachQuickPrompts`); what the coach reads and when
/// anything is sent are in the ⋯ menu.
///
/// Nothing here sends on its own. The brief runs only when its button is tapped, through the callback the
/// screen hands in (`beginBriefIfNeeded` on the engine). Without "Use my data" the brief cannot read
/// anything, so the button says so and opens "What the coach reads", where the switch is.
struct CoachEmptyState: View {
    /// Whether the brief can run: it reads the wearer's data, so it needs "Use my data".
    let briefAvailable: Bool
    /// The first name to greet, empty for « Hello » alone.
    let firstName: String
    let onBrief: () -> Void
    let onShowData: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(StrandPalette.macroProtein)
                .accessibilityHidden(true)
            greeting
                .font(StrandFont.title2.weight(.bold))
                .foregroundStyle(StrandPalette.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("Ask me anything about your data.")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            briefButton
                .padding(.top, 6)
            if !briefAvailable {
                Text("Turn on “Use my data” first")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var greeting: some View {
        let name = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            Text("Hello")
        } else {
            Text("Hello \(name)")
        }
    }

    /// The white capsule with the brief's sun; without "Use my data", it opens what the coach reads.
    private var briefButton: some View {
        Button {
            if briefAvailable { onBrief() } else { onShowData() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(StrandPalette.metricAmber)
                    .accessibilityHidden(true)
                Text("Today's brief")
                    .foregroundStyle(StrandPalette.surfaceBase)
            }
            .font(StrandFont.headline)
            .padding(.horizontal, 22)
            .frame(minHeight: NoopButtonMetrics.height)
            .background(StrandPalette.textPrimary, in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(LiquidPressStyle())
        .accessibilityHint(briefAvailable ? Text("Generates today’s brief")
                                          : Text("Opens what the coach reads"))
    }
}

/// The six short questions above the composer of an empty conversation (fork chantier 9), wrapped rather
/// than scrolled sideways (a sideways row fought the swipe between tabs). They go as soon as the
/// conversation starts.
struct CoachQuickPrompts: View {
    let onAsk: (String) -> Void

    var body: some View {
        CoachChipFlow(spacing: 8) {
            ForEach(CoachPrompts.quickPrompts) { prompt in
                Button {
                    onAsk(prompt.question)
                } label: {
                    Text(verbatim: prompt.label)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 38)
                        .background(StrandPalette.surfaceRaised, in: Capsule(style: .continuous))
                        .overlay(Capsule(style: .continuous)
                            .strokeBorder(StrandPalette.hairline, lineWidth: NoopMetrics.hairlineWidth))
                }
                .buttonStyle(LiquidPressStyle())
                .accessibilityLabel(Text("Suggested question: \(prompt.label)"))
            }
        }
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
