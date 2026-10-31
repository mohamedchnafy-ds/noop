import Foundation

// Which program lines form a superset, kept BESIDE the program rather than in them.
//
// A superset is two (or more) lines of one program performed back to back, then rested from together
// (`LiftSessionEngine`, "Supersets"). The grouping is a property of the program, so it belongs with it —
// but `liftProgramItem` is a cross-platform table pinned by the schema oracle and mirrored by Room, and a
// column there is a migration on two platforms plus the backup contract. Until Android has a session
// screen to read it, the grouping lives here: one defaults entry per program, keyed by the program
// line's id, so a line keeps its group through reorders and edits and loses it when it is deleted.
//
// Not part of the `.noopbak` backup, deliberately: a restored program comes back ungrouped and is
// regrouped in the editor in two taps, which is a smaller debt than a schema column nothing else reads.

enum LiftSupersetGroups {

    static let key = "noop.liftSupersetGroups"

    /// `programId` → (`liftProgramItem.id` → group id). A group id is opaque; lines sharing one are a
    /// superset. A group of one is no superset and is ignored by the engine.
    typealias Groups = [String: String]

    static func groups(programId: String, from defaults: UserDefaults = .standard) -> Groups {
        all(from: defaults)[programId] ?? [:]
    }

    /// Replace the grouping of one program. Lines not in `items` are dropped, so a deleted line does not
    /// keep a ghost group; a program with no superset keeps no entry at all.
    static func store(_ groups: Groups, programId: String, items: [String],
                      in defaults: UserDefaults = .standard) {
        var everything = all(from: defaults)
        let kept = groups.filter { items.contains($0.key) }
        if kept.isEmpty { everything.removeValue(forKey: programId) }
        else { everything[programId] = kept }
        if let data = try? JSONEncoder().encode(everything) {
            defaults.set(data, forKey: key)
        }
    }

    static func remove(programId: String, from defaults: UserDefaults = .standard) {
        var everything = all(from: defaults)
        everything.removeValue(forKey: programId)
        if let data = try? JSONEncoder().encode(everything) {
            defaults.set(data, forKey: key)
        }
    }

    private static func all(from defaults: UserDefaults) -> [String: Groups] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: Groups].self, from: data) else { return [:] }
        return decoded
    }

    // MARK: - Editing

    /// Pair `index` with the line before it: they join the previous line's group, or a new one when the
    /// previous line has none. Pure, so the editor's toggle is testable without defaults.
    static func linking(_ index: Int, toPrevious ids: [String], groups: Groups) -> Groups {
        guard index > 0, ids.indices.contains(index) else { return groups }
        var out = groups
        let group = groups[ids[index - 1]] ?? UUID().uuidString
        out[ids[index - 1]] = group
        out[ids[index]] = group
        return out
    }

    /// Cut the link between `index` and the line before it. The line leaves its group; whatever follows
    /// it in the same group goes with it, so a chain of three cut in the middle leaves two pairs that
    /// never mix. A group left with one member is dropped.
    static func unlinking(_ index: Int, fromPrevious ids: [String], groups: Groups) -> Groups {
        guard index > 0, ids.indices.contains(index), let group = groups[ids[index]] else { return groups }
        var out = groups
        let tail = UUID().uuidString
        for i in index..<ids.count where groups[ids[i]] == group {
            out[ids[i]] = tail
        }
        return dropSingletons(out)
    }

    /// Whether `index` is in the same superset as the line before it.
    static func isLinkedToPrevious(_ index: Int, ids: [String], groups: Groups) -> Bool {
        guard index > 0, ids.indices.contains(index), let group = groups[ids[index]] else { return false }
        return groups[ids[index - 1]] == group
    }

    /// Groups as they stand after a reorder: a group whose members are no longer adjacent is cut at the
    /// gap, and a group of one is dropped. The editor calls this after every move.
    static func normalised(ids: [String], groups: Groups) -> Groups {
        var out: Groups = [:]
        var i = 0
        while i < ids.count {
            guard let group = groups[ids[i]] else { i += 1; continue }
            var j = i
            while j + 1 < ids.count, groups[ids[j + 1]] == group { j += 1 }
            if j > i {
                let fresh = UUID().uuidString
                for k in i...j { out[ids[k]] = fresh }
            }
            i = j + 1
        }
        return out
    }

    private static func dropSingletons(_ groups: Groups) -> Groups {
        var count: [String: Int] = [:]
        for g in groups.values { count[g, default: 0] += 1 }
        return groups.filter { (count[$0.value] ?? 0) > 1 }
    }
}
