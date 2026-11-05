import SwiftUI
import StrandDesign

/// An action the Coach proposes, as a card under its reply (personal fork, chantier 8). Fork chantier 9
/// (Coach mockup): compact — its icon and title with an ⓘ that holds the explanation (it is the user's own
/// correction, not a measurement), the item on one line and what would change under it, then "Confirm".
/// Once confirmed the card offers "Undo"; once undone it says so. Nothing is written until the tap
/// (`AICoachEngine.confirmAction`).
struct CoachActionCard: View {
    let proposal: CoachActionProposal
    /// Running Confirm or Undo: the button waits.
    let busy: Bool
    let onConfirm: () -> Void
    let onUndo: () -> Void
    @State private var showsNote = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.accent)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                headerTitle
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer(minLength: 8)
                Button { showsNote = true } label: {
                    Image(systemName: "info.circle")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("About this card"))
                .popover(isPresented: $showsNote, arrowEdge: .top) {
                    note
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(NoopMetrics.cardInnerPadding)
                        .frame(width: 280, alignment: .leading)
                        .sleepGuidePopoverAdaptation()
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(proposal.lines.enumerated()), id: \.offset) { index, line in
                    Text(verbatim: line)
                        .font(index == 0 ? StrandFont.subhead : StrandFont.footnote)
                        .foregroundStyle(index == 0 ? StrandPalette.textPrimary : StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // Fork chantier 12: Confirm folds into « Done · Undo », the check bounces, a success haptic.
            actions
                .transition(.softCard(reduced: motion.poseStill(reduceMotion)))
                .animation(NoopMotion.gated(NoopMotion.card, reduced: motion.poseStill(reduceMotion)),
                           value: proposal.state)
                .strandHaptic(.success, trigger: proposal.state, when: { $0 == .applied })
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
        .accessibilityElement(children: .contain)
    }

    private var symbol: String {
        switch proposal.kind {
        case .nap: return "moon.zzz.fill"
        case .workout: return "figure.run"
        case .liftSets: return "dumbbell.fill"
        case .remember: return "brain.head.profile"
        }
    }

    private var headerTitle: Text {
        switch proposal.kind {
        case .nap: return Text("Proposed nap")
        case .workout: return Text("Workout correction")
        case .liftSets: return Text("Set correction")
        case .remember: return Text("To remember")
        }
    }

    private var note: Text {
        switch proposal.kind {
        case .nap: return Text("Added as a nap you entered, staged from your strap's data when there is some.")
        case .workout, .liftSets: return Text("Your correction, kept as entered by hand, not as a measurement.")
        case .remember: return Text("Added to “What the coach should know about you”, where you can change it.")
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch proposal.state {
        case .proposed:
            NoopButton("Confirm", systemImage: "checkmark", kind: .primary, fullWidth: true, action: onConfirm)
                .disabled(busy)
        case .applied:
            HStack(spacing: 8) {
                Label("Done", systemImage: "checkmark")
                    .noopSymbolBounce(proposal.state)
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                NoopButton("Undo", systemImage: "arrow.uturn.backward", kind: .secondary, fullWidth: true,
                           action: onUndo)
                    .disabled(busy)
                    .fixedSize(horizontal: true, vertical: false)
            }
        case .undone:
            Label("Undone", systemImage: "arrow.uturn.backward")
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(StrandPalette.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }
}
