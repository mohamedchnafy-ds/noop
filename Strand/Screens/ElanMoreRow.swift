import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - The Élan row of the Plus sheet (personal fork, chantier 10, PR B)
//
// Mohamed's choice (5 Nov.): Élan is reached ONLY by one row at the head of the Plus sheet, under the
// profile card, with its standing on the right (the week's sessions) and a blue dot when something new
// waits (yesterday's session missed, nothing decided yet). Nothing on Today. The label is shared so it
// renders to PNG on macOS; the live row below reads the same resolver as the Élan screen.

struct ElanMoreRowLabel: View {
    /// « 1 / 3 sessions », nil while loading.
    var line: String?
    var isNew: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "flame.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(StrandPalette.surfaceBase)
                .frame(width: 40, height: 40)
                .background(StrandPalette.elanSand, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Élan")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                if let line {
                    Text(verbatim: line)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if isNew {
                Circle().fill(StrandPalette.accent).frame(width: 8, height: 8)
                    .accessibilityLabel(Text("new"))
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StrandPalette.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
            .strokeBorder(StrandPalette.elanSand.opacity(0.35), lineWidth: 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// `ElanMoreRowLabel` fed live: the week's tally and whether yesterday's missed session waits for an answer,
/// from the calendar's own reads (`TrainingSnapshot`, `TrainingDays`, `ElanResolver`).
struct ElanMoreRowHost: View {
    @EnvironmentObject private var repo: Repository
    @State private var line: String?
    @State private var isNew = false

    var body: some View {
        ElanMoreRowLabel(line: line, isNew: isNew)
            .task(id: repo.refreshSeq) { await load() }
    }

    @MainActor
    private func load() async {
        let now = Date()
        let calendar = Calendar.current
        guard let snapshot = await TrainingSnapshot.loadTrainingSnapshot(repo: repo, historyDays: 14,
                                                                         effortScale: .hundred, now: now) else { return }
        let monday = TrainingCalendar.mondayOf(now, calendar: calendar)
        let week = TrainingDays.buildTrainingDays(TrainingCalendar.weekDates(from: monday, calendar: calendar),
                                                  plan: snapshot.plan, lifts: snapshot.lifts,
                                                  activities: snapshot.activities, now: now, calendar: calendar)
        let tally = TrainingDays.sessionTally(week)
        if tally.planned > 0 {
            line = String(localized: "\(tally.done) / \(tally.planned) sessions this week")
        } else {
            line = String(localized: "\(tally.done) sessions this week")
        }
        let today = TrainingCalendar.trainingDayKey(now, calendar: calendar)
        let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) ?? now
        let yesterday = TrainingDays.buildTrainingDays([yesterdayDate], plan: snapshot.plan, lifts: snapshot.lifts,
                                                       activities: snapshot.activities, now: now, calendar: calendar).first
        let names = Dictionary(snapshot.programs.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let missed = ElanResolver.elanMissedYesterday(yesterday, programNames: names)
        isNew = missed != nil
            && !ElanShortSessionChoice.isDismissed(day: today)
            && ElanShortSessionChoice.acceptedProgramId(day: today) == nil
    }
}
