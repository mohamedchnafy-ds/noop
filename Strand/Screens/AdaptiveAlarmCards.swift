import SwiftUI
import StrandDesign

// Personal fork, chantier 25 — the Alarms screen's adaptive mode, Fajr alarm and wake question. Separate
// views so `SmartAlarmView` stays within the iOS type-check budget. Every time shown comes from
// `WakeSchedule`, the plan the strap is armed from.

/// The one-tap question after a wake: tired or rested. Hidden when nothing is waiting for an answer.
struct WakeFeedbackCard: View {
    @EnvironmentObject private var model: AppModel
    /// Bumped after an answer so the card re-reads the journal and disappears.
    @State private var revision = 0

    var body: some View {
        let _ = revision
        if let event = WakeLearning.pendingQuestion(history: WakeJournal.load(), now: Date()) {
            StrandCard(padding: 20, tint: StrandPalette.sleepWake) {
                VStack(alignment: .leading, spacing: 12) {
                    if event.kind == .fajr {
                        Text("Fajr alarm").strandOverline()
                    } else {
                        Text("This morning").strandOverline()
                    }
                    Text(Self.headline(event))
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("How do you feel?")
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textSecondary)
                    HStack(spacing: 10) {
                        Button { answer(event, .tired) } label: {
                            Label("Tired", systemImage: "battery.25")
                        }
                        .buttonStyle(NoopButtonStyle(.secondary, fullWidth: true))
                        Button { answer(event, .fresh) } label: {
                            Label("Rested", systemImage: "sun.max.fill")
                        }
                        .buttonStyle(NoopButtonStyle(.primary, fullWidth: true))
                    }
                    Text("Your answers tune the adaptive mode, night after night.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func answer(_ event: WakeEvent, _ feeling: WakeFeeling) {
        model.answerWake(event, feeling: feeling)
        revision += 1
    }

    static func headline(_ event: WakeEvent) -> String {
        let time = WakeNotification.wakeClock(event.wokeAt)
        if event.adaptive { return String(localized: "Your strap buzzed at \(time), in a lighter phase.") }
        return String(localized: "Woken at \(time), the end of your window.")
    }
}

/// The adaptive mode of the main alarm, inside the strap alarm card.
struct AdaptiveModeSection: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(WakeAlarmSettings.adaptiveKey) private var adaptive = false
    @AppStorage(WakeAlarmSettings.windowKey) private var window = WakePlan.defaultWindowMinutes
    /// The earliest wake set above, minutes since midnight.
    let earliestMinutes: Int
    /// True when some days have a time of their own: then no single deadline can be named here.
    let hasOverrides: Bool

    /// Explicit: the private property wrappers would make the memberwise initializer private.
    init(earliestMinutes: Int, hasOverrides: Bool) {
        self.earliestMinutes = earliestMinutes
        self.hasOverrides = hasOverrides
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Adaptive mode")
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("At night NOOP listens to your heart rate from the strap and buzzes it when you come out of a deeper phase, from your earliest time. The end of the window is guaranteed: the strap's own alarm is armed there.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: $adaptive)
                    .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                    .accessibilityLabel("Adaptive mode")
            }
            if adaptive {
                HStack {
                    Text("Window").font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                    Picker("", selection: $window) {
                        ForEach(WakePlan.windowChoices, id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel("Window")
                }
                .frame(minHeight: 42)
                Text(deadlineLine)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(AdaptiveWakeCopy.learnedLine(kind: .main))
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Keep the strap on, Bluetooth on and NOOP open in the background (not swiped away), so it can hear your heart at night.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChangeCompat(of: adaptive) { _ in model.applySmartAlarm() }
        .onChangeCompat(of: window) { _ in model.applySmartAlarm() }
    }

    private var deadlineLine: String {
        let minutes = WakePlan.clampedWindow(window)
        guard !hasOverrides else {
            return String(localized: "Guaranteed \(minutes) min after the earliest time, never later.")
        }
        let deadline = (earliestMinutes + minutes) % (24 * 60)
        let label = String(format: "%02d:%02d", deadline / 60, deadline % 60)
        return String(localized: "Guaranteed by \(label), never later.")
    }
}

/// Copy shared by the two adaptive alarms.
enum AdaptiveWakeCopy {
    /// What the detector currently waits for, and how many answers taught it.
    static func learnedLine(kind: WakeAlarmKind) -> String {
        let journal = WakeJournal.load()
        let rise = WakeLearning.riseBpm(history: journal, kind: kind)
        let answers = WakeLearning.answeredCount(history: journal, kind: kind)
        if answers == 0 {
            return String(localized: "It waits for a rise of \(rise) bpm over the night's lowest heart rate. Your answer each morning adjusts it.")
        }
        if answers == 1 {
            return String(localized: "It waits for a rise of \(rise) bpm over the night's lowest heart rate, learned from 1 answer.")
        }
        return String(localized: "It waits for a rise of \(rise) bpm over the night's lowest heart rate, learned from \(answers) answers.")
    }
}

/// The Fajr alarm: anchored on the adhan of Masjid At-Tawba, `lead` minutes before it, never after.
struct FajrAlarmCard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var behavior: BehaviorStore
    @AppStorage(WakeAlarmSettings.fajrKey) private var fajrOn = false
    @AppStorage(WakeAlarmSettings.fajrLeadKey) private var lead = WakePlan.defaultLeadMinutes
    @AppStorage(WakeAlarmSettings.fajrAdaptiveKey) private var adaptive = true
    @State private var tokenDraft = ""
    @State private var hasToken = MawaqitTokenStore.hasToken
    @State private var refreshing = false
    /// Bumped after a fetch so the times and the status re-read the cache.
    @State private var revision = 0

    var body: some View {
        StrandCard(padding: 20, tint: fajrOn ? StrandPalette.sleepWake : nil) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prayer").strandOverline()
                    HStack(spacing: 10) {
                        Image(systemName: "sun.horizon.fill")
                            .foregroundStyle(StrandPalette.sleepWake)
                            .accessibilityHidden(true)
                        Text("Fajr alarm")
                            .font(StrandFont.title2)
                            .foregroundStyle(StrandPalette.textPrimary)
                    }
                }
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wake me before Fajr")
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text("A second alarm on the adhan of Masjid At-Tawba (Bagnols-sur-Cèze), never after it. The strap buzzes; the phone cannot ring loudly.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: $fajrOn)
                        .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                        .accessibilityLabel("Wake me before Fajr")
                }
                if fajrOn {
                    Divider().overlay(StrandPalette.hairline)
                    adhanRows
                    Divider().overlay(StrandPalette.hairline)
                    settingsRows
                    Divider().overlay(StrandPalette.hairline)
                    tokenRows
                }
            }
        }
        .onChangeCompat(of: fajrOn) { _ in model.applySmartAlarm() }
        .onChangeCompat(of: lead) { _ in model.applySmartAlarm() }
        .onChangeCompat(of: adaptive) { _ in model.applySmartAlarm() }
    }

    @ViewBuilder private var adhanRows: some View {
        let _ = revision
        let now = Date()
        if let adhan = WakeSchedule.nextAdhan(now: now) {
            HStack {
                Text("Next adhan").font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                Spacer()
                Text(Self.dayClock(adhan.time))
                    .font(StrandFont.bodyNumber)
                    .foregroundStyle(StrandPalette.sleepWake)
            }
            Text(Self.sourceLine(adhan.source))
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let window = WakeSchedule.upcomingWindows(now: now).first(where: { $0.kind == .fajr }) {
            Text(Self.windowLine(window))
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var settingsRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Before the adhan").font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
            Picker("", selection: $lead) {
                ForEach(WakePlan.leadChoices, id: \.self) { minutes in
                    Text("\(minutes) min").tag(minutes)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Before the adhan")
        }
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Adaptive in this margin")
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("The strap buzzes at a lighter phase within the margin, and at the adhan at the latest.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: $adaptive)
                .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                .accessibilityLabel("Adaptive in this margin")
        }
        if adaptive {
            Text(AdaptiveWakeCopy.learnedLine(kind: .fajr))
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if behavior.smartAlarmEnabled {
            Text("When the adhan falls within 45 min of your main alarm, only the earlier of the two buzzes that morning.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var tokenRows: some View {
        let _ = revision
        Text("Mosque times (MAWAQIT)").font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
        if hasToken {
            if let status = Self.statusLine() {
                Text(status)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button { refresh() } label: {
                    if refreshing {
                        Text("Updating…")
                    } else {
                        Text("Update now")
                    }
                }
                .buttonStyle(NoopButtonStyle(.secondary, fullWidth: true))
                .disabled(refreshing)
                Button(role: .destructive) {
                    MawaqitTokenStore.clear()
                    FajrTimes.clearTimetable()
                    hasToken = false
                    revision += 1
                    model.applySmartAlarm()
                } label: {
                    Text("Remove the token")
                }
                .buttonStyle(NoopButtonStyle(.secondary, fullWidth: true))
            }
        } else {
            Text("MAWAQIT's API is reserved for its own apps: ask MAWAQIT (support@mawaqit.net) for an access token for your account, then paste it here. Until then NOOP calculates Fajr on the phone. Only the mosque's id is sent, once a day.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            SecureField("Paste your MAWAQIT token", text: $tokenDraft)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("MAWAQIT token")
            Button {
                if MawaqitTokenStore.save(tokenDraft) {
                    tokenDraft = ""
                    hasToken = MawaqitTokenStore.hasToken
                    refresh()
                }
            } label: {
                Text("Save the token")
            }
            .buttonStyle(NoopButtonStyle(.primary, fullWidth: true))
            .disabled(tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func refresh() {
        refreshing = true
        Task { @MainActor in
            _ = await MawaqitClient.refreshIfNeeded(force: true, log: { line in model.live.append(log: line) })
            refreshing = false
            revision += 1
            model.applySmartAlarm()
        }
    }

    static func dayClock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.activeLocale
        formatter.setLocalizedDateFormatFromTemplate("EEE jj:mm")
        return formatter.string(from: date)
    }

    static func sourceLine(_ source: FajrSource) -> String {
        switch source {
        case .mosque(let fetchedAt):
            let day = fetchedAt.formatted(.dateTime.day().month(.abbreviated).locale(AppLanguage.activeLocale))
            return String(localized: "The mosque's timetable from MAWAQIT, updated \(day).")
        case .calculated:
            return String(localized: "Calculated on the phone (sun 15° below the horizon): usually 3 to 5 min before the mosque's adhan.")
        }
    }

    static func windowLine(_ window: WakeWindow) -> String {
        let start = WakeNotification.wakeClock(window.start)
        let end = WakeNotification.wakeClock(window.deadline)
        if window.adaptive { return String(localized: "Next window: \(start) to \(end), the adhan.") }
        return String(localized: "Next buzz: \(end).")
    }

    static func statusLine() -> String? {
        guard let last = MawaqitClient.lastOutcome() else { return nil }
        switch last.outcome {
        case .ok:
            return nil
        case .unauthorized:
            return String(localized: "MAWAQIT refused the token. Check it, or ask MAWAQIT for access; the calculated times are used meanwhile.")
        case .network:
            return String(localized: "MAWAQIT could not be reached. NOOP tries again later and keeps the times it has.")
        case .invalid:
            return String(localized: "MAWAQIT's answer could not be read. NOOP keeps the times it has.")
        }
    }
}
