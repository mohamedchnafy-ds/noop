import Foundation

/// The suggested questions offered when a Coach thread is empty (#1862), and the follow-ups offered
/// under an answer.
///
/// Shared by the Today launcher sheet and the full screen so both offer the SAME prompts. Personal fork:
/// grouped by theme (session, recovery and sleep, nutrition), as the Coach mockups show them, and every
/// string goes through the String Catalog. The follow-ups depend on the theme of the conversation's first
/// question when it is one of these prompts, and are generic otherwise.
enum CoachPrompts {

    enum Theme: String, CaseIterable, Identifiable {
        case session, recovery, nutrition
        var id: String { rawValue }

        var prompts: [String] {
            switch self {
            case .session:
                return [String(localized: "Create a session for me for today"),
                        String(localized: "How did my last session go?")]
            case .recovery:
                return [String(localized: "Can I train hard today?"),
                        String(localized: "How was my night?")]
            case .nutrition:
                return [String(localized: "How much protein today?"),
                        CoachPrompts.photoMealPrompt]
            }
        }

        var followUps: [String] {
            switch self {
            case .session:
                return [String(localized: "Make it shorter, 30 min"),
                        String(localized: "Swap one exercise"),
                        String(localized: "What should I eat after?")]
            case .recovery:
                return [String(localized: "When should I go to bed tonight?"),
                        String(localized: "Can I train hard tomorrow?"),
                        String(localized: "Explain why")]
            case .nutrition:
                return [String(localized: "Give me a meal example"),
                        String(localized: "And on rest days?"),
                        String(localized: "Explain why")]
            }
        }
    }

    /// Every suggested question, theme by theme.
    static var suggestions: [String] { Theme.allCases.flatMap(\.prompts) }

    /// One of the six short chips above the composer of an empty conversation (fork chantier 9, Coach
    /// mockup): its short label and the question it asks. The questions are the themes' own where one
    /// exists, so the follow-ups still recognise the conversation's theme.
    struct QuickPrompt: Equatable, Identifiable {
        let label: String
        let question: String
        /// The theme whose follow-ups the conversation gets when it starts with this question; nil keeps
        /// the generic ones. The fixed chips are recognised by `theme(ofFirstQuestion:)` already; the
        /// personalised ones (`CoachSuggestions`) carry theirs, since their text holds the day's figures.
        var theme: Theme? = nil
        var id: String { question }
    }

    /// The mockup's six chips, in its order. "Analyze my meal" opens the photo picker (`photoMealPrompt`).
    static var quickPrompts: [QuickPrompt] {
        [QuickPrompt(label: String(localized: "Can I train hard today?"),
                     question: String(localized: "Can I train hard today?")),
         QuickPrompt(label: String(localized: "My HRV over 30 days"),
                     question: String(localized: "Show me my HRV over the last 30 days. Is it going down?")),
         QuickPrompt(label: String(localized: "Protein left"),
                     question: String(localized: "How much protein today?")),
         QuickPrompt(label: String(localized: "Create a session for me"),
                     question: String(localized: "Create a session for me for today")),
         QuickPrompt(label: String(localized: "How was my night?"),
                     question: String(localized: "How was my night?")),
         QuickPrompt(label: String(localized: "Analyze my meal"),
                     question: photoMealPrompt)]
    }

    /// Follow-ups for an answer whose conversation has no known theme.
    static var genericFollowUps: [String] {
        [String(localized: "Explain why"),
         String(localized: "What should I do today?"),
         String(localized: "Compare with my week")]
    }

    /// The theme of a conversation whose first question is one of the suggested ones, else nil.
    static func theme(ofFirstQuestion question: String?) -> Theme? {
        guard let question else { return nil }
        return Theme.allCases.first { $0.prompts.contains(question) }
    }

    /// The suggestion that opens the photo picker instead of being asked as it stands (personal fork,
    /// Nutrition 4c); also the question a photo sent with no words asks.
    static var photoMealPrompt: String { String(localized: "Analyze my meal from a photo") }

    /// Under a meal card (Nutrition 4c): where the day stands now, and what comes next.
    static var mealFollowUps: [String] {
        [String(localized: "How much protein do I have left today?"),
         String(localized: "What should I eat at my next meal?"),
         String(localized: "Explain why")]
    }

    /// The follow-up that turns a session described in words into a session card (step 6b).
    static var makeThisSession: String { String(localized: "Make me this session") }

    /// The follow-ups to offer under the last answer. A reply that shows a session card gets the
    /// session's follow-ups (shorter, swap, what to eat after); a session question answered in words,
    /// or a conversation that starts with the brief, gets "Make me this session" first.
    ///
    /// With `facts` (the Coach screen, « Use my data » on), the follow-ups are then fitted to what is on the
    /// device (`CoachSuggestions.fittedFollowUps`); `known` holds the personalised chips on screen, so a
    /// conversation that started with one keeps its theme.
    static func followUps(forFirstQuestion question: String?, lastReplyHasSession: Bool,
                          startsWithBrief: Bool, lastReplyHasMeal: Bool = false,
                          facts: CoachSuggestionFacts? = nil, known: [QuickPrompt] = []) -> [String] {
        let plain = unfittedFollowUps(forFirstQuestion: question, lastReplyHasSession: lastReplyHasSession,
                                      startsWithBrief: startsWithBrief, lastReplyHasMeal: lastReplyHasMeal,
                                      known: known)
        guard let facts else { return plain }
        return CoachSuggestions.fittedFollowUps(plain, facts: facts)
    }

    private static func unfittedFollowUps(forFirstQuestion question: String?, lastReplyHasSession: Bool,
                                          startsWithBrief: Bool, lastReplyHasMeal: Bool,
                                          known: [QuickPrompt]) -> [String] {
        if lastReplyHasSession { return Theme.session.followUps }
        if lastReplyHasMeal { return mealFollowUps }
        let knownTheme = question.flatMap { q in known.first { $0.question == q }?.theme }
        switch knownTheme ?? theme(ofFirstQuestion: question) {
        case .session?:
            return [makeThisSession, String(localized: "Make it shorter, 30 min"),
                    String(localized: "What should I eat after?")]
        case let theme?:
            return theme.followUps
        case nil:
            guard startsWithBrief else { return genericFollowUps }
            return [makeThisSession, String(localized: "Explain why"), String(localized: "Compare with my week")]
        }
    }
}
