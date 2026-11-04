import Foundation
import WhoopStore

// The program editor's blocks (personal fork, Supersets et blocs, 4 Nov.).
//
// A BLOCK is what a session runs as one: a superset (consecutive lines with the same label,
// `LiftSuperset.blocks`) or a line on its own. The editor moves whole blocks, takes one line out of its
// superset, and adds a ready-made superset from the body map. The grouping stays the one `LiftSuperset`
// rule: these helpers only reorder lines and rewrite their labels, then `LiftSuperset.relabeled` letters
// them A, B, C… again.
//
// PURE: no store, no UI. Tested in `LiftProgramBlocksTests`.

enum LiftProgramBlocks {

    /// The line order after the block holding line `index` moves `offset` blocks (−1 up, +1 down): the
    /// indices of the old lines in their new order. Unchanged when the block is already at that end.
    static func moveProgramBlock(labels: [String?], containing index: Int, by offset: Int) -> [Int] {
        var blocks = LiftSuperset.blocks(labels)
        let identity = Array(labels.indices)
        guard let from = blocks.firstIndex(where: { $0.contains(index) }) else { return identity }
        let to = from + offset
        guard blocks.indices.contains(to) else { return identity }
        blocks.swapAt(from, to)
        return blocks.flatMap { Array($0) }
    }

    /// The line order and labels after line `index` leaves its superset: it goes right after the
    /// superset, on its own (no label). A superset of two leaves two lines on their own. Unchanged for a
    /// line that is not in a superset.
    static func detachFromSuperset(labels: [String?], index: Int) -> (order: [Int], labels: [String?]) {
        let identity = Array(labels.indices)
        guard let group = LiftSuperset.group(of: index, in: labels) else { return (identity, labels) }
        var order = identity.filter { $0 != index }
        // After the group's last remaining line, which sits one place earlier once `index` is out.
        order.insert(index, at: group.upperBound - 1)
        var moved = order.map { labels[$0] }
        if let at = order.firstIndex(of: index) { moved[at] = nil }
        return (order, LiftSuperset.relabeled(moved))
    }

    /// The labels after `count` new lines are added at the end as ONE superset (two or more of them).
    static func appendingSuperset(labels: [String?], count: Int) -> [String?] {
        let fresh = "~new"
        return LiftSuperset.relabeled(labels + Array(repeating: count >= 2 ? fresh : nil, count: max(0, count)))
    }

    // MARK: A superset added from the body map

    /// Most exercises one superset added from the body map takes (the mockup's 2 or 3).
    static let maxSupersetPicks = 3
    /// The rest after the round of a superset added from the body map (the mockup's 1:30).
    static let supersetRestSec = 90
    /// The targets of an exercise never logged: 3 × 10, no weight.
    static let defaultSets = 3
    static let defaultReps = 10

    /// The targets a line added in a superset takes from the exercise's last session (`lastLiftSets`):
    /// as many sets as its working sets, and the reps and weight of its heaviest working set (the first
    /// of them on a tie). Never logged: 3 × 10, no weight.
    static func supersetDraftTargets(lastSets: [LiftSetRow]) -> (sets: Int, reps: Int, weightKg: Double?) {
        let working = lastSets.filter { !$0.isWarmup }
        guard !working.isEmpty else { return (defaultSets, defaultReps, nil) }
        var top = working[0]
        for set in working.dropFirst() where (set.weightKg ?? 0) > (top.weightKg ?? 0) { top = set }
        return (working.count, top.reps ?? defaultReps, top.weightKg)
    }
}
