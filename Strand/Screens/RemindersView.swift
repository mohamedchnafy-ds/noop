import SwiftUI
import StrandDesign
import UserNotifications

// MARK: - Rappels (personal fork, chantier 10, PR C)
//
// The ONE screen of the reminders (mockup v2.1 screen 4), opened from Élan's bell and from Nutrition →
// Objectifs → Rappels: how many may go (Élan and meals together: one a day, four or two a week), the quiet
// hours, the four Élan reminders, the three meal reminders of chantier 8, the weigh-in apart, and the
// plan's usual session hour. Every switch writes its key and re-plans everything through the shared planner
// (`ReminderPlanner.refreshAllReminders`); the first switch turned on asks for notifications, here, with
// these words around the request. Nothing is sent anywhere: the reminders are planned on the phone.

struct RemindersView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore

    @AppStorage(ElanReminder.missedKey) private var missedOn = true
    @AppStorage(ElanReminder.plannedKey) private var plannedOn = true
    @AppStorage(ElanReminder.threeDaysKey) private var threeDaysOn = true
    @AppStorage(ElanReminder.weeklyKey) private var weeklyOn = true
    @AppStorage(ElanReminder.weighKey) private var weighOn = true
    @AppStorage(ElanReminder.weighMinutesKey) private var weighMinutes = ElanReminder.defaultWeighMinutes
    @AppStorage(MealReminder.trainingDayKey) private var mealTrainingDayOn = true
    @AppStorage(MealReminder.afterSessionKey) private var mealAfterSessionOn = true
    @AppStorage(MealReminder.eveningKey) private var mealEveningOn = false
    @AppStorage(MealReminder.minutesKey) private var mealMinutes = MealReminder.defaultMinutes
    @AppStorage(MealReminder.eveningMinutesKey) private var eveningMinutes = MealReminder.defaultEveningMinutes
    @AppStorage(ReminderPlanner.budgetKey) private var budgetRaw = ReminderBudget.daily.rawValue
    @AppStorage(ReminderPlanner.quietStartKey) private var quietStart = ReminderQuietHours.standard.startMinutes
    @AppStorage(ReminderPlanner.quietEndKey) private var quietEnd = ReminderQuietHours.standard.endMinutes

    /// The plan's usual session hour (`TrainingWeekPlan.sessionMinutes`), read on appear, written back on change.
    @State private var sessionMinutes = ElanReminder.defaultSessionMinutes
    @State private var authorization: UNAuthorizationStatus = .notDetermined
    @State private var quietExpanded = false

    init() {
        // The chantier 8 master switch, carried into the per-kind keys before they are read.
        MealReminder.migrateLegacySwitch()
    }

    private var budget: Binding<ReminderBudget> {
        Binding(get: { ReminderBudget(rawValue: budgetRaw) ?? .daily },
                set: { budgetRaw = $0.rawValue; refresh() })
    }

    var body: some View {
        ScreenScaffold(title: "Reminders",
                       subtitle: "Few reminders, at the right time. The same settings as Nutrition → Goals → Reminders.") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                authorizationCard
                section("How many") { budgetCard }
                section("Training") { trainingCard }
                section("Nutrition (already in the app)") { nutritionCard }
                section("Apart, outside the limit") { weighCard }
                sessionHourCard
                Text("If two reminders fall the same day, only one goes, the most useful: a missed session, then a planned session, then a meal, then three days without a session. The weigh-in does not count toward the limit.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
        .task {
            sessionMinutes = TrainingWeekPlan.loadWeekPlan().sessionMinutes ?? ElanReminder.defaultSessionMinutes
            await readAuthorization()
        }
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(StrandFont.footnote.weight(.medium))
                .foregroundStyle(StrandPalette.textSecondary)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    // MARK: Permission

    @ViewBuilder
    private var authorizationCard: some View {
        switch authorization {
        case .denied:
            NoopCard(padding: 14) {
                Text("Notifications are off for NOOP: turn them on in the Settings app.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.statusWarning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .notDetermined:
            NoopCard(padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Nothing is planned until NOOP may notify you. The reminders are planned on the phone; nothing is sent.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ElanActionButton(title: Text("Allow notifications"), look: .primary) {
                        Task { await requestAuthorization() }
                    }
                }
            }
        default:
            EmptyView()
        }
    }

    // MARK: How many

    private var budgetCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("At most, Élan and meals together")
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textPrimary)
            SegmentedPillControl(ReminderBudget.allCases, selection: budget, fillsAvailableWidth: true) { item in
                switch item {
                case .daily: return String(localized: "1 a day")
                case .fourPerWeek: return String(localized: "4 a week")
                case .twoPerWeek: return String(localized: "2 a week")
                }
            }
            hairline
            Button { withAnimation(.easeInOut(duration: 0.2)) { quietExpanded.toggle() } } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Quiet")
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text("no reminder during these hours")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Text(verbatim: TodaySynthesisLogic.clock(quietStart) + " – " + TodaySynthesisLogic.clock(quietEnd))
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textSecondary)
                    Image(systemName: quietExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if quietExpanded {
                timeRow("From", minutes: $quietStart)
                timeRow("Until", minutes: $quietEnd)
            }
        }
        .padding(16)
        .background(StrandPalette.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius, style: .continuous))
    }

    // MARK: Training

    private var trainingCard: some View {
        listCard {
            toggleRow(Text("The day after a miss"), subtitle: Text("short session proposed · \(TodaySynthesisLogic.clock(ElanReminder.missedMinutes))"),
                      isOn: $missedOn)
            hairline
            toggleRow(Text("Before a planned session"), subtitle: Text("an hour before the plan's usual time"), isOn: $plannedOn)
            hairline
            toggleRow(Text("After three days without a session"), subtitle: Text("your why and before / now"), isOn: $threeDaysOn)
            hairline
            toggleRow(Text("Week recap"), subtitle: Text("Sunday · \(TodaySynthesisLogic.clock(ElanReminder.weeklyMinutes))"), isOn: $weeklyOn)
        }
    }

    // MARK: Nutrition

    private var nutritionCard: some View {
        listCard {
            toggleRow(Text("Training day without a meal logged"), subtitle: Text("at \(TodaySynthesisLogic.clock(mealMinutes))"),
                      isOn: $mealTrainingDayOn)
            if mealTrainingDayOn {
                timeRow("At", minutes: $mealMinutes)
            }
            hairline
            toggleRow(Text("After a session without a meal logged"), subtitle: Text("an hour after the end"), isOn: $mealAfterSessionOn)
            hairline
            toggleRow(Text("Meals not logged in the evening"), subtitle: Text("at \(TodaySynthesisLogic.clock(eveningMinutes)) if nothing is logged"),
                      isOn: $mealEveningOn)
            if mealEveningOn {
                timeRow("At", minutes: $eveningMinutes)
            }
        }
    }

    // MARK: The weigh-in

    private var weighCard: some View {
        listCard {
            toggleRow(Text("Morning weigh-in"), subtitle: Text("every day · \(TodaySynthesisLogic.clock(weighMinutes))"), isOn: $weighOn)
            if weighOn {
                timeRow("At", minutes: $weighMinutes)
            }
        }
    }

    // MARK: The session hour

    private var sessionHourCard: some View {
        listCard {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Usual session time")
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("what « Before a planned session » counts from")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                Spacer(minLength: 8)
                DatePicker("", selection: sessionTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .accessibilityLabel(Text("Usual session time"))
            }
            .frame(minHeight: 56)
        }
    }

    /// The plan's hour as a date today, written back into the stored plan as minutes since midnight.
    private var sessionTime: Binding<Date> {
        Binding(get: { Self.date(minutes: sessionMinutes) }, set: { date in
            sessionMinutes = Self.minutes(of: date)
            var plan = TrainingWeekPlan.loadWeekPlan()
            plan.sessionMinutes = sessionMinutes
            plan.storeWeekPlan()
            refresh()
        })
    }

    // MARK: Pieces

    private func listCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.horizontal, 16)
        .background(StrandPalette.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius, style: .continuous))
    }

    private var hairline: some View {
        Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
    }

    private func toggleRow(_ title: Text, subtitle: Text, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                subtitle
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(get: { isOn.wrappedValue }, set: { on in
                isOn.wrappedValue = on
                switched(on: on)
            }))
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(StrandPalette.switchOn)
            .accessibilityLabel(title)
        }
        .frame(minHeight: 62)
    }

    /// A time of day under a switch, as minutes since midnight.
    private func timeRow(_ label: LocalizedStringKey, minutes: Binding<Int>) -> some View {
        HStack {
            Text(label)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
            Spacer()
            DatePicker("", selection: Binding(get: { Self.date(minutes: minutes.wrappedValue) },
                                              set: { minutes.wrappedValue = Self.minutes(of: $0); refresh() }),
                       displayedComponents: .hourAndMinute)
                .labelsHidden()
                .accessibilityLabel(Text(label))
        }
        .padding(.bottom, 10)
    }

    private static func date(minutes: Int) -> Date {
        let clamped = min(max(minutes, 0), 24 * 60 - 1)
        return Calendar.current.date(bySettingHour: clamped / 60, minute: clamped % 60, second: 0, of: Date()) ?? Date()
    }

    private static func minutes(of date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    // MARK: Permission and planning

    private func switched(on: Bool) {
        if on, authorization == .notDetermined {
            Task { await requestAuthorization() }
        } else {
            refresh()
        }
    }

    private func refresh() {
        let store = repo
        let wearer = profile
        Task { await ReminderPlanner.refreshAllReminders(repo: store, profile: wearer) }
    }

    @MainActor
    private func readAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @MainActor
    private func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        await readAuthorization()
        refresh()
    }
}
