import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - « End the fast at 12:30? » (personal fork, chantier 15 PR C)
//
// The sheet a screen shows once a meal saved during a fast left a proposal (`FastingMealLink`): Nutrition
// after its editor, add sheet or scanner closes, the Coach after a meal card is added, the Jeûne page on
// arrival. Every figure comes from the proposal and the fast's row; the end is written through
// `FastingLog`, the one resolver, so the ring, the card and the banner follow at once.

/// A pending proposal with the fast it is about, ready to show.
struct FastingMealQuestion: Identifiable, Equatable {
    let proposal: FastingMealProposal
    let fast: FastRow

    var id: String { FastingMealLink.dismissalMemo(proposal) }

    /// The question waiting, if any, checked against the store.
    static func pending(_ repo: Repository) async -> FastingMealQuestion? {
        guard let store = await repo.storeHandle(), let found = await FastingMealLink.resolvePending(store) else {
            return nil
        }
        return FastingMealQuestion(proposal: found.proposal, fast: found.fast)
    }

    /// « End at 12:30 »: write the end and forget the question.
    func end(_ repo: Repository) async {
        guard let store = await repo.storeHandle() else { return }
        await FastingMealLink.applyProposal(store, proposal, fast: fast)
    }

    /// « Keep fasting »: forget the question.
    func keep() {
        FastingMealLink.dismissProposal(proposal)
    }
}

struct FastingMealQuestionSheet: View {
    let question: FastingMealQuestion
    var now = Date()
    let onEnd: () -> Void
    let onKeep: () -> Void

    private var proposal: FastingMealProposal { question.proposal }
    private var fast: FastRow { question.fast }
    private var end: Date { Date(timeIntervalSince1970: TimeInterval(proposal.endSec)) }
    private var start: Date { Date(timeIntervalSince1970: TimeInterval(fast.startedAt)) }
    private var plannedEnd: Date { start.addingTimeInterval(TimeInterval(fast.goalMinutes * 60)) }
    private var recordedEnd: Date { Date(timeIntervalSince1970: TimeInterval(fast.endedAt ?? proposal.endSec)) }
    /// The fast's length with the meal's time as its end.
    private var elapsedMinutes: Int { max(0, (proposal.endSec - fast.startedAt) / 60) }

    private var title: String {
        switch proposal.kind {
        case .endRunning: return String(localized: "End the fast at \(FastingFormat.clock(end))?")
        case .moveEndBack: return String(localized: "Move the end of the fast to \(FastingFormat.clock(end))?")
        }
    }

    private var explanation: String {
        switch proposal.kind {
        case .endRunning:
            return String(localized: "You are logging “\(proposal.mealName)” at \(FastingFormat.dayAndClock(end, now: now)) while a \(FastingFormat.duration(minutes: fast.goalMinutes)) fast is running (planned end \(FastingFormat.dayAndClock(plannedEnd, now: now))). The meal is saved either way.")
        case .moveEndBack:
            return String(localized: "You are logging “\(proposal.mealName)” at \(FastingFormat.dayAndClock(end, now: now)), before the recorded end of your fast (\(FastingFormat.dayAndClock(recordedEnd, now: now))). The meal is saved either way.")
        }
    }

    private var endTitle: String {
        String(localized: "End at \(FastingFormat.clock(end)) · \(FastingFormat.duration(minutes: elapsedMinutes)) done")
    }

    private var keepTitle: String {
        switch proposal.kind {
        case .endRunning: return String(localized: "Keep fasting")
        case .moveEndBack: return String(localized: "Keep \(FastingFormat.clock(recordedEnd))")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(StrandPalette.fastingDone)
                    .frame(width: 36, height: 36)
                    .background(StrandPalette.fastingDone.opacity(0.18), in: Circle())
                Text(verbatim: title)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(verbatim: explanation)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onEnd) {
                Text(verbatim: endTitle)
                    .font(StrandFont.body.weight(.bold))
                    .foregroundStyle(StrandPalette.surfaceBase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(StrandPalette.fastingDone, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(LiquidPressStyle())
            FastingActionButton(title: Text(verbatim: keepTitle), look: .secondary, action: onKeep)
        }
        .padding(.horizontal, NoopMetrics.screenHPadding)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StrandPalette.surfaceBase.ignoresSafeArea())
        #if os(iOS)
        .presentationDetents([.height(330), .medium])
        .presentationDragIndicator(.visible)
        #endif
    }
}
