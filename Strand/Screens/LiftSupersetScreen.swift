import SwiftUI
import StrandDesign
import WhoopStore

// The guided superset screens (personal fork): the block READY to start, the round IN PROGRESS and the
// REST between rounds — one full screen each, one obvious action each. Which one, and every number on
// it, comes from `LiftSupersetGuide`; this file only draws it.
//
// PURE BY CONSTRUCTION. Nothing here reads the session, the strap or the store: the guide and the
// actions come in, and so do the four parts that are live or editable — the number fields, the row of
// live tiles, the strap card and the next round's numbers. That keeps the session's typing logic in
// one place (`LiftSessionView`), keeps every live number in a small view of its own that redraws alone
// (`LiftLiveReadouts.swift`), and lets the screens be rendered to an image with stand-ins for a visual
// check against the mockups (`LiftSupersetRenderTests`).
//
// The layout follows the validated mockups ("NOOP – Superset guidé") measure for measure — type sizes
// and weights, radii, gaps — in NOOP's tokens: surfaces, text, the Effort blue the superset already
// wears, amber for rest, the heart-rate rose, green for done.

/// Which number of a set a field edits.
enum LiftGuideField: Hashable {
    case weight, reps
}

/// What the row of live tiles shows.
enum LiftGuideVitals: Equatable {
    /// Heart rate and zone, Effort, energy.
    case working
    /// Heart rate coming down, how long the round just done took, Effort.
    case resting(lastRoundSec: Int?)
}

struct LiftSupersetScreen: View {

    struct Actions {
        var start: () -> Void
        var roundDone: () -> Void
        var skipRest: () -> Void
        var addRest: () -> Void
        /// +1 or −1 round.
        var changeRounds: (Int) -> Void
        /// The block's new rest, in seconds.
        var setRest: (Int) -> Void
        var endBlock: () -> Void
        var showSession: () -> Void
        var undo: () -> Void
        var finish: () -> Void
    }

    let guide: LiftSupersetGuide
    let sessionStart: Int
    let lastTime: LiftSupersetGuide.LastTime?
    let unitSystem: UnitSystem
    let canUndo: Bool
    /// The editable number of a set — a text field in the app. Styled here, inside its chip.
    let field: (LiftSlot, LiftGuideField) -> AnyView
    let vitals: (LiftGuideVitals) -> AnyView
    let strapCard: () -> AnyView
    /// A set's numbers as "40 kg × 10" — typed, else grey.
    let preview: (LiftSlot) -> String
    /// The load step-up proposed for an exercise, already formatted ("↑ 42.5 kg"), if any.
    let suggestion: (String) -> String?
    let actions: Actions
    /// Off only for the render check: a scroll view is drawn by the platform and does not render to an image.
    var scrolls = true

    @State private var showingMenu = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if scrolls {
                    ScrollView { top }
                } else {
                    top
                    Spacer(minLength: 0)
                }
            }
            bottom
                .padding(.horizontal, NoopMetrics.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 8)
        }
        .background(StrandPalette.surfaceBase)
        .confirmationDialog(String(localized: "Superset \(guide.letter)"), isPresented: $showingMenu,
                            titleVisibility: .hidden) {
            Button(String(localized: "Whole session")) { actions.showSession() }
            if canUndo {
                Button(String(localized: "Undo")) { actions.undo() }
            }
            Button(String(localized: "Finish session")) { actions.finish() }
        }
    }

    private var top: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch guide.phase {
            case .ready(let restEndsAt): readyTop(restEndsAt: restEndsAt)
            case .working(let startedAt): workingTop(startedAt: startedAt)
            case .resting(let startedAt, let endsAt): restingTop(startedAt: startedAt, endsAt: endsAt)
            }
        }
        .padding(.horizontal, NoopMetrics.screenPadding)
        .padding(.top, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var bottom: some View {
        switch guide.phase {
        case .ready: readyBottom
        case .working: workingBottom
        case .resting: restingBottom
        }
    }

    // MARK: - Ready

    private func readyTop(restEndsAt: Int?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            readyHeader
            readyIntro(restEndsAt: restEndsAt)
            membersCard(nameSize: 18, chipHeight: 44, spacing: 14, detailed: true)
                .padding(.top, 20)
            readySteppers
                .padding(.top, 14)
            strapCard()
                .padding(.top, 14)
            if let lastTime {
                lastTimeBlock(lastTime)
                    .padding(.top, 14)
            }
        }
    }

    private var readyHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(String(localized: "Superset \(guide.letter)"))
                .font(StrandFont.rounded(30, weight: .heavy))
                .tracking(-0.5)
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            Text(String(localized: "Block \(guide.blockNumber) / \(guide.blockCount)"))
                .font(StrandFont.rounded(13, weight: .regular))
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1)
            menuButton
        }
    }

    private func readyIntro(restEndsAt: Int?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Chain the \(guide.members.count) exercises, then rest. Double-tap the strap = set done."))
                .font(StrandFont.rounded(14, weight: .regular))
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let restEndsAt {
                restPill(endsAt: restEndsAt)
            }
        }
        .padding(.top, 4)
    }

    private var readySteppers: some View {
        HStack(spacing: 12) {
            stepperTile(label: String(localized: "Sets"), value: "\(guide.rounds)",
                        canDecrease: guide.canRemoveRound, canIncrease: guide.canAddRound,
                        decreaseLabel: String(localized: "One set fewer"),
                        increaseLabel: String(localized: "One more set"),
                        decrease: { actions.changeRounds(-1) },
                        increase: { actions.changeRounds(1) })
            stepperTile(label: String(localized: "Rest between sets"), value: LiftFormat.duration(guide.restSec),
                        canDecrease: guide.restSec > 0,
                        canIncrease: guide.restSec < LiftSessionEngine.maxRestSec,
                        decreaseLabel: String(localized: "15 seconds less"),
                        increaseLabel: String(localized: "15 seconds more"),
                        decrease: { actions.setRest(max(0, guide.restSec - LiftSessionController.restStepSec)) },
                        increase: { actions.setRest(guide.restSec + LiftSessionController.restStepSec) })
        }
    }

    private func lastTimeBlock(_ last: LiftSupersetGuide.LastTime) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Last time · \(last.date.formatted(.dateTime.day().month(.abbreviated)))"))
            Text(lastTimeSummary(last))
        }
        .font(StrandFont.rounded(13, weight: .regular))
        .foregroundStyle(StrandPalette.textSecondary)
    }

    /// The block's exercises in one card, linked by the chain that says there is no rest between them.
    private func membersCard(nameSize: CGFloat, chipHeight: CGFloat, spacing: CGFloat,
                             detailed: Bool) -> some View {
        VStack(spacing: spacing) {
            ForEach(Array(guide.members.enumerated()), id: \.element.index) { position, member in
                if position > 0 { chainedDivider(withWord: detailed) }
                memberRow(member, round: guide.round, nameSize: nameSize, chipHeight: chipHeight,
                          detailed: detailed)
            }
        }
        .padding(16)
        .background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var readyBottom: some View {
        Button(action: actions.start) {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                    .font(.system(size: 20, weight: .bold))
                Text(guide.rounds == 1 ? String(localized: "Start · 1 set")
                                       : String(localized: "Start · \(guide.rounds) sets"))
            }
            .font(StrandFont.rounded(20, weight: .heavy))
            .foregroundStyle(StrandPalette.surfaceBase)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(StrandPalette.effortColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(LiftGuidePressStyle())
    }

    /// The rest still running from the block before, so the ready screen does not hide a clock that is
    /// counting.
    private func restPill(endsAt: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "timer")
                .font(.system(size: 12, weight: .bold))
            Text("Rest period")
            LiftRunningClock { max(0, endsAt - $0) }
        }
        .font(StrandFont.rounded(13, weight: .bold))
        .foregroundStyle(StrandPalette.metricAmber)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(StrandPalette.metricAmber.opacity(0.16), in: Capsule())
    }

    private func stepperTile(label: String, value: String, canDecrease: Bool, canIncrease: Bool,
                             decreaseLabel: String, increaseLabel: String,
                             decrease: @escaping () -> Void, increase: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            overline(label)
            HStack(spacing: 8) {
                stepButton("minus", enabled: canDecrease, label: decreaseLabel, action: decrease)
                Text(value)
                    .font(StrandFont.rounded(30, weight: .heavy))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                stepButton("plus", enabled: canIncrease, label: increaseLabel, action: increase)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func stepButton(_ symbol: String, enabled: Bool, label: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(enabled ? StrandPalette.textPrimary : StrandPalette.textTertiary)
                .frame(width: 40, height: 40)
                .background(StrandPalette.hairline, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(LiftGuidePressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .accessibilityLabel(label)
    }

    /// "3 × (40 kg × 10 + 60 kg × 10) · rest 2:00 · 9 min".
    private func lastTimeSummary(_ last: LiftSupersetGuide.LastTime) -> String {
        let unit = LiftFormat.weightUnit(unitSystem)
        let members = last.numbers.map { numbers -> String in
            let weight = numbers.weightKg.map {
                LiftFormat.trim(LiftFormat.display(fromKilograms: $0, system: unitSystem)) + " " + unit
            }
            switch (weight, numbers.reps) {
            case (let w?, let r?): return "\(w) × \(r)"
            case (let w?, nil): return w
            case (nil, let r?): return String(localized: "\(r) reps")
            case (nil, nil): return "—"
            }
        }
        var parts = ["\(last.rounds) × (\(members.joined(separator: " + ")))"]
        if let rest = last.restSec { parts.append(String(localized: "rest \(LiftFormat.duration(rest))")) }
        if let duration = last.durationSec, duration >= 60 {
            parts.append(String(localized: "\(duration / 60) min"))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Set in progress

    private func workingTop(startedAt: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            compactHeader
            workingClock(startedAt: startedAt)
                .frame(maxWidth: .infinity)
                .padding(.top, 18)
            membersCard(nameSize: 20, chipHeight: 40, spacing: 12, detailed: false)
                .padding(.top, 22)
            vitals(.working)
                .padding(.top, 14)
            hint(String(localized: "Double-tap the strap or the button when \(guide.members.last?.tag ?? "") is done"))
                .padding(.top, 12)
        }
    }

    private func workingClock(startedAt: Int) -> some View {
        VStack(spacing: 2) {
            Text("Set in progress")
                .font(StrandFont.rounded(13, weight: .bold))
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(StrandPalette.effortColor)
            LiftRunningClock { $0 - startedAt }
                .font(StrandFont.rounded(72, weight: .heavy))
                .tracking(-3)
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            LiftRoundSegments(rounds: guide.rounds, done: guide.doneRounds, current: guide.round)
                .padding(.top, 10)
            roundCaption
                .font(StrandFont.rounded(14, weight: .regular))
                .foregroundStyle(StrandPalette.textSecondary)
                .padding(.top, 6)
        }
    }

    private var workingBottom: some View {
        VStack(spacing: 10) {
            Button(action: actions.roundDone) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 22, weight: .heavy))
                    Text(guide.restSec > 0 ? String(localized: "Set done · rest \(LiftFormat.duration(guide.restSec))")
                                           : String(localized: "Set done"))
                }
                .font(StrandFont.rounded(20, weight: .heavy))
                .foregroundStyle(StrandPalette.surfaceBase)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 72)
                .background(StrandPalette.effortColor, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(LiftGuidePressStyle())

            HStack(spacing: 10) {
                secondaryButton(String(localized: "Whole session"), action: actions.showSession)
                secondaryButton(String(localized: "End block"), action: actions.endBlock)
            }
        }
    }

    /// "Set **2** of 3", the number in the primary ink.
    private var roundCaption: Text {
        var caption = AttributedString(localized: "Set **\(guide.round)** of \(guide.rounds)")
        for run in caption.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            caption[run.range].foregroundColor = StrandPalette.textPrimary
        }
        return Text(caption)
    }

    // MARK: - Rest

    private func restingTop(startedAt: Int, endsAt: Int) -> some View {
        let next = guide.nextRound ?? guide.round + 1
        return VStack(alignment: .leading, spacing: 0) {
            compactHeader
            restCountdown(startedAt: startedAt, endsAt: endsAt, next: next)
                .frame(maxWidth: .infinity)
                .padding(.top, 26)
            vitals(.resting(lastRoundSec: guide.lastRoundSec))
                .padding(.top, 20)
            nextRoundCard(next)
                .padding(.top, 14)
            hint(String(localized: "The strap buzzes 5 s before 0:00, then set \(next) starts"))
                .padding(.top, 12)
        }
    }

    private func restCountdown(startedAt: Int, endsAt: Int, next: Int) -> some View {
        VStack(spacing: 8) {
            Text("Resting")
                .font(StrandFont.rounded(13, weight: .bold))
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(StrandPalette.metricAmber)
            LiftRestRing(startedAt: startedAt, endsAt: endsAt)
                .frame(width: 230, height: 230)
            LiftRoundSegments(rounds: guide.rounds, done: guide.doneRounds, current: nil)
                .padding(.top, 8)
            Text(String(localized: "Set \(guide.round) done · set \(next) starts at 0:00"))
                .font(StrandFont.rounded(14, weight: .regular))
                .foregroundStyle(StrandPalette.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    /// The round the rest leads to, with each exercise's numbers — what to load before the clock ends.
    private func nextRoundCard(_ next: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            overline(String(localized: "Set \(next) · ready"))
            ForEach(guide.members.filter { $0.targetSets >= next }, id: \.index) { member in
                HStack(spacing: 8) {
                    tagPill(member.tag, small: true)
                    Text(member.exercise)
                        .font(StrandFont.rounded(15, weight: .bold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(preview(LiftSlot(exerciseIndex: member.index, setIndex: next)))
                        .font(StrandFont.rounded(15, weight: .regular))
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var restingBottom: some View {
        let next = guide.nextRound ?? guide.round + 1
        return HStack(spacing: 10) {
            Button(action: actions.addRest) {
                Text("+30 s")
                    .font(StrandFont.rounded(15, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .frame(width: 72, height: 60)
                    .background(StrandPalette.surfaceRaised,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(LiftGuidePressStyle())
            Button(action: actions.skipRest) {
                HStack(spacing: 8) {
                    Text(String(localized: "Skip · set \(next) now"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 17, weight: .bold))
                }
                .font(StrandFont.rounded(17, weight: .heavy))
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(StrandPalette.hairline, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(LiftGuidePressStyle())
        }
    }

    // MARK: - Shared pieces

    /// "SUPERSET A" and the session's clock, over the round and the rest.
    private var compactHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(String(localized: "Superset \(guide.letter)"))
                .font(StrandFont.rounded(13, weight: .bold))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(StrandPalette.textTertiary)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Text("Session")
                LiftRunningClock { $0 - sessionStart }
            }
            .font(StrandFont.rounded(13, weight: .regular))
            .foregroundStyle(StrandPalette.textSecondary)
            menuButton
        }
    }

    private var menuButton: some View {
        Button { showingMenu = true } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(StrandPalette.textSecondary)
                .frame(width: 30, height: 30)
                .background(StrandPalette.surfaceRaised, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "More"))
    }

    /// One exercise of the block: its tag, name and muscles, then its weight and reps for `round` as two
    /// chips. A member without that set (uneven counts) shows a dash instead.
    private func memberRow(_ member: LiftSupersetGuide.Member, round: Int, nameSize: CGFloat,
                           chipHeight: CGFloat, detailed: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            tagPill(member.tag, small: false)
            memberTitle(member, nameSize: nameSize, detailed: detailed)
                .frame(maxWidth: .infinity, alignment: .leading)
            memberNumbers(member, round: round, chipHeight: chipHeight)
        }
    }

    private func memberTitle(_ member: LiftSupersetGuide.Member, nameSize: CGFloat,
                             detailed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(member.exercise)
                .font(StrandFont.rounded(nameSize, weight: .bold))
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if detailed {
                memberDetails(member)
            }
        }
    }

    /// Muscles, the proposed step-up and the line's cue — one quiet line each, only on the ready screen.
    @ViewBuilder
    private func memberDetails(_ member: LiftSupersetGuide.Member) -> some View {
        Text(LiftMuscleSummary.line(primary: member.primaryMuscle, secondaries: member.secondaryMuscles))
            .font(StrandFont.rounded(12, weight: .regular))
            .foregroundStyle(StrandPalette.textSecondary)
            .lineLimit(1)
        if let up = suggestion(member.exercise) {
            Text(up)
                .font(StrandFont.rounded(12, weight: .semibold))
                .foregroundStyle(StrandPalette.chargeColor)
                .lineLimit(1)
        }
        if let note = member.note, !note.isEmpty {
            Text(note)
                .font(StrandFont.rounded(12, weight: .regular))
                .foregroundStyle(StrandPalette.textTertiary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func memberNumbers(_ member: LiftSupersetGuide.Member, round: Int, chipHeight: CGFloat) -> some View {
        if round <= member.targetSets {
            chip(field(LiftSlot(exerciseIndex: member.index, setIndex: round), .weight),
                 unit: LiftFormat.weightUnit(unitSystem), height: chipHeight)
            chip(field(LiftSlot(exerciseIndex: member.index, setIndex: round), .reps),
                 unit: String(localized: "Reps"), height: chipHeight)
        } else {
            Text(verbatim: "—")
                .font(StrandFont.rounded(18, weight: .heavy))
                .foregroundStyle(StrandPalette.textTertiary)
        }
    }

    /// A number with its unit, on the page's own colour, sunk into the card.
    private func chip(_ number: AnyView, unit: String, height: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            number
                .font(StrandFont.rounded(18, weight: .heavy))
                .foregroundStyle(StrandPalette.textPrimary)
            Text(unit)
                .font(StrandFont.rounded(12, weight: .semibold))
                .textCase(.lowercase)
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: height)
        .background(StrandPalette.surfaceBase, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func tagPill(_ tag: String, small: Bool) -> some View {
        Text(tag)
            .font(StrandFont.rounded(small ? 12 : 13, weight: .heavy))
            .foregroundStyle(StrandPalette.surfaceBase)
            .padding(.horizontal, small ? 7 : 9)
            .padding(.vertical, small ? 2 : 4)
            .background(StrandPalette.effortColor,
                        in: RoundedRectangle(cornerRadius: small ? 7 : 9, style: .continuous))
    }

    /// Between two exercises of a round: chained, no rest.
    private func chainedDivider(withWord: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .font(.system(size: 13, weight: .bold))
            if withWord {
                Text("Chained")
                    .font(StrandFont.rounded(12, weight: .bold))
                    .tracking(1)
                    .textCase(.uppercase)
                    .fixedSize()
            }
            Rectangle()
                .fill(StrandPalette.hairline)
                .frame(height: 1)
        }
        .foregroundStyle(StrandPalette.metricAmber)
        .padding(.leading, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "No rest"))
    }

    private func overline(_ text: String) -> some View {
        Text(text)
            .font(StrandFont.rounded(11, weight: .bold))
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(StrandPalette.textTertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private func hint(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(StrandPalette.statusPositive)
            Text(text)
                .font(StrandFont.rounded(13, weight: .regular))
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(StrandFont.rounded(14, weight: .bold))
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(LiftGuidePressStyle())
    }
}

/// The rounds as a row of bars: done in green, the one being worked in the superset's blue, the rest
/// still to come.
struct LiftRoundSegments: View {
    let rounds: Int
    let done: Set<Int>
    let current: Int?

    var body: some View {
        let count = max(1, rounds)
        // 44 wide up to six rounds, as drawn; narrower beyond, so twenty still fit a phone.
        let width: CGFloat = count <= 6 ? 44 : max(10, 300 / CGFloat(count) - 6)
        HStack(spacing: count <= 6 ? 8 : 6) {
            ForEach(1...count, id: \.self) { k in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(done.contains(k) ? StrandPalette.statusPositive
                          : (k == current ? StrandPalette.effortColor : StrandPalette.hairline))
                    .frame(width: width, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(done.count) of \(count) sets done"))
    }
}

/// The rest as a ring that empties: the time left in the middle, the rest's length under it. Its own
/// small view on its own timeline, so the second it ticks redraws the ring and nothing around it.
struct LiftRestRing: View {
    let startedAt: Int
    let endsAt: Int

    var body: some View {
        TimelineView(.periodic(from: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970)), by: 1)) {
            context in
            let now = Int(context.date.timeIntervalSince1970)
            let total = max(1, endsAt - startedAt)
            let left = max(0, endsAt - now)
            ZStack {
                Circle()
                    .stroke(StrandPalette.hairline, lineWidth: 12)
                Circle()
                    .trim(from: 0, to: CGFloat(left) / CGFloat(total))
                    .stroke(StrandPalette.metricAmber, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: left)
                VStack(spacing: 4) {
                    Text(ActiveWorkoutClock.clock(left))
                        .font(StrandFont.rounded(68, weight: .heavy))
                        .tracking(-2)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(String(localized: "out of \(LiftFormat.duration(total))"))
                        .font(StrandFont.rounded(13, weight: .regular))
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                .padding(.horizontal, 24)
            }
            .padding(6)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One of the three live tiles: a label, a big number, a line under it.
struct LiftGuideTile: View {
    let label: String
    let value: String
    var tint: Color = StrandPalette.textPrimary
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(StrandFont.rounded(11, weight: .bold))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(StrandPalette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(StrandFont.rounded(28, weight: .heavy))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(StrandFont.rounded(12, weight: .regular))
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The ready screen's strap line: whether the strap is sending a heart rate, what a double-tap does,
/// and the heart rate itself. Display only.
struct LiftStrapCardContent: View {
    let bpm: Int?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(bpm == nil ? StrandPalette.textTertiary : StrandPalette.statusPositive)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(bpm == nil ? String(localized: "Strap not reading") : String(localized: "Strap reading"))
                    .font(StrandFont.rounded(14, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("Double-tap = set done · buzzes 5 s before the rest ends")
                    .font(StrandFont.rounded(12, weight: .regular))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: "\(bpm.map(String.init) ?? "—") bpm")
                .font(StrandFont.rounded(14, weight: .bold))
                .foregroundStyle(bpm == nil ? StrandPalette.textTertiary : StrandPalette.metricRose)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A press that answers under the thumb: a touch smaller and dimmer while held.
struct LiftGuidePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
