import XCTest
@testable import Strand

/// Personal fork: the Coach's suggested questions fitted to the day's data (`CoachSuggestions`). Pins the
/// rules: a figure only when it is today's, nothing about data that is not there, the fixed chips with
/// « Use my data » off, the most current question first, the meal photo last, and follow-ups the data can
/// answer. Expected texts are built with the same catalogue calls, so the tests hold in every language.
final class CoachSuggestionsTests: XCTestCase {

    private typealias Facts = CoachSuggestionFacts

    private func duration(_ minutes: Int) -> String { SleepDurationText.format(Double(minutes)) }
    private func percent(_ value: Int) -> String {
        (Double(value) / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    private func questions(_ facts: Facts) -> [String] {
        CoachSuggestions.personalizedQuickPrompts(facts).map(\.question)
    }

    private var hrvChip: String { CoachSuggestions.hrvQuestion }
    private var nextMeal: String { String(localized: "What should I eat at my next meal?") }
    private var createSession: String { String(localized: "Create a session for me for today") }
    private var lastSession: String { String(localized: "How did my last session go?") }

    // MARK: - Consent

    func testWithoutUseMyDataTheFixedChipsStay() {
        var facts = Facts(useData: false, photosAvailable: true, hour: 7)
        facts.nightMinutes = 370
        facts.charge = 38
        XCTAssertEqual(CoachSuggestions.personalizedQuickPrompts(facts), CoachPrompts.quickPrompts)
        facts.photosAvailable = false
        XCTAssertFalse(questions(facts).contains(CoachPrompts.photoMealPrompt))
        XCTAssertFalse(questions(facts).contains { $0.contains(duration(370)) })
    }

    // MARK: - Examples

    /// 7:30, the night synced, a debt, a Charge, a planned program, meals logged earlier in the week.
    func testAMorningWithFreshDataLeadsWithTheNightAndTheSession() {
        var facts = Facts(useData: true, photosAvailable: true, hour: 7)
        facts.nightMinutes = 370
        facts.debtMinutes = 80
        facts.charge = 38
        facts.session = .planned("Push A")
        facts.lastLiftDaysAgo = 2
        facts.mealDays7 = 3
        facts.hrvDays30 = 20
        XCTAssertEqual(questions(facts), [
            String(localized: "How was my night of \(duration(370))?"),
            String(localized: "Charge \(percent(38)): do I keep \("Push A")?"),
            String(localized: "How do I make up \(duration(80)) of sleep debt?"),
            nextMeal,
            lastSession,
            CoachPrompts.photoMealPrompt,
        ])
    }

    /// No sync since yesterday: today's row is absent, so neither the night nor the Charge is named.
    func testStaleDataNamesNoFigureOfToday() {
        var facts = Facts(useData: true, photosAvailable: true, hour: 9)
        facts.lastLiftDaysAgo = 3
        facts.hrvDays30 = 10
        let asked = questions(facts)
        XCTAssertEqual(asked, [lastSession, createSession, hrvChip, nextMeal, CoachPrompts.photoMealPrompt])
        XCTAssertFalse(asked.contains(String(localized: "How was my night?")))
    }

    /// 13:00, the session done this morning, two meals, protein left.
    func testMiddayAfterASessionAsksAboutItThenTheMeals() {
        var facts = Facts(useData: true, photosAvailable: false, hour: 13)
        facts.session = .done("Push A")
        facts.charge = 60
        facts.mealsToday = 2
        facts.proteinLeftG = 70
        let asked = questions(facts)
        XCTAssertEqual(Array(asked.prefix(3)), [
            String(localized: "How did my \("Push A") session go?"),
            String(localized: "What should I eat after my session?"),
            String(localized: "\(String(localized: "\(70) g")) of protein left: what should I eat?"),
        ])
        XCTAssertFalse(asked.contains(String(localized: "Charge \(percent(60)): can I train hard?")),
                       "the session is done: no « can I train hard »")
        XCTAssertFalse(asked.contains(CoachPrompts.photoMealPrompt))
    }

    func testTheEveningLeadsWithTheBedtime() {
        var facts = Facts(useData: true, photosAvailable: true, hour: 21)
        facts.bedtimeKnown = true
        facts.debtMinutes = 90
        facts.nightMinutes = 400
        let asked = questions(facts)
        XCTAssertEqual(asked.first, String(localized: "When should I go to bed tonight?"))
        XCTAssertEqual(asked[1], String(localized: "How do I make up \(duration(90)) of sleep debt?"))
        XCTAssertEqual(asked.last, CoachPrompts.photoMealPrompt)
    }

    func testAFastRunningNowComesFirst() {
        var facts = Facts(useData: true, photosAvailable: true, hour: 10)
        facts.fastingMinutes = 14 * 60 + 20
        facts.nightMinutes = 420
        XCTAssertEqual(questions(facts).first,
                       String(localized: "My fast is at \(duration(14 * 60 + 20)): how is it going?"))
    }

    // MARK: - Nothing without data

    func testNoProteinQuestionWithoutAMealToday() {
        var facts = Facts(useData: true, photosAvailable: true, hour: 12)
        facts.mealDays7 = 0
        facts.proteinLeftG = 50
        let asked = questions(facts)
        XCTAssertFalse(asked.contains(String(localized: "How much protein today?")))
        XCTAssertFalse(asked.contains { $0.contains(String(localized: "\(50) g")) })
    }

    func testNoHrvChipWithoutAWeekOfReadings() {
        var facts = Facts(useData: true, photosAvailable: true, hour: 12)
        facts.hrvDays30 = 6
        XCTAssertFalse(questions(facts).contains(hrvChip))
        facts.hrvDays30 = 7
        XCTAssertTrue(questions(facts).contains(hrvChip))
    }

    /// Below the normal band: said neutrally, and the trend chip gives way to it.
    func testAnHrvUnderTheNormalIsSaidNeutrally() {
        var facts = Facts(useData: true, photosAvailable: true, hour: 8)
        facts.hrvBelowNormal = true
        facts.hrvDays30 = 25
        let asked = questions(facts)
        XCTAssertTrue(asked.contains(String(localized: "My HRV is below my normal: what does it mean?")))
        XCTAssertFalse(asked.contains(hrvChip))
    }

    func testARestDayDoesNotAskToTrainHard() {
        var facts = Facts(useData: true, photosAvailable: true, hour: 8)
        facts.session = .rest
        facts.charge = 80
        let asked = questions(facts)
        XCTAssertTrue(asked.contains(String(localized: "Rest day: what should I do?")))
        XCTAssertFalse(asked.contains(String(localized: "Charge \(percent(80)): can I train hard?")))
    }

    func testAChargeWithNothingPlannedAsksWhetherToTrainHard() {
        var facts = Facts(useData: true, photosAvailable: true, hour: 8)
        facts.charge = 80
        XCTAssertTrue(questions(facts).contains(String(localized: "Charge \(percent(80)): can I train hard?")))
    }

    func testAtMostSixChipsAndThePhotoLast() {
        var facts = Facts(useData: true, photosAvailable: true, hour: 8)
        facts.fastingMinutes = 600
        facts.nightMinutes = 400
        facts.debtMinutes = 120
        facts.charge = 50
        facts.hrvBelowNormal = true
        facts.lastLiftDaysAgo = 1
        facts.mealsToday = 1
        facts.proteinLeftG = 90
        let asked = questions(facts)
        XCTAssertEqual(asked.count, CoachSuggestions.maxPrompts)
        XCTAssertEqual(asked.last, CoachPrompts.photoMealPrompt)
        XCTAssertEqual(Set(asked).count, asked.count)
    }

    func testTheLauncherListsTheChipsQuestions() {
        var facts = Facts(useData: true, photosAvailable: true, hour: 7)
        facts.nightMinutes = 370
        XCTAssertEqual(CoachSuggestions.launcherQuestions(facts), questions(facts))
    }

    // MARK: - Follow-ups

    func testAPersonalisedFirstQuestionKeepsItsTheme() {
        var facts = Facts(useData: true, photosAvailable: true, hour: 8)
        facts.session = .planned("Push A")
        let chips = CoachSuggestions.personalizedQuickPrompts(facts)
        let first = chips[0]
        XCTAssertEqual(first.theme, .session)
        let followUps = CoachPrompts.followUps(forFirstQuestion: first.question, lastReplyHasSession: false,
                                               startsWithBrief: false, facts: facts, known: chips)
        XCTAssertEqual(followUps.first, CoachPrompts.makeThisSession)
    }

    func testFollowUpsDropWhatTheDataCannotAnswer() {
        var facts = Facts(useData: true, photosAvailable: true, hour: 10)
        facts.bedtimeKnown = false
        facts.dataDays7 = 1
        let recovery = CoachPrompts.followUps(forFirstQuestion: CoachPrompts.Theme.recovery.prompts[0],
                                              lastReplyHasSession: false, startsWithBrief: false, facts: facts)
        XCTAssertFalse(recovery.contains(String(localized: "When should I go to bed tonight?")))
        XCTAssertGreaterThanOrEqual(recovery.count, 2)

        let generic = CoachPrompts.followUps(forFirstQuestion: "My knee hurts", lastReplyHasSession: false,
                                             startsWithBrief: false, facts: facts)
        XCTAssertFalse(generic.contains(String(localized: "Compare with my week")))
        XCTAssertGreaterThanOrEqual(generic.count, 2)

        let session = CoachPrompts.followUps(forFirstQuestion: nil, lastReplyHasSession: true,
                                             startsWithBrief: false, facts: facts)
        XCTAssertFalse(session.contains(String(localized: "What should I eat after?")), "no meal is ever logged")
    }

    func testTheBedtimeFollowUpComesFirstInTheEvening() {
        var facts = Facts(useData: true, photosAvailable: true, hour: 22)
        facts.bedtimeKnown = true
        let recovery = CoachPrompts.followUps(forFirstQuestion: CoachPrompts.Theme.recovery.prompts[0],
                                              lastReplyHasSession: false, startsWithBrief: false, facts: facts)
        XCTAssertEqual(recovery.first, String(localized: "When should I go to bed tonight?"))
    }

    func testFollowUpsStayAsTheyWereWithoutUseMyData() {
        let facts = Facts(useData: false, photosAvailable: true, hour: 22)
        for question in [nil, "My knee hurts", CoachPrompts.Theme.recovery.prompts[0]] {
            XCTAssertEqual(
                CoachPrompts.followUps(forFirstQuestion: question, lastReplyHasSession: false,
                                       startsWithBrief: false, facts: facts),
                CoachPrompts.followUps(forFirstQuestion: question, lastReplyHasSession: false,
                                       startsWithBrief: false))
        }
    }
}
