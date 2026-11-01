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
                        String(localized: "What should I eat before my session?")]
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

    /// The follow-ups to offer under an answer.
    static func followUps(forFirstQuestion question: String?) -> [String] {
        theme(ofFirstQuestion: question)?.followUps ?? genericFollowUps
    }
}
