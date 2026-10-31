import Foundation
import WhoopStore

// What the guided superset screens show, resolved from the session in ONE place (personal fork).
//
// A superset is run on three full screens rather than as a card in the session sheet: the block READY
// to start (its exercises, numbers, rounds and rest, one Start button), the round IN PROGRESS (a big
// clock, where the block stands, one Set-done button) and the REST between rounds (a countdown ring,
// what comes next, +30 s and Skip). Which of the three applies, to which block, and every number they
// show come from here, so the screens hold no session logic of their own and the decision is testable
// without SwiftUI (`LiftSessionGuidedTests`).
//
// Only a superset is guided. A line done on its own keeps the session sheet, so `make` answers nil
// whenever the session is not standing on, or heading for, a superset.
//
// PURE: no clock is read here — `now` is a parameter — and nothing is stored.

struct LiftSupersetGuide: Equatable {

    enum Phase: Equatable {
        /// The block has not started. `restEndsAt` is the end of the rest still running from the block
        /// before it, nil when there is none (the session's first block, or that rest is over).
        case ready(restEndsAt: Int?)
        /// A round is being worked, since `startedAt`.
        case working(startedAt: Int)
        /// Resting between two rounds of the block, from `startedAt` until `endsAt`.
        case resting(startedAt: Int, endsAt: Int)
    }

    /// One exercise of the block, as its screens list it.
    struct Member: Equatable {
        var index: Int
        /// "A1", "A2"…
        var tag: String
        var exercise: String
        var primaryMuscle: LiftMuscle?
        var secondaryMuscles: [LiftMuscle]
        var note: String?
        /// How many sets the line holds — fewer than the block's rounds when the counts are uneven.
        var targetSets: Int
    }

    var phase: Phase
    /// The plan index of the block's first line — the one the session drives the round through.
    var lead: Int
    /// "A", "B"…
    var letter: String
    var members: [Member]
    /// Where the block sits among the session's blocks (a line on its own is a block too), 1-based.
    var blockNumber: Int
    var blockCount: Int
    /// How many rounds the block holds.
    var rounds: Int
    /// The round in hand: the one about to start (ready), being worked, or just finished (resting).
    var round: Int
    /// Rounds already done, by number — they need not be the first ones, since any round can be redone.
    var doneRounds: Set<Int>
    /// The round the rest leads to. Nil outside a rest.
    var nextRound: Int?
    /// The rest the block takes after each round, in seconds.
    var restSec: Int
    /// How long the round just finished took. Nil outside a rest.
    var lastRoundSec: Int?
    var canAddRound: Bool
    var canRemoveRound: Bool

    /// The guided screen for `engine` at `now`, or nil when the session sheet applies.
    static func make(_ engine: LiftSessionEngine, now: Int) -> LiftSupersetGuide? {
        let anchor: LiftSlot
        let phase: Phase
        switch engine.stage {
        case .finished:
            return nil
        case .warmup:
            guard let next = engine.nextPendingSlot else { return nil }
            anchor = next
            phase = .ready(restEndsAt: nil)
        case .working(let slot):
            anchor = slot
            phase = .working(startedAt: engine.stageStartedAt)
        case .resting(let slot, let endsAt):
            // Everything done: the sheet, which says so and leads to Finish.
            guard let next = engine.slotAfter(slot) else { return nil }
            let members = engine.supersetMembers(of: slot.exerciseIndex)
            if members.count > 1, engine.supersetMembers(of: next.exerciseIndex) == members {
                anchor = slot
                phase = .resting(startedAt: engine.stageStartedAt, endsAt: endsAt)
            } else {
                // The block just left, or a line on its own, is behind: what is shown is where the
                // session goes next — the same slot `advance` would start.
                anchor = next
                phase = .ready(restEndsAt: endsAt > now ? endsAt : nil)
            }
        }
        let members = engine.supersetMembers(of: anchor.exerciseIndex)
        guard members.count > 1, let lead = members.first,
              let letter = engine.supersetLetter(of: lead) else { return nil }

        let rounds = members.map { engine.plan[$0].targetSets }.max() ?? 1
        let doneRounds = Set((1...max(1, rounds)).filter {
            engine.isCompleted(engine.leadSlot(LiftSlot(exerciseIndex: lead, setIndex: $0)))
        })
        let blocks = engine.blocks
        var nextRound: Int?
        var lastRoundSec: Int?
        if case .resting = phase {
            nextRound = engine.slotAfter(anchor)?.setIndex
            lastRoundSec = engine.recordedSet(for: anchor).map { max(0, $0.endTs - $0.startTs) }
        }
        return LiftSupersetGuide(
            phase: phase,
            lead: lead,
            letter: letter,
            members: members.map { index in
                let item = engine.plan[index]
                return Member(index: index, tag: engine.supersetTag(of: index) ?? "",
                              exercise: item.exercise, primaryMuscle: item.primaryMuscle,
                              secondaryMuscles: item.secondaryMuscles, note: item.note,
                              targetSets: item.targetSets)
            },
            blockNumber: (blocks.firstIndex { $0.contains(lead) } ?? 0) + 1,
            blockCount: blocks.count,
            rounds: rounds,
            round: anchor.setIndex,
            doneRounds: doneRounds,
            nextRound: nextRound,
            restSec: engine.restAfter(LiftSlot(exerciseIndex: lead, setIndex: 1)),
            lastRoundSec: lastRoundSec,
            canAddRound: rounds < LiftSessionEngine.maxSetsPerExercise,
            canRemoveRound: engine.canRemoveSet(fromExercise: lead))
    }

    // MARK: - Last time

    /// The block as it was done last time, for its ready screen: when, how many rounds, each member's
    /// numbers in round 1, the rest most often taken and how long the block took.
    struct LastTime: Equatable {
        var date: Date
        var rounds: Int
        /// Per member, in block order: round 1's weight (kg) and reps.
        var numbers: [LiftSetCarry]
        var restSec: Int?
        var durationSec: Int?
    }

    /// `rows[i]` is member i's sets from its last session (`WhoopStore.lastLiftSets`). Nil unless every
    /// member has sets, all from ONE session: a block assembled from different days would describe a
    /// workout that never happened.
    static func lastTime(rows: [[LiftSetRow]]) -> LastTime? {
        let working = rows.map { $0.filter { !$0.isWarmup } }
        guard !working.isEmpty, working.allSatisfy({ !$0.isEmpty }),
              Set(working.flatMap { $0.map(\.sessionId) }).count == 1 else { return nil }
        let all = working.flatMap { $0 }
        let starts = all.compactMap(\.startTs)
        let ends = all.compactMap(\.endTs)
        guard let first = starts.min() else { return nil }
        let rests = all.compactMap(\.restSec).filter { $0 > 0 }
        // The rest taken most often; the longer one on a tie, which is the planned one far more often
        // than not (a short rest is usually a round cut short).
        let usualRest = Dictionary(grouping: rests, by: { $0 })
            .max { ($0.value.count, $0.key) < ($1.value.count, $1.key) }?.key
        return LastTime(
            date: Date(timeIntervalSince1970: TimeInterval(first)),
            rounds: working.map(\.count).max() ?? 0,
            numbers: working.map { sets in
                let firstRound = sets.min { $0.setIndex < $1.setIndex }
                return LiftSetCarry(weightKg: firstRound?.weightKg, reps: firstRound?.reps)
            },
            restSec: usualRest,
            durationSec: ends.max().map { max(0, $0 - first) })
    }
}
