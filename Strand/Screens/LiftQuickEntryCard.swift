import SwiftUI
import StrandDesign

// The quick-entry card (fork chantier 18, maquette 1 « Saisie rapide en séance »): the set coming up, in big,
// already filled in, so the usual set is ONE tap — « Set done ». The weight is the weight of the set before
// it (`LiftSessionEngine.carry`), the reps those of last time or the program's target, the rest the
// exercise's own, started by the tap.
//
// To correct a number: − and + move it by one step (the exercise's weight step, one rep), and a tap on the
// number opens a wheel, with no keyboard. The rest runs in the card with −15 s, +15 s and Skip. The other
// sets of the exercise stay listed under the card, where any of them can still be typed into.
//
// A pure view: every number comes in as a value and every action goes out as a closure, so it can be drawn
// without a session; `LiftSessionView` wires it.

struct LiftQuickEntryCard: View {

    struct Content: Equatable {
        /// "Set 2 of 4".
        var setNumber: Int
        var setCount: Int
        /// "60 × 8": what the exercise was last session, nil when it has none.
        var lastTime: String?
        /// The weight shown, already in the display unit ("62.5"), and its unit ("kg").
        var weight: String
        var weightUnit: String
        /// The reps shown, nil when nothing is known.
        var reps: Int?
        /// The exercise's step, already in the display unit ("2.5 kg").
        var step: String
        /// The session stands before its first set: the button starts it instead of recording it.
        var isWarmup: Bool
        /// A rest is running before this set (absolute end, unix seconds), nil otherwise.
        var restEndsAt: Int?
        /// Water logged since the session began (fork chantier 18, lot C), in ml; nil before the first glass.
        var waterMl: Int? = nil
    }

    struct Actions {
        var weight: (Int) -> Void
        var reps: (Int) -> Void
        var openWeightWheel: () -> Void
        var openRepsWheel: () -> Void
        var cycleStep: () -> Void
        var done: () -> Void
        var shortenRest: () -> Void
        var extendRest: () -> Void
        var skipRest: () -> Void
        /// « + glass » in the rest band: 25 cl into the water log.
        var addWater: () -> Void = {}
    }

    let content: Content
    let actions: Actions
    /// Turns the current unix second into the rest's seconds left — the session's clock, which stands
    /// still while it is paused.
    let restRemaining: (Int) -> Int

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
                Text(String(localized: "Set \(content.setNumber) of \(content.setCount)"))
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer(minLength: NoopMetrics.space2)
                if let last = content.lastTime {
                    Text(String(localized: "Last time: \(last)"))
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            HStack(spacing: NoopMetrics.space2) {
                field(title: Text("Weight"),
                      value: content.weight, unit: content.weightUnit,
                      open: actions.openWeightWheel, step: actions.weight)
                field(title: Text("Reps"),
                      value: content.reps.map(String.init) ?? "—", unit: nil,
                      open: actions.openRepsWheel, step: actions.reps)
            }

            Button(action: actions.cycleStep) {
                HStack(spacing: NoopMetrics.space1) {
                    Image(systemName: "dial.low")
                        .font(.system(size: 12, weight: .semibold))
                    Text(String(localized: "Step \(content.step)"))
                        .font(StrandFont.caption.weight(.semibold))
                }
                .foregroundStyle(StrandPalette.textSecondary)
                .padding(.horizontal, NoopMetrics.space3)
                .frame(minHeight: 32)
                .background(StrandPalette.surfaceInset, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Changes how far − and + move the weight of this exercise"))

            if let endsAt = content.restEndsAt {
                restBand(endsAt: endsAt)
            }

            Button(action: actions.done) {
                Group {
                    if content.isWarmup {
                        Text("Start first set")
                    } else {
                        Text("Set done")
                    }
                }
                .font(StrandFont.rounded(19, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 60)
            }
            .buttonStyle(.noopPrimary)
        }
        .padding(NoopMetrics.cardPadding)
        .background(StrandPalette.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
    }

    /// One number: its label, the number in big (a tap opens the wheel), and − / + under it.
    private func field(title: Text, value: String, unit: String?,
                       open: @escaping () -> Void, step: @escaping (Int) -> Void) -> some View {
        VStack(spacing: NoopMetrics.space2) {
            title
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
            Button(action: open) {
                HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.spaceHalf) {
                    Text(verbatim: value)
                        .font(StrandFont.number(40, weight: .bold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let unit {
                        Text(verbatim: unit)
                            .font(StrandFont.subhead.weight(.semibold))
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack(spacing: NoopMetrics.space2) {
                stepButton("minus", label: Text("Less")) { step(-1) }
                stepButton("plus", label: Text("More")) { step(1) }
            }
        }
        .padding(NoopMetrics.space2)
        .frame(maxWidth: .infinity)
        .background(StrandPalette.surfaceInset,
                    in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius - 4, style: .continuous))
    }

    private func stepButton(_ symbol: String, label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(StrandPalette.surfaceOverlay,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// The rest before this set, in amber, with what one tap does to it.
    private func restBand(endsAt: Int) -> some View {
        VStack(spacing: NoopMetrics.space2) {
        HStack(spacing: NoopMetrics.space2) {
            LiftRunningClock(seconds: restRemaining)
                .font(StrandFont.number(26, weight: .bold))
                .foregroundStyle(StrandPalette.metricAmber)
            Text(String(localized: "Rest before set \(content.setNumber)"))
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.metricAmber)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            restButton(Text("−15 s"), action: actions.shortenRest)
            restButton(Text("+15 s"), action: actions.extendRest)
            restButton(Text("Skip"), action: actions.skipRest)
        }
        .padding(.horizontal, NoopMetrics.space3)
        .padding(.vertical, NoopMetrics.space2)
        .background(StrandPalette.metricAmber.opacity(0.14),
                    in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius - 4, style: .continuous))
        waterRow
        }
    }

    /// « + glass » (fork chantier 18, lot C, maquette 4): one tap logs 25 cl, with the session's total so far.
    private var waterRow: some View {
        HStack(spacing: NoopMetrics.space2) {
            Image(systemName: "drop.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(StrandPalette.accent)
            if let ml = content.waterMl, ml > 0 {
                Text(String(localized: "\(ml / 10) cl this session"))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
            } else {
                Text("Water")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            Spacer(minLength: NoopMetrics.space2)
            Button(action: actions.addWater) {
                Text("+ glass")
                    .font(StrandFont.caption.weight(.semibold))
                    .foregroundStyle(StrandPalette.accent)
                    .padding(.horizontal, NoopMetrics.space3)
                    .frame(minHeight: 36)
                    .background(StrandPalette.accent.opacity(0.16), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Log a 25 cl glass of water"))
        }
    }

    private func restButton(_ label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label
                .font(StrandFont.caption.weight(.semibold))
                .foregroundStyle(StrandPalette.metricAmber)
                .lineLimit(1)
                .padding(.horizontal, NoopMetrics.space2)
                .frame(minHeight: 36)
                .background(StrandPalette.metricAmber.opacity(0.2),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// The wheel the quick-entry card opens on a tap on its number (fork chantier 18): no keyboard, the values
/// on the exercise's step for a weight, one by one for reps. « OK » keeps the value turned to; closing the
/// sheet any other way keeps the number as it was.
struct LiftNumberWheelSheet: View {
    let title: String
    let values: [Double]
    let format: (Double) -> String
    let initial: Double
    let onPick: (Double) -> Void
    /// For a weight: the exercise's step ("2.5 kg"), and what one tap on « Step » does — it keeps the next
    /// step and hands back the wheel's values and the new label. Nil for reps.
    var stepLabel: String? = nil
    var onCycleStep: (() -> (values: [Double], label: String))? = nil

    @State private var selection: Double = 0
    @State private var shown: [Double] = []
    @State private var shownStep: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: NoopMetrics.space3) {
            Text(verbatim: title)
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textPrimary)
                .padding(.top, NoopMetrics.space4)
            HStack(spacing: NoopMetrics.space3) {
                stepButton("minus", label: Text("Less")) { move(-1) }
                Picker(selection: $selection) {
                    ForEach(shown, id: \.self) { value in
                        Text(verbatim: format(value))
                            .font(StrandFont.number(24, weight: .semibold))
                            .tag(value)
                    }
                } label: {
                    Text(verbatim: title)
                }
                .labelsHidden()
                #if os(iOS)
                .pickerStyle(.wheel)
                #endif
                .frame(maxHeight: 180)
                stepButton("plus", label: Text("More")) { move(1) }
            }
            .padding(.horizontal, NoopMetrics.screenPadding)
            if let step = shownStep, let onCycleStep {
                Button {
                    let next = onCycleStep()
                    shown = next.values
                    shownStep = next.label
                    selection = Self.nearest(selection, in: next.values)
                } label: {
                    Text(String(localized: "Step \(step)"))
                        .font(StrandFont.caption.weight(.semibold))
                        .foregroundStyle(StrandPalette.textSecondary)
                        .padding(.horizontal, NoopMetrics.space3)
                        .frame(minHeight: 32)
                        .background(StrandPalette.surfaceRaised, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Button {
                onPick(selection)
                dismiss()
            } label: {
                Text("OK").frame(maxWidth: .infinity)
            }
            .buttonStyle(.noopPrimary)
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.bottom, NoopMetrics.space4)
        }
        .background(StrandPalette.surfaceBase)
        #if os(iOS)
        .presentationDetents([.height(stepLabel == nil ? 340 : 390)])
        .presentationDragIndicator(.visible)
        #else
        .frame(width: 360, height: 390)
        #endif
        .onAppear {
            shown = values
            shownStep = stepLabel
            selection = Self.nearest(initial, in: values)
        }
    }

    /// One value up or down the wheel: one step of the exercise for a weight, one rep for reps.
    private func move(_ offset: Int) {
        guard let index = shown.firstIndex(of: selection) else { return }
        let next = min(max(0, index + offset), shown.count - 1)
        selection = shown[next]
    }

    private static func nearest(_ value: Double, in values: [Double]) -> Double {
        values.min(by: { abs($0 - value) < abs($1 - value) }) ?? value
    }

    private func stepButton(_ symbol: String, label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(width: 52, height: 52)
                .background(StrandPalette.surfaceRaised, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
