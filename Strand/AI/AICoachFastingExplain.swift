import Foundation

// MARK: - A phase of the fast, explained for the wearer (personal fork, chantier 15)
//
// The phase sheet of the Jeûne page shows the app's own text first (`FastingPhaseText`, offline). Its
// « Ask the Coach for me » button sends ONE request outside any conversation, with the fast's figures,
// the day's water and the last meal, and shows the answer in a bubble. Nothing goes to the Coach's
// history; Anthropic only, with the wearer's own key, like the meal estimate. Sent only on that tap.

/// What the Coach is told about the fast. Plain text, already formatted by the screen, so the model and
/// the page say the same figures.
struct FastingCoachContext: Equatable {
    var phaseName: String
    var phaseRange: String
    var phaseStatus: String
    var elapsedText: String
    var goalText: String
    var remainingText: String
    var startText: String
    var plannedEndText: String
    var waterText: String
    var lastMealText: String?
}

/// How the explanation ended.
enum FastingExplainOutcome: Equatable {
    case answer(String)
    case failure(String)
}

extension AICoachEngine {

    /// The explanation can run: the Coach is on, its provider is Anthropic and has a key.
    var canExplainFasting: Bool { canEstimateMeals }

    /// The instructions: short, personal, prudent.
    nonisolated static func fastingExplainSystemPrompt(languageName: String) -> String {
        """
        You are the wearer's coach inside an offline health app. They are in an intermittent fast and tapped \
        one of its phases to understand it for themselves. Answer in \(languageName), in 3 to 5 short \
        sentences, second person, warm and concrete. Use the figures you are given (time fasted, time left, \
        water, last meal) and relate them to the phase; suggest one simple thing to do now (drink, a walk, \
        how to break the fast) when it helps. The phase landmarks are indicative, not measurements: say so \
        lightly if the wearer seems to expect precision. Never give medical advice, never mention diseases \
        or medication; past 24 hours of fasting, say a doctor should be asked. No headings, no lists, no \
        emoji.
        """
    }

    /// The message that carries the figures.
    nonisolated static func fastingExplainQuestion(_ context: FastingCoachContext) -> String {
        var lines = [
            "Phase tapped: \(context.phaseName) (\(context.phaseRange)) — \(context.phaseStatus).",
            "Fasted so far: \(context.elapsedText) of a \(context.goalText) goal; \(context.remainingText) left.",
            "Started \(context.startText); planned end \(context.plannedEndText).",
            "Water today: \(context.waterText).",
        ]
        if let meal = context.lastMealText { lines.append("Last meal: \(meal).") }
        lines.append("Explain this phase for me.")
        return lines.joined(separator: "\n")
    }

    /// Explain the phase in one request outside the conversation.
    func explainFastingPhase(_ context: FastingCoachContext) async -> FastingExplainOutcome {
        guard canExplainFasting, let key = resolvedKey else {
            return .failure(AICoachError.noKey.errorDescription ?? "")
        }
        let system = Self.fastingExplainSystemPrompt(languageName: Self.mealEstimateLanguageName())
        let messages = [AnthropicToolRequest.message(role: "user", text: Self.fastingExplainQuestion(context))]
        do {
            let body = try AnthropicToolRequest.body(model: model, system: system, messages: messages, tools: [],
                                                     allowTools: false, maxTokens: 1500)
            let turn = try await streamToolRound(key: key, body: body) { _ in }
            var said = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !said.isEmpty else { return .failure(String(localized: "The Coach did not answer. Try again.")) }
            // Cut by the token budget (it happened at 600 on the first IPA): say so rather than end mid-sentence.
            if turn.stopReason == "max_tokens" { said += "…" }
            return .answer(said)
        } catch {
            if Task.isCancelled || error is CancellationError { return .failure("") }
            return .failure((error as? AICoachError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
