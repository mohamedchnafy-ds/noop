import SwiftUI
import StrandDesign

/// "What the coach reads" (personal fork): the data-access switch, what each question carries, the
/// summary opt-in, what never leaves the device, and the exact text a question would carry right now.
///
/// It holds the two consent switches that used to sit in `CoachSettingsView`, so each is shown once.
/// "The exact text" is read through `AICoachEngine.questionContext()`, the funnel `send` itself uses, so
/// the preview is the request's own context rather than a description of it.
struct CoachDataView: View {
    @EnvironmentObject var coach: AICoachEngine
    @Environment(\.dismiss) private var dismiss

    @State private var showProfile = false
    @State private var exactText: CoachExactText?
    @State private var loadingExact = false

    var body: some View {
        ScreenScaffold(title: "What the coach reads",
                       subtitle: "Sent to \(coach.provider.displayName) with each question, and never without one.",
                       topBackground: liquidScaffoldSky(),
                       trailing: {
                           Button("Done") { dismiss() }
                               .buttonStyle(.plain)
                               .font(StrandFont.subhead)
                               .foregroundStyle(StrandPalette.accent)
                       }) {
            consentCard
            CoachSectionTitle("ALWAYS SENT")
            alwaysSentCard
            if !coach.dataConsent {
                Text("Only what you told the coach is sent while “Use my data” is off.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            CoachSectionTitle("NEVER SENT")
            Text("Raw beats, second-by-second readings, your location. Your key only goes to \(coach.provider.displayName).")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            NoopButton(loadingExact ? "Preparing…" : "See the exact text sent", systemImage: "doc.text",
                       kind: .secondary, fullWidth: true) {
                loadExactText()
            }
            .disabled(loadingExact)
            .padding(.top, 4)
        }
        .sheet(isPresented: $showProfile) {
            CoachProfileView().environmentObject(coach)
        }
        .sheet(item: $exactText) { text in
            CoachExactTextView(text: text.value)
        }
    }

    // MARK: Consent

    private var consentCard: some View {
        NoopCard(padding: 14, tint: StrandPalette.chargeColor) {
            HStack(spacing: 12) {
                CoachDataIcon(symbol: coach.dataConsent ? "lock.open.fill" : "lock.fill",
                              tint: coach.dataConsent ? StrandPalette.accent : StrandPalette.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use my data").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                    Text("Off: the coach answers without any of your numbers.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: $coach.dataConsent)
                    .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                    .accessibilityLabel("Use my data")
            }
        }
    }

    // MARK: What a question carries

    private var alwaysSentCard: some View {
        NoopCard(padding: 14, tint: StrandPalette.chargeColor) {
            VStack(alignment: .leading, spacing: 0) {
                CoachDataRow(symbol: "person.fill", tint: StrandPalette.textSecondary, title: "Profile",
                             detail: profileSummary)
                    .opacity(coach.dataConsent ? 1 : 0.45)
                divider
                // Sent with or without data access: the user wrote it for the coach.
                Button {
                    showProfile = true
                } label: {
                    CoachDataRow(symbol: "scope", tint: StrandPalette.accent,
                                 title: "What you told the coach", detail: coach.coachProfile.summary,
                                 chevron: true)
                }
                .buttonStyle(.plain)
                Group {
                    dailyRows
                    divider
                    trainingRows
                }
                .opacity(coach.dataConsent ? 1 : 0.45)
                .disabled(!coach.dataConsent)
            }
        }
    }

    /// Today, the normals, sleep and the last 14 days.
    @ViewBuilder
    private var dailyRows: some View {
        divider
        CoachDataRow(symbol: "square.grid.2x2.fill", tint: StrandPalette.chargeColor, title: "Today",
                     detail: String(localized: "Charge, Effort, Rest, sleep stages, resting HR, HRV, SpO2, respiration, temperature, steps, calories"))
        divider
        CoachDataRow(symbol: "waveform.path.ecg", tint: StrandPalette.liquidHeart, title: "Your normals",
                     detail: String(localized: "Resting HR, HRV and sleep over 30 nights, and today's gap"))
        divider
        CoachDataRow(symbol: "moon.fill", tint: StrandPalette.restBright, title: "Sleep",
                     detail: String(localized: "Debt, sleep need, usual wake-up, suggested bedtime, naps"))
        divider
        CoachDataRow(symbol: "calendar", tint: StrandPalette.textSecondary, title: "Last 14 days",
                     detail: String(localized: "One line per day, and today's stress"))
    }

    /// The Lift Log, workouts and the summary opt-in.
    @ViewBuilder
    private var trainingRows: some View {
        CoachDataRow(symbol: "dumbbell.fill", tint: StrandPalette.effortColor, title: "Lift Log",
                     detail: String(localized: "8 weeks of sets, programs, Progression statuses"))
        divider
        CoachDataRow(symbol: "figure.run", tint: StrandPalette.metricAmber, title: "Workouts",
                     detail: String(localized: "The last 6 in 30 days: sport, duration, heart rate, calories"))
        divider
        HStack(spacing: 12) {
            CoachDataRow(symbol: "book.closed.fill", tint: StrandPalette.textSecondary,
                         title: "Patterns and Lab Book",
                         detail: String(localized: "A summary only, never the readings"))
            Toggle("", isOn: $coach.includeOnDeviceSignals)
                .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                .accessibilityLabel("Also share my patterns and Lab Book with the coach")
        }
    }

    private var divider: some View {
        Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
    }

    /// "30 years · Male · 178 cm · 80 kg · Max HR 187", from the resolver the context uses.
    private var profileSummary: String {
        guard let b = coach.bodyFiche else { return String(localized: "Age, sex, height, weight, max HR") }
        let age = String(localized: "\(b.age) years")
        let height = "\(Int(b.heightCm.rounded())) cm"
        let weight = LiftFormat.trim((b.weightKg * 10).rounded() / 10) + " kg"
        let hrMax = String(localized: "Max HR") + " \(b.hrMax)"
        return [age, CoachProfileText.sex(b.sex), height, weight, hrMax].joined(separator: " · ")
    }

    private func loadExactText() {
        loadingExact = true
        Task {
            let text = await coach.questionContext()
            exactText = CoachExactText(value: text)
            loadingExact = false
        }
    }
}

/// One line of the "Always sent" card.
private struct CoachDataRow: View {
    let symbol: String
    let tint: Color
    let title: LocalizedStringKey
    let detail: String
    var chevron = false

    var body: some View {
        HStack(spacing: 12) {
            CoachDataIcon(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                Text(detail).font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(StrandFont.footnote.weight(.semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct CoachDataIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(StrandFont.subhead.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(tint.opacity(0.16), in: Circle())
            .accessibilityHidden(true)
    }
}

/// The context text handed to the exact-text sheet.
struct CoachExactText: Identifiable {
    let id = UUID()
    let value: String
}

/// The context a question would carry right now, selectable and copyable.
private struct CoachExactTextView: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScreenScaffold(title: "Exact text sent",
                       subtitle: "Sent with your question, after the coach's built-in instructions.",
                       topBackground: liquidScaffoldSky(),
                       trailing: {
                           Button("Done") { dismiss() }
                               .buttonStyle(.plain)
                               .font(StrandFont.subhead)
                               .foregroundStyle(StrandPalette.accent)
                       }) {
            NoopButton("Copy", systemImage: "doc.on.doc", kind: .secondary) {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                #else
                UIPasteboard.general.string = text
                #endif
            }
            NoopCard(padding: 14) {
                Text(text)
                    .font(StrandFont.mono)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
