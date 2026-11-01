import SwiftUI
import StrandDesign

/// The session the Coach proposes, as a card under its reply (personal fork, Coach mockup 3): the lines
/// done on their own, the supersets boxed with their A1/A2 badges and the rest after the round, then
/// "Add to Lift Log" and "Start". Nothing is stored until one of them is tapped.
struct CoachSessionCard: View {
    let proposal: CoachSessionProposal
    let system: UnitSystem
    /// Running an action (the store write, the plan): the buttons wait.
    let busy: Bool
    let onAdd: () -> Void
    /// Nil where the Lift Log session cannot run (the Mac).
    let onStart: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Text(proposal.name)
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textPrimary)
                .padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
            Text(summary)
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(proposal.blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .single(let index): singleLine(index)
                    case let .superset(label, range): supersetBox(label: label, range: range)
                    }
                }
            }
            .padding(.top, 10)
            actions
                .padding(.top, 14)
        }
        .padding(16)
        .background(NoopPanelSurface(cornerRadius: 24))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Proposed session: \(proposal.name)"))
    }

    // MARK: Parts

    private var header: some View {
        HStack {
            Label {
                Text("Proposed session")
                    .font(StrandFont.overline)
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(StrandPalette.textSecondary)
            } icon: {
                Image(systemName: "dumbbell.fill")
                    .font(StrandFont.caption.weight(.semibold))
                    .foregroundStyle(StrandPalette.effortColor)
            }
            Spacer(minLength: 8)
            if let minutes = proposal.minutes {
                Text("≈ \(minutes) min")
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    /// "2 on their own · 2 supersets · 17 sets", leaving out a count of zero.
    private var summary: String {
        let counts = proposal.counts
        var parts: [String] = []
        if counts.singles > 0 {
            parts.append(counts.singles == 1 ? String(localized: "1 exercise on its own")
                                             : String(localized: "\(counts.singles) exercises on their own"))
        }
        if counts.supersets > 0 {
            parts.append(counts.supersets == 1 ? String(localized: "1 superset")
                                               : String(localized: "\(counts.supersets) supersets"))
        }
        parts.append(String(localized: "\(counts.sets) sets"))
        return parts.joined(separator: " · ")
    }

    private func singleLine(_ index: Int) -> some View {
        let line = proposal.lines[index]
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Circle()
                    .strokeBorder(StrandPalette.textTertiary, lineWidth: 1.5)
                    .frame(width: 7, height: 7)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                lineRow(line)
            }
            .frame(minHeight: 30)
            if let rest = line.restSec {
                Text("On its own · rest \(CoachSessionProposal.restText(rest))")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .padding(.leading, 38)
            }
        }
    }

    private func supersetBox(label: String, range: Range<Int>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Superset \(label)")
                    .font(StrandFont.overline)
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(StrandPalette.textSecondary)
                Spacer(minLength: 8)
                if let rest = proposal.lines[range.upperBound - 1].restSec,
                   let last = proposal.position(of: range.upperBound - 1) {
                    Text("rest \(CoachSessionProposal.restText(rest)) after \(last)")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
            .frame(minHeight: 18)
            ForEach(Array(range), id: \.self) { index in
                HStack(spacing: 10) {
                    Text(proposal.position(of: index) ?? "")
                        .font(StrandFont.caption.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .frame(width: 28, height: 22)
                        .background(StrandPalette.surfaceRaised,
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    lineRow(proposal.lines[index])
                }
                .frame(minHeight: 32)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(StrandPalette.hairline, lineWidth: 1))
    }

    private func lineRow(_ line: CoachSessionProposal.Line) -> some View {
        HStack(spacing: 8) {
            Text(line.exercise)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 0) {
                Text(CoachSessionProposal.target(line))
                if let kg = line.weightKg {
                    Text(" · ")
                    Text(weight(kg)).fontWeight(.semibold)
                }
            }
            .font(StrandFont.subhead.monospacedDigit())
            .foregroundStyle(StrandPalette.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    private func weight(_ kg: Double) -> String {
        LiftFormat.trim(LiftFormat.display(fromKilograms: kg, system: system)) + " " + LiftFormat.weightUnit(system)
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 8) {
            if proposal.programId == nil {
                NoopButton("Add to Lift Log", systemImage: "plus", kind: .primary, fullWidth: true, action: onAdd)
                    .disabled(busy)
                    .layoutPriority(1.45)
            } else {
                Label("In your Lift Log", systemImage: "checkmark")
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            if let onStart {
                NoopButton("Start", systemImage: "play.fill", kind: .secondary, fullWidth: true, action: onStart)
                    .disabled(busy)
            }
        }
    }
}
