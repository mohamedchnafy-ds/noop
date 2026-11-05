import SwiftUI
import StrandDesign

/// The Lift Log's end-of-session scoreboard (personal fork, chantier 12, effect F): the shared
/// `NoopScoreboard` with the session's length, its working sets and their volume, then its records, counted
/// by the one resolver (`LiftRecordBook`).
struct LiftScoreboardView: View {
    let figures: LiftScoreboardFigures
    let system: UnitSystem
    let onClose: () -> Void

    private var lines: [NoopScoreboardLine] {
        [NoopScoreboardLine(id: 0, label: Text("Duration"), value: ActiveWorkoutClock.clock(figures.seconds),
                            tint: StrandPalette.textPrimary),
         NoopScoreboardLine(id: 1, label: Text("Sets"), value: String(figures.workingSets),
                            tint: StrandPalette.effortColor),
         NoopScoreboardLine(id: 2, label: Text("Volume"),
                            value: LiftFormat.weight(figures.volumeKg.rounded(), system: system),
                            tint: StrandPalette.textPrimary)]
    }

    private var recordLine: Text? {
        switch figures.records {
        case 0: return nil
        case 1: return Text("1 record")
        default: return Text("\(figures.records) records")
        }
    }

    var body: some View {
        NoopScoreboard(title: Text(verbatim: figures.title ?? String(localized: "Session")), lines: lines,
                       record: recordLine, recordBadge: Text("Record badge"),
                       recordKey: "lift.scoreboard.\(figures.seconds).\(figures.workingSets)",
                       closeLabel: Text("Done"), onClose: onClose)
    }
}
