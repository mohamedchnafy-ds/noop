import XCTest
@testable import Strand

/// Twin of the Android `TodayLayoutPrefsTest` (#today-layout): default order, encode/decode round-trip,
/// reorder, and the never-hide "insert missing section at its default position" invariant — pinned on both
/// platforms so the byte-identical "today.sectionOrder" wire format can't drift.
final class TodayLayoutPrefsTests: XCTestCase {

    func testEmptyOrUnsetYieldsDefaultOrder() {
        XCTAssertEqual(TodayLayoutPrefs.decodeOrder(""), TodaySection.defaultOrder)
        XCTAssertEqual(TodayLayoutPrefs.decodeOrder("   "), TodaySection.defaultOrder)
    }

    func testEncodeDecodeRoundTripsAReorderedList() {
        let reordered: [TodaySection] = [
            .heartRate, .hero, .yourCards, .liveSession, .synthesis, .keyMetrics, .workouts, .recoveryVitals,
            .journal, .menstrualCycle, .addedCards, .stress,
        ]
        let encoded = TodayLayoutPrefs.encode(reordered)
        XCTAssertEqual(encoded, "heartRate,hero,yourCards,liveSession,synthesis,keyMetrics,workouts,recoveryVitals,journal,menstrualCycle,addedCards,stress")
        XCTAssertEqual(TodayLayoutPrefs.decodeOrder(encoded), reordered)
    }

    /// The v1 upgrade path: an order saved by the FIRST cut (6 sections — no hero/liveSession, which were
    /// pinned then) must surface the two new sections at the TOP (their default position), not teleport
    /// them to the bottom of the user's saved order.
    func testSavedOrderFromFirstCutInsertsHeroAndSessionAtTheirDefaultPosition() {
        let firstCut = "synthesis,keyMetrics,workouts,heartRate,recoveryVitals,yourCards"
        XCTAssertEqual(
            TodayLayoutPrefs.decodeOrder(firstCut),
            // journal(8) follows everything saved → appended; addedCards(10) is last, appended after it.
            [.hero, .liveSession, .synthesis, .keyMetrics, .workouts, .heartRate, .recoveryVitals, .yourCards, .menstrualCycle, .journal, .addedCards, .stress]
        )
    }

    func testInsertsAnyMissingSectionAtItsDefaultPositionRelativeToSaved() {
        let partial = "heartRate,synthesis,keyMetrics,recoveryVitals"
        XCTAssertEqual(
            TodayLayoutPrefs.decodeOrder(partial),
            [.hero, .liveSession, .workouts, .heartRate, .synthesis, .keyMetrics, .recoveryVitals, .yourCards, .menstrualCycle, .journal, .addedCards, .stress]
        )
    }

    func testDropsUnknownTokensAndCollapsesDuplicates() {
        let messy = "yourCards,BOGUS,yourCards,heartRate, ,heartRate"
        XCTAssertEqual(
            TodayLayoutPrefs.decodeOrder(messy),
            [.hero, .liveSession, .synthesis, .keyMetrics, .workouts, .recoveryVitals, .yourCards, .heartRate, .menstrualCycle, .journal, .addedCards, .stress]
        )
    }

    func testAllJunkYieldsDefaultOrder() {
        XCTAssertEqual(TodayLayoutPrefs.decodeOrder("nope,,zzz"), TodaySection.defaultOrder)
    }

    func testHiddenSectionsAreExplicitReversibleAndDeduplicated() {
        let hidden = TodayLayoutPrefs.decodeHidden("workouts,BOGUS,workouts,journal")
        XCTAssertEqual(hidden, [.workouts, .journal])
        XCTAssertEqual(TodayLayoutPrefs.encodeHidden(hidden), "workouts,journal")
    }

    func testVisibleOrderFiltersHiddenWithoutChangingSavedOrder() {
        let order = "heartRate,hero,yourCards,liveSession,synthesis,keyMetrics,workouts,recoveryVitals,journal"
        XCTAssertEqual(
            TodayLayoutPrefs.visibleOrder(orderRaw: order, hiddenRaw: "hero,workouts"),
            [.heartRate, .yourCards, .liveSession, .synthesis, .keyMetrics, .recoveryVitals, .menstrualCycle, .journal, .addedCards, .stress]
        )
        XCTAssertEqual(TodayLayoutPrefs.decodeOrder(order), [
            .heartRate, .hero, .yourCards, .liveSession, .synthesis, .keyMetrics, .workouts,
            .recoveryVitals, .menstrualCycle, .journal, .addedCards, .stress,
        ])
    }

    func testNewOrPreviouslyMissingSectionsDefaultToVisible() {
        XCTAssertTrue(
            TodayLayoutPrefs.visibleOrder(
                orderRaw: "synthesis,keyMetrics,workouts,heartRate,recoveryVitals,yourCards",
                hiddenRaw: "workouts"
            ).contains(.journal)
        )
    }

    /// defaultOrder must cover EVERY case: the never-hide merge iterates it, so a case missing from the
    /// default order could otherwise be dropped from render (Android) or mis-sorted (iOS).
    func testDefaultOrderCoversEveryCase() {
        XCTAssertEqual(Set(TodaySection.defaultOrder), Set(TodaySection.allCases))
        XCTAssertEqual(TodaySection.defaultOrder.count, TodaySection.allCases.count)
    }

    func testSectionRawKeysAreStableAndUnique() {
        let raws = TodaySection.allCases.map(\.rawValue)
        XCTAssertEqual(raws.count, Set(raws).count, "raw keys must be unique (they're the persisted identity)")
        // Pin the exact wire strings — they must match the Android TodaySection byte-for-byte.
        XCTAssertEqual(
            raws,
            ["hero", "liveSession", "synthesis", "keyMetrics", "workouts", "heartRate", "recoveryVitals", "yourCards", "menstrualCycle", "journal", "addedCards", "stress"]
        )
    }

    func testEditableLayoutHidesAndRestoresWithoutDeleting() {
        var draft = EditableLayoutDraft(
            visible: TodaySection.defaultOrder,
            allItems: TodaySection.defaultOrder
        )

        draft.hide(.workouts)
        XCTAssertFalse(draft.visible.contains(.workouts))
        XCTAssertEqual(draft.hidden, [.workouts])

        draft.show(.workouts)
        XCTAssertEqual(draft.visible.last, .workouts)
        XCTAssertTrue(draft.hidden.isEmpty)
        XCTAssertEqual(Set(draft.visible), Set(TodaySection.defaultOrder))
    }

    // MARK: Chantier 9 (personal fork)

    func testLayoutV3PutsTheFivePageSectionsFirstAndKeepsEveryToken() {
        let moved = TodayLayoutPrefs.decodeOrder(TodayLayoutPrefs.liquidV3Order(""))
        XCTAssertEqual(Array(moved.prefix(5)), [.hero, .synthesis, .heartRate, .stress, .keyMetrics])
        // A v2 order (heart rate then synthesis under the hero) keeps the rest in its relative order.
        let v2 = "hero,heartRate,synthesis,liveSession,keyMetrics,workouts,recoveryVitals,yourCards,journal"
        let movedV2 = TodayLayoutPrefs.decodeOrder(TodayLayoutPrefs.liquidV3Order(v2))
        XCTAssertEqual(movedV2, [.hero, .synthesis, .heartRate, .stress, .keyMetrics, .liveSession, .workouts,
                                 .recoveryVitals, .yourCards, .menstrualCycle, .journal, .addedCards])
        XCTAssertEqual(Set(movedV2), Set(TodaySection.allCases))
    }

    func testLiquidOrderLeavesTheMovedSectionsOutButKeepsThemStored() {
        let raw = TodayLayoutPrefs.liquidV3Order("")
        XCTAssertTrue(raw.contains("liveSession") && raw.contains("workouts"))
        let visible = TodayLayoutPrefs.liquidVisibleOrder(orderRaw: raw, hiddenRaw: "")
        XCTAssertFalse(visible.contains(.liveSession) || visible.contains(.workouts) || visible.contains(.recoveryVitals))
        XCTAssertEqual(Array(visible.prefix(5)), [.hero, .synthesis, .heartRate, .stress, .keyMetrics])
    }

    func testLayoutV4PutsHeartRateAboveSynthesisAndKeepsTheRest() {
        let v4Raw = TodayLayoutPrefs.liquidV4Order(TodayLayoutPrefs.liquidV3Order(""))
        let fresh = TodayLayoutPrefs.decodeOrder(v4Raw)
        XCTAssertEqual(Array(fresh.prefix(5)), [.hero, .heartRate, .synthesis, .stress, .keyMetrics])
        XCTAssertEqual(Set(fresh), Set(TodaySection.allCases))
        // A wearer's own v3 rearrangement keeps every other section where it was.
        let own = "hero,keyMetrics,synthesis,stress,heartRate,journal"
        let named: Set<TodaySection> = [.hero, .keyMetrics, .synthesis, .stress, .heartRate, .journal]
        let moved = TodayLayoutPrefs.decodeOrder(TodayLayoutPrefs.liquidV4Order(own)).filter { named.contains($0) }
        XCTAssertEqual(moved, [.hero, .keyMetrics, .heartRate, .synthesis, .stress, .journal])
        let visible = TodayLayoutPrefs.liquidVisibleOrder(orderRaw: v4Raw, hiddenRaw: "")
        XCTAssertEqual(Array(visible.prefix(5)), [.hero, .heartRate, .synthesis, .stress, .keyMetrics])
    }

    // MARK: Chantier 17 (personal fork)

    func testLayoutV5PutsStressAboveSynthesisAndKeepsTheRest() {
        let fresh = TodayLayoutPrefs.decodeOrder(TodayLayoutPrefs.liquidDefaultOrderRaw)
        XCTAssertEqual(Array(fresh.prefix(5)), [.hero, .heartRate, .stress, .synthesis, .keyMetrics])
        XCTAssertEqual(Set(fresh), Set(TodaySection.allCases))
        XCTAssertEqual(fresh.count, TodaySection.allCases.count)
        // A wearer's own rearrangement keeps every other section where it was; only stress moves.
        let own = "hero,keyMetrics,heartRate,synthesis,journal,stress"
        let named: Set<TodaySection> = [.hero, .keyMetrics, .heartRate, .synthesis, .journal, .stress]
        let moved = TodayLayoutPrefs.decodeOrder(TodayLayoutPrefs.liquidV5Order(own)).filter { named.contains($0) }
        XCTAssertEqual(moved, [.hero, .keyMetrics, .heartRate, .stress, .synthesis, .journal])
        // Applying it again changes nothing.
        let once = TodayLayoutPrefs.liquidV5Order(own)
        XCTAssertEqual(TodayLayoutPrefs.liquidV5Order(once), once)
        // A hidden Stress card stays hidden, in its new slot.
        let visible = TodayLayoutPrefs.liquidVisibleOrder(orderRaw: TodayLayoutPrefs.liquidDefaultOrderRaw, hiddenRaw: "")
        XCTAssertEqual(Array(visible.prefix(5)), [.hero, .heartRate, .stress, .synthesis, .keyMetrics])
        let hidden = TodayLayoutPrefs.liquidVisibleOrder(orderRaw: TodayLayoutPrefs.liquidDefaultOrderRaw, hiddenRaw: "stress")
        XCTAssertEqual(Array(hidden.prefix(4)), [.hero, .heartRate, .synthesis, .keyMetrics])
    }

    func testRestoredBlocksAreOffByDefaultAndRoundTrip() {
        XCTAssertTrue(TodayRestoredBlock.decode("").isEmpty)
        let set = TodayRestoredBlock.decode("workouts,BOGUS,fitnessAge,workouts")
        XCTAssertEqual(set, [.workouts, .fitnessAge])
        XCTAssertEqual(TodayRestoredBlock.encode(set), "fitnessAge,workouts")
        XCTAssertEqual(TodayRestoredBlock.allCases.map(\.rawValue),
                       ["fitnessAge", "vitality", "liveSession", "workouts", "dataSources", "emptyTiles"])
    }

    func testEditableLayoutKeepsAtLeastOneItemVisible() {
        var draft = EditableLayoutDraft(visible: [KeyMetric.hrv], hidden: KeyMetric.defaultOrder.filter { $0 != .hrv })
        draft.hide(.hrv)
        XCTAssertEqual(draft.visible, [.hrv])
    }
}
