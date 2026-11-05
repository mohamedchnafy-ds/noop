import Foundation
import WhoopStore

// MARK: - Lift Log records (personal fork, chantier 12, effect D)
//
// The ONE resolver of a personal record, read by the running session, the end-of-session summary and a
// session's sheet, so the three can never disagree on what counted.
//
// Rule (Mohamed's default, 5 Nov.): a set is a record when its load beats the best load ever done on that
// exercise, or when it repeats a load already done with more reps than the best at that load. Never on
// the first session of an exercise (nothing to beat), and only against the sets of FINISHED sessions that
// started before the one being judged: warm-ups and sets without a load or reps never count.

/// The best of each exercise over the finished sessions before a given start.
struct LiftRecordBook: Equatable {
    struct Best: Equatable {
        /// The heaviest working load done, in kilograms.
        var topKg: Double
        /// The most reps done at each load, the load in hundredths of a kilogram.
        var repsAtLoad: [Int: Int]
    }

    var bests: [String: Best] = [:]

    static let empty = LiftRecordBook()

    /// A load as the key of `repsAtLoad`: hundredths of a kilogram, so 62.5 and 62.50 are one load.
    static func loadKey(_ kg: Double) -> Int { Int((kg * 100).rounded()) }

    /// Builds the book from finished sets: warm-ups and sets without a load or reps are left out.
    static func liftRecordBook(from sets: [LiftSetRow]) -> LiftRecordBook {
        var book = LiftRecordBook()
        for set in sets where !set.isWarmup {
            guard let kg = set.weightKg, kg > 0, let reps = set.reps, reps > 0 else { continue }
            var best = book.bests[set.exercise] ?? Best(topKg: kg, repsAtLoad: [:])
            best.topKg = max(best.topKg, kg)
            let key = loadKey(kg)
            best.repsAtLoad[key] = max(best.repsAtLoad[key] ?? 0, reps)
            book.bests[set.exercise] = best
        }
        return book
    }

    /// Whether a working set of `exercise` at `weightKg` × `reps` is a record against this book.
    func liftRecordCheck(exercise: String, weightKg: Double?, reps: Int?, isWarmup: Bool = false) -> Bool {
        guard !isWarmup, let kg = weightKg, kg > 0, let reps, reps > 0,
              let best = bests[exercise] else { return false }
        if Self.loadKey(kg) > Self.loadKey(best.topKg) { return true }
        guard let bestReps = best.repsAtLoad[Self.loadKey(kg)] else { return false }
        return reps > bestReps
    }

    /// The book of every finished session that started before `before` (unix seconds).
    static func loadLiftRecordBook(repo: Repository, before: Int) async -> LiftRecordBook {
        guard let store = await repo.storeHandle() else { return .empty }
        let sessions = ((try? await store.liftSessions(deviceId: repo.deviceId, fromTs: 0,
                                                       toTs: max(0, before - 1))) ?? [])
            .filter { $0.endTs != nil && $0.startTs < before }
        var sets: [LiftSetRow] = []
        for session in sessions {
            sets += (try? await store.liftSets(sessionId: session.id)) ?? []
        }
        return liftRecordBook(from: sets)
    }
}

// MARK: - End-of-session scoreboard (effect F)

/// What the Lift Log's end-of-session scoreboard shows, from the rows just saved.
struct LiftScoreboardFigures: Equatable {
    var title: String?
    var seconds: Int
    var workingSets: Int
    var volumeKg: Double
    var records: Int

    /// The figures of a saved session: its working sets (performed, not warm-ups), their volume, and how
    /// many of them `book` counts as records.
    static func liftScoreboard(title: String?, seconds: Int, rows: [LiftSetRow],
                               book: LiftRecordBook) -> LiftScoreboardFigures {
        let working = rows.filter { !$0.isWarmup && ($0.reps ?? 0) > 0 }
        let volume = working.reduce(0.0) { $0 + ($1.weightKg ?? 0) * Double($1.reps ?? 0) }
        let records = working.filter {
            book.liftRecordCheck(exercise: $0.exercise, weightKg: $0.weightKg, reps: $0.reps)
        }.count
        return LiftScoreboardFigures(title: title, seconds: seconds, workingSets: working.count,
                                     volumeKg: volume, records: records)
    }
}
