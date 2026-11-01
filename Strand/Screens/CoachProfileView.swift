import SwiftUI
import StrandDesign

/// "What the coach should know about you" (personal fork): the body profile the coach reads, shown
/// read-only because Settings › Profile is where it is edited, then what the user tells the coach about
/// their training (`CoachProfile`). Every change is saved as it is made and rides the next question.
///
/// Presented as a sheet from the coach menu and from "What the coach reads", like `CoachSettingsView`
/// and for the same reason: the coach appears in places with and without a navigation stack.
struct CoachProfileView: View {
    @EnvironmentObject var coach: AICoachEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScreenScaffold(title: "What the coach should know about you",
                       subtitle: "Sent with every question. Everything is optional.",
                       topBackground: liquidScaffoldSky(),
                       trailing: {
                           Button("Done") { dismiss() }
                               .buttonStyle(.plain)
                               .font(StrandFont.subhead)
                               .foregroundStyle(StrandPalette.accent)
                       }) {
            bodySection
            goalSection
            rhythmSection
            equipmentSection
            textSection(title: "PAIN OR CONSTRAINTS",
                        placeholder: "e.g. right shoulder sensitive on overhead press",
                        text: $coach.coachProfile.constraints)
            textSection(title: "ANYTHING ELSE",
                        placeholder: "e.g. football on Sundays, I train in the evening",
                        text: $coach.coachProfile.other)
            Label("Saved on this device only.", systemImage: "lock.fill")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
        }
    }

    // MARK: Body profile (read-only)

    @ViewBuilder
    private var bodySection: some View {
        CoachSectionTitle("FROM YOUR NOOP PROFILE")
        NoopCard(padding: 14, tint: StrandPalette.chargeColor) {
            VStack(alignment: .leading, spacing: 0) {
                if let fiche = coach.bodyFiche {
                    row("Age", String(localized: "\(fiche.age) years"), stored: true)
                    divider
                    row("Sex", CoachProfileText.sex(fiche.sex), stored: fiche.sexStored)
                    divider
                    row("Height", "\(Int(fiche.heightCm.rounded())) cm", stored: fiche.heightStored)
                    divider
                    row("Weight", LiftFormat.trim((fiche.weightKg * 10).rounded() / 10) + " kg",
                        stored: fiche.weightStored)
                    divider
                    row("Max HR", "\(fiche.hrMax) bpm", stored: true,
                        note: fiche.hrMaxSetByUser ? nil : String(localized: "estimated"))
                    divider
                }
                Text("Change these in Settings › Profile.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .padding(.top, coach.bodyFiche == nil ? 0 : 10)
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
    }

    private func row(_ label: LocalizedStringKey, _ value: String, stored: Bool, note: String? = nil) -> some View {
        HStack(spacing: 8) {
            Text(label).font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
            Spacer(minLength: 8)
            Text(value).font(StrandFont.bodyNumber).foregroundStyle(StrandPalette.textPrimary)
            if let suffix = note ?? (stored ? nil : String(localized: "not entered")) {
                Text("· " + suffix).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    // MARK: Goal

    @ViewBuilder
    private var goalSection: some View {
        CoachSectionTitle("GOAL")
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(CoachProfile.Goal.allCases) { goal in
                CoachChip(goal.label, selected: coach.coachProfile.goal == goal) {
                    coach.coachProfile.goal = coach.coachProfile.goal == goal ? nil : goal
                }
            }
        }
    }

    // MARK: Rhythm

    @ViewBuilder
    private var rhythmSection: some View {
        CoachSectionTitle("RHYTHM")
        NoopCard(padding: 14, tint: StrandPalette.chargeColor) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sessions per week").font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                CoachSegments(choices: CoachProfile.sessionChoices, selection: $coach.coachProfile.sessionsPerWeek,
                              label: { "\($0)" })
                    .accessibilityLabel(Text("Sessions per week"))
                Text("Session length").font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                    .padding(.top, 6)
                CoachSegments(choices: CoachProfile.minuteChoices, selection: $coach.coachProfile.sessionMinutes,
                              label: { "\($0)" }, unit: String(localized: "min"))
                    .accessibilityLabel(Text("Session length"))
            }
        }
    }

    // MARK: Equipment

    @ViewBuilder
    private var equipmentSection: some View {
        CoachSectionTitle("EQUIPMENT")
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
            ForEach(CoachProfile.Equipment.allCases) { item in
                CoachChip(item.label, selected: coach.coachProfile.equipment.contains(item)) {
                    coach.coachProfile.equipment = coach.coachProfile.toggled(item)
                }
            }
        }
        VStack(alignment: .leading, spacing: 6) {
            Text("Details").font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            CoachTextField(placeholder: "e.g. no leg press", text: $coach.coachProfile.equipmentNote, lines: 1...2)
        }
    }

    @ViewBuilder
    private func textSection(title: LocalizedStringKey, placeholder: LocalizedStringKey,
                             text: Binding<String>) -> some View {
        CoachSectionTitle(title)
        CoachTextField(placeholder: placeholder, text: text, lines: 3...6)
    }
}

/// Display text for the profile's stored tokens.
enum CoachProfileText {
    /// The `ProfileStore.sex` token as a label; an unknown token is shown as stored.
    static func sex(_ token: String) -> String {
        switch token.lowercased() {
        case "male": return String(localized: "Male")
        case "female": return String(localized: "Female")
        case "nonbinary", "non-binary": return String(localized: "Non-binary")
        default: return token
        }
    }
}

// MARK: - Small pieces shared by the coach's sheets

/// The overline above a group, in the coach sheets' style.
struct CoachSectionTitle: View {
    private let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(StrandFont.overline)
            .tracking(1.6)
            .foregroundStyle(StrandPalette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A selectable chip: tapped again, it is deselected.
struct CoachChip: View {
    private let title: String
    private let selected: Bool
    private let action: () -> Void

    init(_ title: String, selected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.selected = selected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if selected {
                    Image(systemName: "checkmark").font(StrandFont.footnote.weight(.bold)).accessibilityHidden(true)
                }
                Text(title).font(StrandFont.subhead.weight(selected ? .semibold : .regular)).lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(selected ? StrandPalette.accent : StrandPalette.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 12)
            .background(Capsule().fill(selected ? StrandPalette.accent.opacity(0.14) : StrandPalette.surfaceInset))
            .overlay(Capsule().strokeBorder(selected ? StrandPalette.accent.opacity(0.6) : StrandPalette.hairline,
                                            lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A row of numbers to pick one from; tapping the picked one clears it, since every field is optional.
struct CoachSegments: View {
    let choices: [Int]
    @Binding var selection: Int?
    let label: (Int) -> String
    var unit: String? = nil

    var body: some View {
        HStack(spacing: 3) {
            ForEach(choices, id: \.self) { value in
                let picked = selection == value
                Button {
                    selection = picked ? nil : value
                } label: {
                    Text(label(value))
                        .font(StrandFont.bodyNumber.weight(picked ? .bold : .regular))
                        .foregroundStyle(picked ? StrandPalette.textPrimary : StrandPalette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(picked ? StrandPalette.surfaceOverlay : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(picked ? .isSelected : [])
            }
            if let unit {
                Text(unit).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    .padding(.horizontal, 6)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(StrandPalette.surfaceInset))
    }
}

/// A multi-line text field in the coach sheets' style.
struct CoachTextField: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    let lines: ClosedRange<Int>

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .lineLimit(lines)
            .font(StrandFont.body)
            .foregroundStyle(StrandPalette.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(StrandPalette.surfaceInset))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(StrandPalette.hairline, lineWidth: 1))
    }
}
