import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - A meal during a fast (personal fork, chantier 15 PR C)
//
// The meal editor and the add sheet save a new meal first, then ask `FastingLog.mealFastQuestion` whether
// it falls inside the newest fast. When it does, this small sheet asks « End the fast at 12:30? »: the
// green button moves the fast's real end to the meal's time (`FastingLog.endFastAtMeal`), the other one
// keeps the fast as it is. The meal stays in the journal either way.

/// The question card, in the page's own buttons. A pure view: the caller ends the fast.
struct FastingMealQuestionSheet: View {
    let question: FastingMealQuestion
    let now: Date
    let onEnd: () -> Void
    let onKeep: () -> Void

    private var mealClock: String { FastingFormat.clock(question.endAt) }
    private var goalText: String { FastingFormat.duration(minutes: question.fast.goalMinutes) }

    private var explanation: String {
        if let end = question.fast.endedAt {
            let endDate = Date(timeIntervalSince1970: TimeInterval(end))
            return String(localized: "You are logging a meal at \(mealClock), during your last fast (ended \(FastingFormat.dayAndClock(endDate, now: now))). The meal is saved either way.")
        }
        let planned = Date(timeIntervalSince1970: TimeInterval(question.fast.startedAt + question.fast.goalMinutes * 60))
        return String(localized: "You are logging a meal at \(mealClock) while a \(goalText) fast is running (planned end \(FastingFormat.dayAndClock(planned, now: now))). The meal is saved either way.")
    }

    private var keepTitle: Text {
        if let end = question.fast.endedAt {
            return Text("Keep the end at \(FastingFormat.clock(Date(timeIntervalSince1970: TimeInterval(end))))")
        }
        return Text("Keep fasting")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("End the fast at \(mealClock)?")
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textPrimary)
            Text(verbatim: explanation)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            FastingActionButton(title: Text("End at \(mealClock) · \(FastingFormat.duration(minutes: question.minutesAtEnd)) done"),
                                look: .done, action: onEnd)
            FastingActionButton(title: keepTitle, look: .secondary, action: onKeep)
        }
        .padding(.horizontal, NoopMetrics.screenHPadding)
        .padding(.top, 22)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StrandPalette.surfaceRaised.ignoresSafeArea())
        #if os(iOS)
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
        #else
        .frame(width: 420)
        #endif
    }
}

extension View {
    /// Presents the question of a meal logged during a fast while `question` is set; `onClosed` runs once
    /// it is answered or swiped away (the meal sheets then close themselves).
    func fastingMealQuestion(_ question: Binding<FastingMealQuestion?>, repo: Repository,
                             onClosed: @escaping () -> Void) -> some View {
        sheet(item: question, onDismiss: onClosed) { item in
            FastingMealQuestionSheet(
                question: item, now: Date(),
                onEnd: {
                    question.wrappedValue = nil
                    Task {
                        guard let store = await repo.storeHandle() else { return }
                        await FastingLog.endFastAtMeal(store, item)
                    }
                },
                onKeep: { question.wrappedValue = nil })
        }
    }
}
