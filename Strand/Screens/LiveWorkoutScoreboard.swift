import SwiftUI
import StrandDesign

// MARK: - Countdown setting and the cardio scoreboard (personal fork, chantier 12)

/// « Countdown before a session » (Settings, on by default): a 3 · 2 · 1 · Go before a live cardio session.
/// Device-only (`UserDefaults`, outside `.noopbak`), read here and nowhere else.
enum WorkoutCountdownPrefs {
    static let enabledKey = "workout.countdown.enabled"

    /// Whether the countdown plays: on until switched off.
    static func isOn(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }
}

/// What the scoreboard of a live workout shows, read from the workout as it is ended.
struct LiveWorkoutScoreboard: Equatable {
    var title: String
    var seconds: Int
    var averageHr: Int?
    var peakHr: Int?
    var effortText: String
    /// The Effort's share of its scale, for the ring.
    var effortFraction: Double

    static func liveScoreboard(_ workout: AppModel.ActiveWorkout, scale: EffortScale) -> LiveWorkoutScoreboard {
        let value = UnitFormatter.effortValue(workout.liveStrain, scale: scale)
        let top = scale == .whoop ? 21.0 : 100.0
        return LiveWorkoutScoreboard(
            title: WorkoutSource.displaySport(workout.sport),
            seconds: Int(workout.elapsed()),
            averageHr: workout.avgHr > 0 ? workout.avgHr : nil,
            peakHr: workout.savedPeak,
            effortText: UnitFormatter.effortDisplay(workout.liveStrain, scale: scale),
            effortFraction: min(max(value / top, 0), 1))
    }
}

/// The end of a live workout as a scoreboard (effect F): the Effort ring in a gradient (effect A), then the
/// duration and the average and peak heart rate.
struct LiveWorkoutScoreboardView: View {
    let figures: LiveWorkoutScoreboard
    let onClose: () -> Void

    private var lines: [NoopScoreboardLine] {
        var out = [NoopScoreboardLine(id: 0, label: Text("Duration"),
                                      value: ActiveWorkoutClock.clock(figures.seconds),
                                      tint: StrandPalette.textPrimary)]
        if let average = figures.averageHr {
            out.append(NoopScoreboardLine(id: 1, label: Text("Average heart rate"), value: "\(average) bpm",
                                          tint: StrandPalette.metricRose))
        }
        if let peak = figures.peakHr {
            out.append(NoopScoreboardLine(id: 2, label: Text("Max heart rate"), value: "\(peak) bpm",
                                          tint: StrandPalette.metricRose))
        }
        return out
    }

    var body: some View {
        NoopScoreboard(title: Text(verbatim: figures.title), lines: lines,
                       ring: (fraction: figures.effortFraction, tint: StrandPalette.effortColor,
                              deep: StrandPalette.effortDeep, value: figures.effortText),
                       recordBadge: Text("Record badge"), recordKey: "live.scoreboard",
                       closeLabel: Text("Done"), onClose: onClose)
    }
}
