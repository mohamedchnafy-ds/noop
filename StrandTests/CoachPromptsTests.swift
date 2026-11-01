import XCTest
@testable import Strand

/// The Coach suggestions and follow-ups (personal fork): two questions per theme, follow-ups chosen by
/// the theme of the conversation's first question, and generic ones otherwise.
final class CoachPromptsTests: XCTestCase {

    func testEveryThemeOffersTwoQuestionsAndThreeFollowUps() {
        for theme in CoachPrompts.Theme.allCases {
            XCTAssertEqual(theme.prompts.count, 2, "\(theme)")
            XCTAssertEqual(theme.followUps.count, 3, "\(theme)")
        }
        XCTAssertEqual(CoachPrompts.genericFollowUps.count, 3)
    }

    func testTheLauncherOffersEverySuggestionThemeByTheme() {
        XCTAssertEqual(CoachPrompts.suggestions, CoachPrompts.Theme.allCases.flatMap(\.prompts))
        XCTAssertEqual(Set(CoachPrompts.suggestions).count, CoachPrompts.suggestions.count,
                       "a question listed twice would belong to two themes")
    }

    func testTheThemeComesFromTheFirstQuestionWhenItIsASuggestion() {
        for theme in CoachPrompts.Theme.allCases {
            for prompt in theme.prompts {
                XCTAssertEqual(CoachPrompts.theme(ofFirstQuestion: prompt), theme)
                XCTAssertEqual(CoachPrompts.followUps(forFirstQuestion: prompt), theme.followUps)
            }
        }
    }

    func testATypedQuestionGetsTheGenericFollowUps() {
        XCTAssertNil(CoachPrompts.theme(ofFirstQuestion: "My knee hurts on squats"))
        XCTAssertEqual(CoachPrompts.followUps(forFirstQuestion: "My knee hurts on squats"),
                       CoachPrompts.genericFollowUps)
    }

    /// A brief alone has no question: generic follow-ups.
    func testNoFirstQuestionGetsTheGenericFollowUps() {
        XCTAssertNil(CoachPrompts.theme(ofFirstQuestion: nil))
        XCTAssertEqual(CoachPrompts.followUps(forFirstQuestion: nil), CoachPrompts.genericFollowUps)
    }

    /// Only an exact suggestion sets the theme; a question that merely starts like one does not.
    func testAnEditedSuggestionIsATypedQuestion() {
        let edited = CoachPrompts.Theme.session.prompts[0] + ", 45 min"
        XCTAssertNil(CoachPrompts.theme(ofFirstQuestion: edited))
    }
}

/// The reply's Redo action (personal fork): the last question is asked again in place of its answer,
/// and only when there is a question to ask. No network: the assertions are on the transcript before
/// the new turn could reach a provider, and the turn is stopped right away.
@MainActor
final class CoachRegenerateTests: XCTestCase {

    private func makeEngine() -> AICoachEngine {
        AICoachEngine(repo: Repository(deviceId: "test-coach-regenerate"))
    }

    func testRedoRemovesTheLastQuestionAndItsAnswerBeforeAskingAgain() {
        let engine = makeEngine()
        engine.messages = [ChatMessage(role: .user, text: "Q1"), ChatMessage(role: .assistant, text: "A1"),
                           ChatMessage(role: .user, text: "Q2"), ChatMessage(role: .assistant, text: "A2")]
        engine.regenerateLastReply()
        XCTAssertEqual(engine.messages.map(\.text), ["Q1", "A1"])
        engine.stopReply()
    }

    func testRedoDoesNothingWhileTheLastMessageIsAQuestion() {
        let engine = makeEngine()
        engine.messages = [ChatMessage(role: .user, text: "Q1"), ChatMessage(role: .assistant, text: "A1"),
                           ChatMessage(role: .user, text: "Q2")]
        engine.regenerateLastReply()
        XCTAssertEqual(engine.messages.map(\.text), ["Q1", "A1", "Q2"])
    }

    /// A brief on its own answers no question, so there is nothing to ask again.
    func testRedoDoesNothingForABriefAlone() {
        let engine = makeEngine()
        engine.messages = [ChatMessage(role: .assistant, text: AICoachEngine.briefPrefix + "Charge 66.")]
        engine.regenerateLastReply()
        XCTAssertEqual(engine.messages.count, 1)
    }

    func testRedoDoesNothingOnAnEmptyConversation() {
        let engine = makeEngine()
        engine.regenerateLastReply()
        XCTAssertTrue(engine.messages.isEmpty)
    }
}
