import Foundation
import WhoopStore

// MARK: - Meal estimate (personal fork, Nutrition)
//
// "Dictate" and "Photo" in Add a meal: one request outside any conversation. The model searches the
// Ciqual table and proposes the meal through `log_meal` (a packaged product through `read_label`); the
// proposal opens in the meal editor, where each quantity can change, a food can be removed or added, and
// only "Add to journal" saves it. Nothing goes to the Coach's history. Anthropic only (tools and photos),
// with the wearer's own key, like the Coach.

/// How a meal estimate ended.
enum MealEstimateOutcome: Equatable {
    /// The meal, ready for the editor.
    case proposal(CoachMealProposal)
    /// No food was found in what was said or shown: the model's own sentence.
    case noMeal(String)
    /// The request failed (key, network, cancelled): a message to show.
    case failure(String)
}

extension AICoachEngine {

    /// Rounds of tool calls before the last request forbids another: searching each food, then the meal.
    static let mealEstimateRounds = 6

    /// The estimate can run: the Coach is on, its provider is Anthropic (tools, photos) and has a key.
    var canEstimateMeals: Bool {
        CoachBriefScheduler.coachMasterEnabled && isConfigured && provider == .anthropic
    }

    /// The instructions of the estimate: find each food in Ciqual, then one `log_meal` (or `read_label`).
    nonisolated static func mealEstimateSystemPrompt(now: Date, languageName: String,
                                                     timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd' at 'HH:mm"
        return """
        You turn one meal into a nutrition journal entry. The user dictated or typed what they ate, sent \
        photos of it, or both.
        1. For each food, call search_foods (the Ciqual table, on the device) with a few plain words and pick \
        the closest row: raw or cooked, how it is prepared, its fat content.
        2. Then call log_meal once with every food: its Ciqual code and its quantity in grams. Use the \
        quantities the user gives. Otherwise estimate a usual portion and set estimated to true (always true \
        for a quantity read from a photo).
        3. If a photo shows the nutrition table of a packaged product, call read_label instead of log_meal and \
        copy the values for 100 g exactly as printed.
        Never state calories or macros yourself: the app computes them from the table. Name the meal and each \
        food in \(languageName), briefly. The meal was eaten now unless the user says when (it is \
        \(formatter.string(from: now))).
        If nothing in the message or the photos is food, answer in one short sentence in \(languageName) \
        without calling log_meal.
        """
    }

    /// The name of the app's language, in English, for the instructions ("French").
    nonisolated static func mealEstimateLanguageName(_ locale: Locale = .current) -> String {
        let code = locale.language.languageCode?.identifier ?? "fr"
        return Locale(identifier: "en_US_POSIX").localizedString(forLanguageCode: code) ?? "French"
    }

    /// Estimate the meal in `text` (dictated or typed) and `photos` (`CoachPhotoStore` names, staged), in one
    /// request outside the conversation. `origin` dates the journal line (voice, photo).
    func estimateMeal(text: String, photos: [String], origin: MealOrigin, now: Date = Date()) async -> MealEstimateOutcome {
        guard canEstimateMeals, let key = resolvedKey else {
            return .failure(AICoachError.noKey.errorDescription ?? "")
        }
        let jpegs = photos.prefix(CoachPhotoStore.maxPerQuestion).compactMap(CoachPhotoStore.jpegData(for:))
        var question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if question.isEmpty {
            guard !jpegs.isEmpty else { return .noMeal(String(localized: "Say or show what you ate.")) }
            question = "This is what I ate."
        }
        var conversation: [[String: Any]] = [jpegs.isEmpty
            ? AnthropicToolRequest.message(role: "user", text: question)
            : AnthropicToolRequest.userWithImages(text: question, jpegs: Array(jpegs))]
        let tools = [CoachMealProposal.searchDefinition, CoachMealProposal.logDefinition,
                     CoachMealProposal.labelDefinition]
        let system = Self.mealEstimateSystemPrompt(now: now, languageName: Self.mealEstimateLanguageName())
        var meal: CoachMealProposal?
        var lastText = ""
        do {
            for round in 0...Self.mealEstimateRounds {
                let allowTools = round < Self.mealEstimateRounds
                let body = try AnthropicToolRequest.body(model: model, system: system, messages: conversation,
                                                         tools: tools, allowTools: allowTools, maxTokens: 2048)
                let turn = try await streamToolRound(key: key, body: body) { _ in }
                lastText = turn.text
                let calls = turn.toolCalls
                guard allowTools, turn.stopReason == "tool_use", !calls.isEmpty else { break }
                var results: [(id: String, text: String, isError: Bool)] = []
                var settled = false
                for call in calls {
                    let input = CoachTools.input(fromJSON: call.inputJSON)
                    switch call.name {
                    case CoachMealProposal.searchToolName:
                        let query = CoachTools.text(input, "query") ?? ""
                        let limit = CoachTools.integer(input, "limit", fallback: 8, in: CoachMealProposal.searchLimitRange)
                        results.append((call.id, CoachMealProposal.searchResult(
                            query: query, foods: CiqualTable.search(query, limit: limit)), false))
                    case CoachMealProposal.logToolName:
                        let parsed = CoachMealProposal.fromToolInput(input, origin: origin, now: now,
                                                                     food: CiqualTable.food(code:))
                        if let proposal = parsed.proposal {
                            meal = proposal
                            settled = parsed.unknownCodes.isEmpty
                            results.append((call.id, CoachMealProposal.shownResult(unknownCodes: parsed.unknownCodes), false))
                        } else {
                            results.append((call.id, "No usable food: give each food by a Ciqual code from "
                                            + "search_foods and its quantity in grams.", true))
                        }
                    case CoachMealProposal.labelToolName:
                        let parsed = CoachMealProposal.fromLabelInput(input, questionBarcode: nil, now: now)
                        if var proposal = parsed.proposal {
                            proposal.origin = origin
                            meal = proposal
                            settled = true
                            results.append((call.id, CoachMealProposal.labelShownResult, false))
                        } else {
                            results.append((call.id, parsed.problem ?? "The label could not be read.", true))
                        }
                    default:
                        results.append((call.id, "Unknown tool \(call.name).", true))
                    }
                }
                // The meal is all this request is for: once it is proposed with every food found, stop.
                if settled { break }
                try Task.checkCancellation()
                conversation.append(AnthropicToolRequest.assistant(turn))
                conversation.append(AnthropicToolRequest.toolResults(results))
            }
        } catch {
            if Task.isCancelled || error is CancellationError { return .failure("") }
            return .failure((error as? AICoachError)?.errorDescription ?? error.localizedDescription)
        }
        if let meal { return .proposal(meal) }
        let said = lastText.trimmingCharacters(in: .whitespacesAndNewlines)
        return .noMeal(said.isEmpty ? String(localized: "No food was found. Try again with more detail.") : said)
    }
}
