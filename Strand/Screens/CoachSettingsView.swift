import SwiftUI
import StrandDesign

/// Coach settings, split out of `CoachView` so the coach screen is the conversation and nothing else
/// (#2243). Holds the model, a link to what the coach reads (`CoachDataView`, which holds the data-sharing
/// consent and the summary opt-in in this fork), the Gemini chart opt-in, the extra instructions, and the
/// morning brief.
///
/// Connection management (the provider pill, Update key, Clear conversation, Disconnect) stays on
/// `CoachView`, where both the conversation and the key editor are visible. The Kotlin twin
/// `CoachSettingsScreen` keeps the consents on its settings screen: the coach refonte is iPhone only.
///
/// Presented as a sheet rather than pushed. CoachView appears in three places between the two
/// platforms (a macOS route, an iPhone tab root whose navigation bar is hidden, and an iPhone pillar
/// sheet), and a sheet is the one presentation that behaves the same in all three without depending on
/// an enclosing NavigationStack.
struct CoachSettingsView: View {
    @EnvironmentObject var coach: AICoachEngine
    @Environment(\.dismiss) private var dismiss

    /// Morning-brief settings, read from `CoachBriefScheduler` on init exactly as `CoachView` did
    /// before the split. This screen can now be the first to render them.
    @State private var briefEnabled: Bool = CoachBriefScheduler.isEnabled
    @State private var briefMinutes: Int = CoachBriefScheduler.timeMinutes
    @State private var briefGenerating = false
    @State private var briefStatus: String?

    /// The extra-instructions editor, collapsed until asked for.
    @State private var promptExpanded: Bool = false
    @State private var promptDraft: String = ""

    /// "What the coach reads", opened from its row.
    @State private var showData = false

    var body: some View {
        // Literals, not String(localized:): `title`/`subtitle` are LocalizedStringKey, which converts
        // from a string LITERAL only, so a String value does not type-check here. The catalog keys are
        // these exact English strings.
        //
        // Done goes in the scaffold's `trailing` slot rather than a .toolbar. ScreenScaffold is a bare
        // ScrollView with no NavigationStack, so a toolbar item presented in a sheet would render
        // nowhere, and a macOS sheet has no swipe-to-dismiss: that combination would leave this screen
        // with no way out. (#2206 is the same mistake in the other direction.)
        ScreenScaffold(title: "Coach settings",
                       subtitle: "What the coach may read, how it is told to answer, and when it writes to you.",
                       topBackground: liquidScaffoldSky(),
                       trailing: {
                           Button("Done") { dismiss() }
                               .buttonStyle(.plain)
                               .font(StrandFont.subhead)
                               .foregroundStyle(StrandPalette.accent)
                               .accessibilityLabel("Close coach settings")
                       }) {
            modelBar
            dataBar
            if coach.dataConsent && coach.provider == .gemini { multimodalChartBar }
            systemPromptBar
            morningBriefBar
        }
        .sheet(isPresented: $showData) {
            CoachDataView().environmentObject(coach)
        }
        // Opening this screen is the moment a stale catalogue is worth refreshing: a key exists here by
        // definition, and the picker above is about to be read. Rate-limited and silent on failure.
        .task { await coach.refreshModelsIfStale() }
    }

    /// Which model answers, and the control that refreshes the list of them.
    ///
    /// This lives HERE rather than on the setup card because of where a key exists. `setupCard` renders
    /// only while `isConfigured` is false, which for a cloud provider means no key is stored, and the
    /// Refresh control is `.disabled(!coach.hasKey)` — gated on having a key inside a screen that only
    /// appears when there is none. So for OpenAI, Anthropic and Gemini that button was permanently
    /// disabled and the live catalogue those three publish was unreachable. A key exists by definition
    /// on this screen, so the picker and the refresh both work.
    ///
    /// The PROVIDER deliberately stays on the setup card. A stored key records which provider it
    /// belongs to and is never sent anywhere else, so switching provider here would leave a key that
    /// cannot be used and a screen that cannot fix it. Kotlin twin: `CoachModelCard`.
    private var modelBar: some View {
        NoopCard(padding: 14, tint: StrandPalette.chargeColor) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(coach.provider.displayName) · \(coach.model)")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                    Spacer(minLength: 8)
                    Button {
                        Task { await coach.refreshModels() }
                    } label: {
                        Label("Refresh models", systemImage: "arrow.clockwise")
                            .font(StrandFont.footnote)
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(StrandPalette.accent)
                    .disabled(!coach.hasKey)
                    .accessibilityLabel("Refresh models from provider")
                }
                Picker("Model", selection: $coach.model) {
                    ForEach(coach.availableModels, id: \.self) { m in
                        Text(m).tag(m)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityLabel("Model")
            }
        }
    }

    /// The way to "What the coach reads", which holds the data-access switch and the summary opt-in
    /// (personal fork), so each switch is shown once. The line states the switch's position.
    private var dataBar: some View {
        Button {
            showData = true
        } label: {
            NoopCard(padding: 14, tint: StrandPalette.chargeColor) {
                HStack(spacing: 10) {
                    Image(systemName: coach.dataConsent ? "lock.open.fill" : "lock.fill")
                        .foregroundStyle(coach.dataConsent ? StrandPalette.accent : StrandPalette.textTertiary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("What the coach reads")
                            .font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                        Text(coach.dataConsent
                             ? "On: your data is sent with each question. See exactly what."
                             : "Off: the coach answers without any of your numbers.")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(StrandFont.footnote.weight(.semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// K11: Third opt-in — send a chart image alongside the text when using Gemini's multimodal
    /// API. Only shown when the provider is Gemini. OFF by default.
    private var multimodalChartBar: some View {
        NoopCard(padding: 14, tint: StrandPalette.chargeColor) {
            HStack(spacing: 10) {
                Image(systemName: coach.multimodalChartEnabled ? "photo.badge.checkmark" : "photo")
                    .foregroundStyle(coach.multimodalChartEnabled ? StrandPalette.accent : StrandPalette.textTertiary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Send chart image to Gemini")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                    Text(coach.multimodalChartEnabled
                         ? "On: a chart snapshot of your trends is sent with each question. Gemini can analyze the visual."
                         : "Off: only text is sent. Enable to let Gemini see your charts.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: $coach.multimodalChartEnabled)
                    .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                    .accessibilityLabel("Send chart image to Gemini")
            }
        }
    }

    /// The user's extra instructions, added to the coach's built-in role (personal fork: they no longer
    /// replace it). Collapsed by default; expanding reveals a TextEditor bound to the engine (edits persist
    /// to UserDefaults and take effect on the next message) plus a Clear control.
    private var systemPromptBar: some View {
        NoopCard(padding: 14, tint: StrandPalette.chargeColor) {
            VStack(alignment: .leading, spacing: promptExpanded ? 10 : 0) {
                Button {
                    withAnimation(StrandMotion.fade) {
                        promptExpanded.toggle()
                        if promptExpanded { promptDraft = coach.extraInstructions }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "text.alignleft")
                            .foregroundStyle(coach.hasExtraInstructions ? StrandPalette.accent : StrandPalette.textTertiary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Extra instructions")
                                .font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                            Text(coach.hasExtraInstructions
                                 ? "Added to the coach's built-in role in every reply."
                                 : "Added to the coach's built-in role. Takes effect on your next message.")
                                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: promptExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(StrandPalette.textTertiary)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(promptExpanded ? "Collapse extra instructions" : "Edit extra instructions")

                if promptExpanded {
                    TextEditor(text: $promptDraft)
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 140, maxHeight: 240)
                        .padding(8)
                        .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(StrandPalette.hairline, lineWidth: 1))
                        .onChangeCompat(of: promptDraft) { newValue in
                            coach.extraInstructions = newValue
                        }
                        .accessibilityLabel("Extra instructions editor")

                    HStack {
                        Spacer()
                        Button {
                            coach.clearExtraInstructions()
                            promptDraft = coach.extraInstructions
                        } label: {
                            Label("Clear", systemImage: "xmark.circle")
                                .font(StrandFont.footnote)
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(StrandPalette.accent)
                        .disabled(!coach.hasExtraInstructions)
                        .accessibilityLabel("Clear extra instructions")
                    }
                }
            }
        }
    }

    /// K5: the scheduled morning-brief notification settings — enable toggle, time-of-day picker, and an
    /// explicit "Generate now" button. Mirrors the `ScheduledDebugExport` settings row shape (TestCentreView).
    private var morningBriefBar: some View {
        NoopCard(padding: 14, tint: StrandPalette.chargeColor) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: briefEnabled ? "sunrise.fill" : "sunrise")
                        .foregroundStyle(briefEnabled ? StrandPalette.accent : StrandPalette.textTertiary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Morning brief").font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                        Text(briefEnabled
                             ? "A local notification with today's readiness + training plan, generated on-device each morning."
                             : "Off: nothing is generated or sent on a schedule.")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Toggle("", isOn: $briefEnabled)
                        .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                        .accessibilityLabel("Morning brief")
                }
                .onChangeCompat(of: briefEnabled) { on in
                    CoachBriefScheduler.setEnabled(on, generateBrief: { await coach.generateBrief() }) { outcome in
                        if outcome == .denied {
                            briefEnabled = false
                            briefStatus = "Notifications are off for NOOP — enable them in Settings first."
                        }
                    }
                }

                if briefEnabled {
                    Divider().overlay(StrandPalette.hairline)
                    HStack {
                        Text("Time").font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                        Spacer()
                        DatePicker("", selection: briefTimeBinding, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .accessibilityLabel("Morning brief time")
                    }
                    Text("At \(Platform.deviceNounPhrase == "Mac" ? "this time" : "or soon after"), NOOP will use your key to generate today's brief. Best-effort: \(Platform.deviceNounPhrase) decides exactly when a backgrounded app wakes.")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    NoopButton(briefGenerating ? "Generating…" : "Generate now", systemImage: "sparkles", kind: .secondary) {
                        generateBriefNow()
                    }
                    .disabled(briefGenerating)
                    if let briefStatus {
                        Text(briefStatus).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    }
                }
            }
        }
    }

    private var briefTimeBinding: Binding<Date> {
        Binding(
            get: {
                var c = DateComponents()
                c.hour = briefMinutes / 60
                c.minute = briefMinutes % 60
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                let m = (c.hour ?? 7) * 60 + (c.minute ?? 0)
                briefMinutes = m
                CoachBriefScheduler.setTimeMinutes(m, generateBrief: { await coach.generateBrief() })
            }
        )
    }

    private func generateBriefNow() {
        Task {
            briefGenerating = true
            briefStatus = nil
            defer { briefGenerating = false }
            let text = await CoachBriefScheduler.generateNow { await coach.generateBrief() }
            if let text {
                coach.appendGeneratedBrief(text)
            } else {
                briefStatus = "Couldn't generate a brief right now — check your key and data access."
            }
        }
    }
}
