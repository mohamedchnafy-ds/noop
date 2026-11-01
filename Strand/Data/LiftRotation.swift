import Foundation
import StrandAnalytics
import WhoopStore

/// The Lift Log's rotation: which saved program comes next, and how a program reads in one line.
///
/// One owner for the rule the Coach's context and the Today synthesis both state, so the two can never
/// name different programs for the same day (personal fork).
enum LiftRotation {
    /// A set that counts as training: not a warm-up, and actually performed.
    static func isWorking(_ set: LiftSetRow) -> Bool {
        !set.isWarmup && LiftMetrics.isPerformed(reps: set.reps)
    }

    /// The latest start per program among sessions that held at least one working set.
    static func lastDone(_ performed: [(programId: String?, startTs: Int)]) -> [String: Int] {
        performed.reduce(into: [:]) { acc, s in
            guard let id = s.programId else { return }
            acc[id] = max(acc[id] ?? 0, s.startTs)
        }
    }

    /// The program done least recently. A program never done comes first; ties keep `programIds` order.
    static func next(programIds: [String], lastDone: [String: Int]) -> String? {
        programIds.min { (lastDone[$0] ?? 0) < (lastDone[$1] ?? 0) }
    }

    /// A program's blocks: supersets (runs of two or more lines sharing a label) and lines done alone.
    static func shape(labels: [String?]) -> (supersets: Int, singles: Int) {
        let groups = LiftSuperset.groups(labels)
        let grouped = groups.reduce(0) { $0 + $1.count }
        return (groups.count, max(0, labels.count - grouped))
    }

    /// The usual length of a program in whole minutes: the mean of its finished sessions, nil when none.
    static func typicalMinutes(_ finished: [(startTs: Int, endTs: Int)]) -> Int? {
        let lengths = finished.map { Double($0.endTs - $0.startTs) }.filter { $0 > 0 }
        guard !lengths.isEmpty else { return nil }
        return Int((lengths.reduce(0, +) / Double(lengths.count) / 60).rounded())
    }
}
