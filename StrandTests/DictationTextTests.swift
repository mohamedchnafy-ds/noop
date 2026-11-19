import XCTest
@testable import Strand

/// Personal fork: the dictation in the Coach's composer and in Nutrition's "Dictate a meal". Pins the two
/// pure halves that every recognizer result goes through (`DictationTranscript`, `DictationDraft`), against
/// the reported failures: text vanishing while dictating (sometimes for good) and passages coming out twice.
/// Both screens drive the same two steps as `Dictation` below: a draft started from the field, every result
/// folded into the session's transcript, the transcript merged into the field, and Stop merging it once more.
final class DictationTextTests: XCTestCase {

    private typealias R = DictationTranscript.Recognition

    /// One dictation as a screen runs it: the field, the session's transcript and the draft.
    private struct Dictation {
        var field: String
        var transcript = DictationTranscript()
        var draft: DictationDraft

        init(field: String) {
            self.field = field
            draft = DictationDraft(startingFrom: field)
        }

        /// A recognizer result reaching the screen (`partial`).
        mutating func hear(_ result: R) {
            transcript.ingestRecognition(result)
            field = draft.mergeDictation(spoken: transcript.spokenText, into: field)
        }

        mutating func hear(_ text: String, ended: Bool = false, final: Bool = false) {
            hear(R(text: text, utteranceEnded: ended, isFinal: final))
        }

        /// Stop's completion: the session's whole text, merged once more.
        mutating func stop() {
            field = draft.mergeDictation(spoken: transcript.spokenText, into: field)
        }
    }

    // MARK: - The transcript

    func testRevisionsOfOneUtteranceReplaceEachOther() {
        var t = DictationTranscript()
        for partial in ["je", "je mange", "j'ai mangé", "j'ai mangé une pomme"] {
            t.ingestRecognition(R(text: partial))
        }
        XCTAssertEqual(t.spokenText, "j'ai mangé une pomme")
    }

    func testWordsBeforeAPauseStayWhenTheRecognizerStartsANewUtterance() {
        // The on-device recognizer marks the end of an utterance, then reports only the new words.
        var t = DictationTranscript()
        t.ingestRecognition(R(text: "Est-ce que je peux"))
        t.ingestRecognition(R(text: "Est-ce que je peux m'entraîner", utteranceEnded: true))
        t.ingestRecognition(R(text: "fort"))
        t.ingestRecognition(R(text: "fort aujourd'hui"))
        XCTAssertEqual(t.spokenText, "Est-ce que je peux m'entraîner fort aujourd'hui")
    }

    func testANewUtteranceWithoutTheEndMarkIsStillKeptApart() {
        // No metadata: the text alone shows a restart (shorter, nothing in common with the start).
        var t = DictationTranscript()
        t.ingestRecognition(R(text: "comment était ma nuit"))
        t.ingestRecognition(R(text: "et"))
        t.ingestRecognition(R(text: "et ma VFC"))
        XCTAssertEqual(t.spokenText, "comment était ma nuit et ma VFC")
    }

    func testARunningTranscriptAfterTheEndMarkIsNotDuplicated() {
        // A recognizer that keeps a running transcript across the pause repeats the closed utterance.
        var t = DictationTranscript()
        t.ingestRecognition(R(text: "deux œufs", utteranceEnded: true))
        t.ingestRecognition(R(text: "deux œufs et du pain"))
        XCTAssertEqual(t.spokenText, "deux œufs et du pain")
        t.ingestRecognition(R(text: "deux œufs", utteranceEnded: true))
        t.ingestRecognition(R(text: "deux œufs", isFinal: true))
        XCTAssertEqual(t.spokenText, "deux œufs")
    }

    func testARepetitionReallySaidAfterAPauseIsKept() {
        var t = DictationTranscript()
        t.ingestRecognition(R(text: "très bon", utteranceEnded: true))
        t.ingestRecognition(R(text: "très"))
        t.ingestRecognition(R(text: "très bon"))
        XCTAssertEqual(t.spokenText, "très bon très bon")
    }

    func testARepetitionWithinAnUtteranceIsKept() {
        var t = DictationTranscript()
        t.ingestRecognition(R(text: "très"))
        t.ingestRecognition(R(text: "très très"))
        t.ingestRecognition(R(text: "très très bon"))
        XCTAssertEqual(t.spokenText, "très très bon")
    }

    func testARepetitionThatStartsAfterTheClosedUtteranceIsKeptEvenInOneResult() {
        // Word times, when the recognizer gives them, settle the ambiguous case: it started later.
        var t = DictationTranscript()
        t.ingestRecognition(R(text: "un café", utteranceEnded: true, firstWordStart: 0.4, lastWordEnd: 1.2))
        t.ingestRecognition(R(text: "un café", firstWordStart: 2.5, lastWordEnd: 3.1))
        XCTAssertEqual(t.spokenText, "un café un café")
    }

    func testWordTimesShowARestartWithoutTheEndMark() {
        var t = DictationTranscript()
        t.ingestRecognition(R(text: "ma nuit", firstWordStart: 0.3, lastWordEnd: 1.0))
        t.ingestRecognition(R(text: "ma séance", firstWordStart: 2.0, lastWordEnd: 2.8))
        XCTAssertEqual(t.spokenText, "ma nuit ma séance")
    }

    func testAnEmptyResultNeverWipesWhatWasHeard() {
        var t = DictationTranscript()
        t.ingestRecognition(R(text: "un yaourt"))
        t.ingestRecognition(R(text: "   "))
        t.ingestRecognition(R(text: "", isFinal: true))
        XCTAssertEqual(t.spokenText, "un yaourt")
    }

    func testAFinalResultHoldingOnlyTheLastUtteranceKeepsTheEarlierOnes() {
        var t = DictationTranscript()
        t.ingestRecognition(R(text: "150 g de riz", utteranceEnded: true))
        t.ingestRecognition(R(text: "un blanc"))
        t.ingestRecognition(R(text: "un blanc de poulet", isFinal: true))
        XCTAssertEqual(t.spokenText, "150 g de riz un blanc de poulet")
    }

    func testANumberRewrittenInDigitsIsARevisionNotARestart() {
        var t = DictationTranscript()
        t.ingestRecognition(R(text: "deux cents grammes de riz"))
        t.ingestRecognition(R(text: "200 g de riz"))
        XCTAssertEqual(t.spokenText, "200 g de riz")
    }

    func testAShorterRevisionThatKeepsTheStartIsNotARestart() {
        var t = DictationTranscript()
        t.ingestRecognition(R(text: "j'ai mangé une pomme verte"))
        t.ingestRecognition(R(text: "J'ai mangé une pomme"))
        XCTAssertEqual(t.spokenText, "J'ai mangé une pomme")
    }

    // MARK: - Coach: the composer

    func testCoachKeepsTheTypedQuestionAndAddsTheDictatedWordsAfterIt() {
        var d = Dictation(field: "Analyse ma semaine,")
        d.hear("surtout")
        d.hear("surtout le sommeil")
        XCTAssertEqual(d.field, "Analyse ma semaine, surtout le sommeil")
    }

    func testCoachStopDoesNotWriteTheDictatedPassageTwice() {
        // The bug: the final text was appended to a draft that already held the partial.
        var d = Dictation(field: "")
        d.hear("Comment était ma nuit")
        d.hear("Comment était ma nuit ?", final: true)
        d.stop()
        XCTAssertEqual(d.field, "Comment était ma nuit ?")
    }

    func testCoachKeepsAManualCorrectionMadeWhileListening() {
        var d = Dictation(field: "")
        d.hear("ma VFC sur trente jours")
        d.field = "Ma VFC sur 30 jours"          // corrected by hand, still listening
        d.hear("ma VFC sur trente jours elle baisse")
        d.hear("ma VFC sur trente jours elle baisse ?", final: true)
        d.stop()
        XCTAssertEqual(d.field, "Ma VFC sur 30 jours elle baisse ?")
    }

    func testCoachTextClearedWhileListeningDoesNotComeBack() {
        var d = Dictation(field: "")
        d.hear("bonjour coach")
        d.field = ""
        d.hear("bonjour coach")
        XCTAssertEqual(d.field, "")
        d.hear("bonjour coach ma nuit")
        XCTAssertEqual(d.field, "ma nuit")
    }

    func testCoachResumingAfterStopAddsToTheFirstDictation() {
        var first = Dictation(field: "")
        first.hear("Crée-moi une séance")
        first.stop()
        var second = Dictation(field: first.field + " pour aujourd'hui,")
        second.hear("30 minutes")
        second.stop()
        XCTAssertEqual(second.field, "Crée-moi une séance pour aujourd'hui, 30 minutes")
    }

    func testCoachInterruptionKeepsWhatWasAlreadyWritten() {
        // A call or Siri ends the session with no final result: the field keeps the last partial.
        var d = Dictation(field: "Peux-tu")
        d.hear("regarder ma charge")
        XCTAssertEqual(d.field, "Peux-tu regarder ma charge")
    }

    func testCoachPauseInTheMiddleOfAQuestionKeepsBothHalves() {
        var d = Dictation(field: "")
        d.hear("Combien de protéines", ended: true)
        XCTAssertEqual(d.field, "Combien de protéines")
        d.hear("il me reste")
        d.hear("il me reste aujourd'hui")
        d.stop()
        XCTAssertEqual(d.field, "Combien de protéines il me reste aujourd'hui")
    }

    func testCoachTextEndingWithANewLineGetsNoExtraSpace() {
        var d = Dictation(field: "Première ligne\n")
        d.hear("deuxième")
        XCTAssertEqual(d.field, "Première ligne\ndeuxième")
    }

    // MARK: - Nutrition: Dictate a meal

    func testNutritionStopKeepsTheTextAlreadyThere() {
        // The bug: Stop replaced the whole text with the last session's words.
        var d = Dictation(field: "150 g de riz")
        d.hear("et un yaourt")
        d.hear("et un yaourt nature", final: true)
        d.stop()
        XCTAssertEqual(d.field, "150 g de riz et un yaourt nature")
    }

    func testNutritionTwoDictationsInARowKeepBoth() {
        var first = Dictation(field: "")
        first.hear("deux œufs")
        first.stop()
        var second = Dictation(field: first.field)
        second.hear("une tranche de pain")
        second.stop()
        XCTAssertEqual(second.field, "deux œufs une tranche de pain")
    }

    func testNutritionPauseBetweenFoodsKeepsEveryFood() {
        var d = Dictation(field: "")
        d.hear("deux œufs", ended: true)
        d.hear("et")
        d.hear("et du pain", ended: true)
        d.hear("un café")
        d.hear("un café", final: true)
        d.stop()
        XCTAssertEqual(d.field, "deux œufs et du pain un café")
    }

    func testNutritionFoodSaidTwiceStaysTwice() {
        var d = Dictation(field: "")
        d.hear("un œuf", ended: true)
        d.hear("un")
        d.hear("un œuf")
        d.stop()
        XCTAssertEqual(d.field, "un œuf un œuf")
    }

    func testNutritionTextEditedBetweenTwoDictationsIsKept() {
        var first = Dictation(field: "")
        first.hear("cent grammes de pâtes")
        first.stop()
        let corrected = "100 g de pâtes complètes"   // edited by hand once listening stopped
        var second = Dictation(field: corrected)
        second.hear("avec du parmesan")
        second.stop()
        XCTAssertEqual(second.field, "100 g de pâtes complètes avec du parmesan")
    }

    // MARK: - Helpers

    func testAppendDictatedKeepsTheTextAsItIs() {
        XCTAssertEqual(appendDictated("b", to: ""), "b")
        XCTAssertEqual(appendDictated("", to: "a  "), "a  ")
        XCTAssertEqual(appendDictated("b", to: "a "), "a b")
        XCTAssertEqual(appendDictated("b", to: "a"), "a b")
    }

    func testNormalizedWordsIgnoreCaseAccentsAndPunctuation() {
        XCTAssertEqual(normalizedDictationWord("Été,"), "ete")
        XCTAssertTrue(sameDictatedWord("deux", "2"))
        XCTAssertFalse(sameDictatedWord("deux", "et"))
    }
}
