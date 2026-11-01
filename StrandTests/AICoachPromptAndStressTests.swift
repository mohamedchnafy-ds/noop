import XCTest
@testable import Strand
import WhoopProtocol
import StrandAnalytics

/// Covers the two small AI-Coach additions:
///   1. The built-in role and the user's extra instructions — persisted in UserDefaults under
///      `AICoachEngine.extraInstructionsKey`, read FRESH per request via `systemPrompt`, ADDED to the
///      role rather than replacing it (personal fork), with a Clear that removes them. Plus the one-time
///      default-model upgrade to Claude Sonnet 5.5.
///   2. The derived Baevsky Stress Index context line — its pure formatter (`stressIndexSummary`) and
///      that the line uses the SAME `StressIndex.stressIndex(rr:)` computation StressView does.
///
/// Both paths are UserDefaults / pure — no network, no Keychain — so they run headlessly.
@MainActor
final class AICoachPromptAndStressTests: XCTestCase {

    /// A fresh engine plus a clean slate: clear the key before and after so tests don't leak.
    private func makeEngine() -> AICoachEngine {
        UserDefaults.standard.removeObject(forKey: AICoachEngine.extraInstructionsKey)
        return AICoachEngine(repo: Repository(deviceId: "test-aicoach-prompt"))
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AICoachEngine.extraInstructionsKey)
        super.tearDown()
    }

    // MARK: - Feature 1: built-in role + extra instructions

    func testDefaultsToTheBuiltInRoleWhenNothingStored() {
        let engine = makeEngine()
        XCTAssertEqual(engine.systemPrompt, AICoachEngine.defaultSystemPrompt)
        XCTAssertFalse(engine.hasExtraInstructions)
    }

    func testTheRoleIsTheIntegratedCoachInstructions() {
        let role = AICoachEngine.defaultSystemPrompt
        XCTAssertTrue(role.hasPrefix("Tu es le coach sportif personnel de l'utilisateur"))
        // It names the blocks the context now carries, and no longer asks for a hand-filled profile.
        for block in ["USER PROFILE", "WHAT THE USER TOLD THE COACH", "TODAY", "YOUR NORMALS", "SLEEP",
                      "LIFT LOG", "LIFT PROGRESSION"] {
            XCTAssertTrue(role.contains(block), "the role explains \(block)")
        }
        XCTAssertFalse(role.contains("à compléter"))
        XCTAssertTrue(role.contains("ne t'appuie jamais dessus"), "the RPE rule stays")
    }

    func testExtraInstructionsAreAddedToTheRoleNotSwappedIn() {
        let engine = makeEngine()
        let extra = "Réponds toujours en moins de 3 phrases."
        engine.extraInstructions = extra

        XCTAssertEqual(UserDefaults.standard.string(forKey: AICoachEngine.extraInstructionsKey), extra)
        XCTAssertTrue(engine.systemPrompt.hasPrefix(AICoachEngine.defaultSystemPrompt))
        XCTAssertTrue(engine.systemPrompt.contains("## Consignes de l'utilisateur"))
        XCTAssertTrue(engine.systemPrompt.hasSuffix(extra))
        XCTAssertTrue(engine.hasExtraInstructions)

        // Read fresh per send: a write straight to UserDefaults is picked up by the next read.
        UserDefaults.standard.set("Autre consigne.", forKey: AICoachEngine.extraInstructionsKey)
        XCTAssertTrue(engine.systemPrompt.hasSuffix("Autre consigne."))
    }

    func testClearRemovesTheExtraInstructions() {
        let engine = makeEngine()
        engine.extraInstructions = "Une consigne."
        engine.clearExtraInstructions()
        XCTAssertNil(UserDefaults.standard.string(forKey: AICoachEngine.extraInstructionsKey))
        XCTAssertEqual(engine.systemPrompt, AICoachEngine.defaultSystemPrompt)
        XCTAssertFalse(engine.hasExtraInstructions)
    }

    func testBlankExtraInstructionsClearTheKey() {
        let engine = makeEngine()
        engine.extraInstructions = "   \n  "
        XCTAssertNil(UserDefaults.standard.string(forKey: AICoachEngine.extraInstructionsKey))
        XCTAssertEqual(engine.systemPrompt, AICoachEngine.defaultSystemPrompt)
    }

    func testComposeSystemPromptTrimsAndSkipsBlank() {
        XCTAssertEqual(AICoachEngine.composeSystemPrompt(role: "R", extra: nil), "R")
        XCTAssertEqual(AICoachEngine.composeSystemPrompt(role: "R", extra: " \n "), "R")
        let composed = AICoachEngine.composeSystemPrompt(role: "R", extra: "  X  ")
        XCTAssertTrue(composed.hasPrefix("R\n\n## Consignes de l'utilisateur\n"))
        XCTAssertTrue(composed.hasSuffix("\nX"))
    }

    // MARK: - Default model

    func testTheAnthropicDefaultIsSonnet55() {
        XCTAssertEqual(AIProvider.anthropic.defaultModel, "claude-sonnet-5-5")
        XCTAssertEqual(AIProvider.anthropic.modelOptions.first, "claude-sonnet-5-5")
    }

    func testOnlyThePreviousDefaultIsUpgradedAndOnlyOnce() {
        XCTAssertEqual(AICoachEngine.upgradedModel(provider: .anthropic, stored: "claude-sonnet-4-6",
                                                   alreadyUpgraded: false), "claude-sonnet-5-5")
        XCTAssertNil(AICoachEngine.upgradedModel(provider: .anthropic, stored: "claude-sonnet-4-6",
                                                 alreadyUpgraded: true), "a later manual pick is kept")
        XCTAssertNil(AICoachEngine.upgradedModel(provider: .anthropic, stored: "claude-opus-4-8",
                                                 alreadyUpgraded: false), "a chosen model is kept")
        XCTAssertNil(AICoachEngine.upgradedModel(provider: .anthropic, stored: nil, alreadyUpgraded: false))
        XCTAssertNil(AICoachEngine.upgradedModel(provider: .openAI, stored: "claude-sonnet-4-6",
                                                 alreadyUpgraded: false))
    }

    // MARK: - Feature 2: derived stress line

    func testStressIndexSummaryFormatsOneRoundedNumber() {
        // The line carries exactly the rounded SI plus the labelled proxy note — a derived summary.
        let line = AICoachEngine.stressIndexSummary(si: 223.82920110192836)
        XCTAssertTrue(line.hasPrefix("Stress (SI): 224 "), "rounds and labels the SI: \(line)")
        XCTAssertTrue(line.contains("Baevsky Stress Index"))
        // No raw R-R reading leaks into the summary — it's a single derived number only.
        XCTAssertFalse(line.contains("700"))
        XCTAssertFalse(line.contains("ms"), "no raw R-R values in the summary line")
    }

    func testSummaryNumberMatchesStressViewComputation() {
        // The SAME 22-beat golden series StressIndexTests pins (SI ≈ 223.83 → rounds to 224). The coach
        // line must report the value `StressIndex.stressIndex(rr:)` produces — the exact StressView path.
        let raw: [Double] = [700, 720, 740, 760, 780, 800, 820, 840, 860, 800, 800,
                             800, 800, 820, 780, 800, 810, 790, 800, 800, 805, 795]
        let rr = raw.enumerated().map { RRInterval(ts: 1000 + $0.offset, rrMs: Int($0.element)) }
        let si = StressIndex.stressIndex(rr: rr)
        XCTAssertNotNil(si)
        let expected = "Stress (SI): \(Int(si!.rounded())) "
        XCTAssertTrue(AICoachEngine.stressIndexSummary(si: si!).hasPrefix(expected))
    }
}
