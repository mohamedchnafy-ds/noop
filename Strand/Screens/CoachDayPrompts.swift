import Foundation

// Personal fork: the Coach's suggested questions fitted to what is actually on the device, and how fresh
// it is. The chips above an empty conversation, the Today launcher's list and the follow-ups under an answer
// read the same facts (`CoachSuggestionFacts`, resolved by `AICoachEngine.suggestionFacts`).
//
// Rules, pinned by `CoachDayPromptsTests`:
// - A question names a figure only when that figure is today's and real: last night's sleep, today's Charge,
//   today's HRV against the personal normal, a fast running now, the protein left against today's goal. A
//   value carried from another day is never presented as today's; no data, no question about it.
// - The words stay neutral: « below my normal », never a diagnosis.
// - « Use my data » off: the fixed chips, as before. The Coach reads nothing then, and a question built
//   from the data would itself send a fact the user did not agree to share.
// - Nothing is read here that the Coach's own fiche does not already read, and nothing new leaves the
//   phone: a suggestion is sent only when the user taps it, like a typed question. Habits, the medical file,
//   the lab book and places never appear (the Coach raises habits only when asked).

/// What the suggestions may rely on: every field is today's, or nil when it is not.
struct CoachSuggestionFacts: Equatable {

    /// Today's session as the Synthèse resolves it (`TodaySessionResolver`).
    enum SessionFact: Equatable {
        case none
        /// A Lift Log program or planned cardio still to do today (its shown name).
        case planned(String)
        case running
        /// Done today (its shown name).
        case done(String)
        /// The week plan has no session today.
        case rest
    }

    /// « Use my data » is on: the Coach reads the data, so the questions may be built from it.
    var useData = false
    /// Photos can be sent (Anthropic): the meal-photo chip is offered.
    var photosAvailable = false
    /// The local hour (0–23).
    var hour = 12
    /// Last night's sleep, minutes, from today's row only.
    var nightMinutes: Int?
    /// The sleep debt, minutes, when the ledger counts a debt of an hour or more.
    var debtMinutes: Int?
    /// The suggested bedtime is known (usual wake minus the need).
    var bedtimeKnown = false
    /// Today's Charge, 0–100.
    var charge: Int?
    /// Today's own HRV reading sits under the personal normal band.
    var hrvBelowNormal = false
    /// Days with an HRV reading among the last 30.
    var hrvDays30 = 0
    /// Days with any reading among the last 7.
    var dataDays7 = 0
    var session: SessionFact = .none
    /// Days since the last finished Lift Log session, within the Coach's lookback.
    var lastLiftDaysAgo: Int?
    var mealsToday = 0
    /// Days with a meal among the 7 before today.
    var mealDays7 = 0
    /// Grams of protein left to today's goal, when a meal is logged and more than 10 g are left.
    var proteinLeftG: Int?
    /// Minutes of the fast running now.
    var fastingMinutes: Int?

    /// The user logs meals at all (today or in the week before).
    var logsMeals: Bool { mealsToday > 0 || mealDays7 > 0 }
}

enum CoachDayPrompts {

    /// Most chips above an empty conversation.
    static let maxPrompts = 6

    /// The chips above an empty conversation. « Use my data » off: the fixed chips. On: the questions the
    /// day's data supports, the most current first (what is running now, then the morning's figures, the
    /// day's meals, the trends), the meal photo last; topped up with questions that need no data.
    static func personalizedQuickPrompts(_ facts: CoachSuggestionFacts) -> [CoachPrompts.QuickPrompt] {
        let fixed = CoachPrompts.quickPrompts.filter { facts.photosAvailable || $0.question != CoachPrompts.photoMealPrompt }
        guard facts.useData else { return fixed }

        let morning = facts.hour >= 4 && facts.hour < 12
        let evening = facts.hour >= 18 || facts.hour < 4
        var ranked: [(rank: Int, prompt: CoachPrompts.QuickPrompt)] = []
        func add(_ rank: Int, _ question: String, _ theme: CoachPrompts.Theme?) {
            guard !ranked.contains(where: { $0.prompt.question == question }) else { return }
            ranked.append((rank, CoachPrompts.QuickPrompt(label: question, question: question, theme: theme)))
        }

        if let minutes = facts.fastingMinutes {
            add(10, String(localized: "My fast is at \(duration(minutes)): how is it going?"), .nutrition)
        }
        if evening && facts.bedtimeKnown {
            add(12, String(localized: "When should I go to bed tonight?"), .recovery)
        }

        var trainedOrResting = false
        switch facts.session {
        case .planned(let name):
            if let charge = facts.charge {
                add(morning ? 20 : 18, String(localized: "Charge \(percent(charge)): do I keep \(name)?"), .session)
            } else {
                add(20, String(localized: "Prepare my \(name) session"), .session)
            }
            trainedOrResting = true
        case .done(let name):
            add(morning ? 30 : 15, String(localized: "How did my \(name) session go?"), .session)
            if facts.logsMeals {
                add(morning ? 32 : 17, String(localized: "What should I eat after my session?"), .nutrition)
            }
            trainedOrResting = true
        case .rest:
            add(26, String(localized: "Rest day: what should I do?"), .recovery)
            trainedOrResting = true
        case .running:
            trainedOrResting = true
        case .none:
            add(60, String(localized: "Create a session for me for today"), .session)
        }
        if facts.session != .running, !isDone(facts.session), let days = facts.lastLiftDaysAgo, days <= 7 {
            add(55, String(localized: "How did my last session go?"), .session)
        }

        if let night = facts.nightMinutes {
            add(morning ? 14 : 45, String(localized: "How was my night of \(duration(night))?"), .recovery)
        }
        if let charge = facts.charge, !trainedOrResting {
            add(morning ? 16 : 40, String(localized: "Charge \(percent(charge)): can I train hard?"), .recovery)
        }
        if facts.hrvBelowNormal {
            add(morning ? 18 : 42, String(localized: "My HRV is below my normal: what does it mean?"), .recovery)
        }
        if let debt = facts.debtMinutes {
            add(evening ? 22 : 50, String(localized: "How do I make up \(duration(debt)) of sleep debt?"), .recovery)
        }

        if facts.mealsToday > 0 {
            if let left = facts.proteinLeftG {
                let grams = String(localized: "\(left) g")
                add(morning ? 52 : 28, String(localized: "\(grams) of protein left: what should I eat?"), .nutrition)
            } else {
                add(morning ? 52 : 30, String(localized: "How much protein today?"), .nutrition)
            }
        } else if facts.mealDays7 > 0 {
            add(morning ? 54 : 32, String(localized: "What should I eat at my next meal?"), .nutrition)
        }

        if !facts.hrvBelowNormal, facts.hrvDays30 >= 7, let hrv = fixed.first(where: { $0.question == hrvQuestion }) {
            ranked.append((70, hrv))
        }

        let photo = fixed.first { $0.question == CoachPrompts.photoMealPrompt }
        let room = maxPrompts - (photo == nil ? 0 : 1)
        var prompts = ranked.enumerated()
            .sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }
            .prefix(room).map { $0.element.prompt }
        // Too little data for a full row: questions that need none.
        for question in [String(localized: "Create a session for me for today"),
                         String(localized: "What should I eat at my next meal?")]
        where prompts.count < 4 && !prompts.contains(where: { $0.question == question }) {
            let theme: CoachPrompts.Theme = question == String(localized: "Create a session for me for today")
                ? .session : .nutrition
            prompts.append(CoachPrompts.QuickPrompt(label: question, question: question, theme: theme))
        }
        if let photo { prompts.append(photo) }
        return prompts
    }

    /// The questions the Today launcher lists: the chips' questions.
    static func launcherQuestions(_ facts: CoachSuggestionFacts) -> [String] {
        personalizedQuickPrompts(facts).map(\.question)
    }

    /// Follow-ups fitted to the device (« Use my data » on): none that the data cannot answer (the bedtime
    /// without a usual wake, a comparison with the week without three days of readings, what to eat after a
    /// session for someone who logs no meal), the bedtime first in the evening, and at least two.
    static func fittedFollowUps(_ followUps: [String], facts: CoachSuggestionFacts) -> [String] {
        guard facts.useData else { return followUps }
        let bedtime = String(localized: "When should I go to bed tonight?")
        let week = String(localized: "Compare with my week")
        let eatAfter = String(localized: "What should I eat after?")
        var kept = followUps.filter { prompt in
            if prompt == bedtime { return facts.bedtimeKnown }
            if prompt == week { return facts.dataDays7 >= 3 }
            if prompt == eatAfter { return facts.logsMeals }
            return true
        }
        let evening = facts.hour >= 18 || facts.hour < 4
        if evening, let index = kept.firstIndex(of: bedtime), index > 0 {
            kept.insert(kept.remove(at: index), at: 0)
        }
        for fallback in [String(localized: "Explain why"), String(localized: "What should I do today?")]
        where kept.count < 2 && !kept.contains(fallback) {
            kept.append(fallback)
        }
        return kept
    }

    // MARK: - Formatting

    /// The fixed HRV chip's question (`CoachPrompts.quickPrompts`).
    static var hrvQuestion: String { String(localized: "Show me my HRV over the last 30 days. Is it going down?") }

    private static func isDone(_ session: CoachSuggestionFacts.SessionFact) -> Bool {
        if case .done = session { return true }
        return false
    }

    /// « 6h 10m » in the app's language (the Sleep screen's format).
    private static func duration(_ minutes: Int) -> String {
        SleepDurationText.format(Double(minutes))
    }

    /// « 38% » / « 38 % » in the app's language.
    private static func percent(_ value: Int) -> String {
        (Double(value) / 100).formatted(.percent.precision(.fractionLength(0)))
    }
}
