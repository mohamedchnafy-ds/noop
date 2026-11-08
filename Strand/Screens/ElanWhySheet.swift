import SwiftUI
import StrandDesign

// MARK: - Élan · Mon pourquoi (personal fork, chantier 10, PR B)
//
// The editor of the wearer's own words (`ElanWhy`): the text, four prompts a tap adds, the switch that lets
// the Coach read it (off by default). Written on a motivated day, shown back by Élan on the days without.

struct ElanWhySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ElanWhy.text() ?? ""
    @State private var coachCanRead: Bool = ElanWhy.coachCanRead()
    @FocusState private var focused: Bool

    /// The four prompts, in the app's language.
    private var prompts: [String] {
        [String(localized: "How I want to feel in six months"),
         String(localized: "What I want to be able to do"),
         String(localized: "What I do not want to live through again"),
         String(localized: "Who I do it for")]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Write it on a day you feel motivated. Élan shows it back to you on the days without.")
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Why you are doing this")
                        .font(StrandFont.footnote.weight(.medium))
                        .foregroundStyle(StrandPalette.textSecondary)
                    ZStack(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("In your own words. One sentence is enough.")
                                .font(StrandFont.title2)
                                .foregroundStyle(StrandPalette.textTertiary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 18)
                        }
                        TextEditor(text: $text)
                            .font(StrandFont.title2)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 170)
                            .padding(10)
                            .focused($focused)
                            .accessibilityLabel(Text("Your why"))
                    }
                    .background(StrandPalette.surfaceRaised,
                                in: RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius, style: .continuous))
                    Text("To help you (a tap adds it to the text)")
                        .font(StrandFont.footnote.weight(.medium))
                        .foregroundStyle(StrandPalette.textSecondary)
                    promptChips
                    NoopCard(padding: 0) {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(StrandPalette.textPrimary)
                                .frame(width: 30, height: 30)
                                .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("The Coach may read it")
                                    .font(StrandFont.body)
                                    .foregroundStyle(StrandPalette.textPrimary)
                                Text("to bring it up when you drift")
                                    .font(StrandFont.footnote)
                                    .foregroundStyle(StrandPalette.textSecondary)
                            }
                            Spacer()
                            Toggle("", isOn: $coachCanRead)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .tint(StrandPalette.switchOn)
                                .accessibilityLabel(Text("The Coach may read my why"))
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 60)
                    }
                    Text("It appears at the top of Élan the day after a missed session and after three days without one. It stays on \(Platform.deviceNounPhrase) and in your .noopbak backup.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(NoopMetrics.pagePadding)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle(Text("My why"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        ElanWhy.setText(text)
                        ElanWhy.setCoachCanRead(coachCanRead)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .tint(StrandPalette.accent)
    }

    private var promptChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(prompts.enumerated()), id: \.offset) { _, prompt in
                Button {
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        text = prompt + " : "
                    } else {
                        text = text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n" + prompt + " : "
                    }
                    focused = true
                } label: {
                    Text(verbatim: prompt)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 38)
                        .background(StrandPalette.surfaceInset, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(LiquidPressStyle())
            }
        }
    }
}
