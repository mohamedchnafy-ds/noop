import SwiftUI
import StrandDesign
import WhoopStore

// Fork chantier 21: the execution figure on screen. A small tile under an exercise's name in the
// session (it moves for the exercise in hand, it stands still on the others), and a tap opens the sheet:
// the figure in big with the phase it is in, the tempo, a slow-motion switch, the muscles in the
// highlight colour, three cues of good form, and the movement, which the user can change.
//
// The figure moves only while the shared quiet-motion gate is open (system Reduce Motion, Low Power
// Mode, "Reduce motion in NOOP"): otherwise it holds its still pose. Maquette:
// https://claude.ai/artifact/FHAdxxU4x76FHD3vj6Bx6H

/// Draws one frame of a movement's figure, scaled to fit, in the app's colours.
struct LiftFigureView: View {
    let spec: LiftFigureSpec
    let box: CGRect
    let pose: LiftPose

    /// `time`: seconds into the loop, or nil for the still pose.
    init(movement: LiftMovement, time: Double?) {
        let spec = movement.figure
        self.spec = spec
        box = LiftFigureDrawing.bounds(spec)
        pose = time.map { spec.figurePose(at: $0).pose } ?? spec.stillPose
    }

    var body: some View {
        let spec = spec, box = box, pose = pose
        Canvas { context, size in
            Self.paintFigure(context, size: size, spec: spec, box: box, pose: pose)
        }
        .accessibilityHidden(true)
    }

    static func paintFigure(_ context: GraphicsContext, size: CGSize, spec: LiftFigureSpec, box: CGRect,
                            pose: LiftPose) {
        guard box.width > 0, box.height > 0 else { return }
        let scale = min(size.width / box.width, size.height / box.height)
        let ox = (size.width - box.width * scale) / 2 - box.minX * scale
        let oy = (size.height - box.height * scale) / 2 - box.minY * scale
        func onScreen(_ p: CGPoint) -> CGPoint { CGPoint(x: ox + p.x * scale, y: oy + p.y * scale) }
        func length(_ v: Double) -> CGFloat { CGFloat(v) * scale }

        for shape in LiftFigureDrawing.shapes(spec, pose, in: box) {
            let color = shapeColor(shape.role)
            switch shape.kind {
            case .line(let a, let b, let width):
                var path = Path()
                path.move(to: onScreen(a))
                path.addLine(to: onScreen(b))
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: length(width), lineCap: .round))
            case .disc(let center, let radius):
                let c = onScreen(center), r = length(radius)
                context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                             with: .color(color))
            case .ring(let center, let radius, let width):
                let c = onScreen(center), r = length(radius)
                let disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                context.fill(disc, with: .color(StrandPalette.surfaceOverlay))
                context.stroke(disc, with: .color(color), lineWidth: length(width))
            case .bar(let rect):
                let origin = onScreen(rect.origin)
                let scaled = CGRect(x: origin.x, y: origin.y, width: rect.width * scale, height: rect.height * scale)
                context.fill(Path(roundedRect: scaled, cornerRadius: length(2)), with: .color(color))
            }
        }
    }

    private static func shapeColor(_ role: LiftFigureShape.Role) -> Color {
        switch role {
        case .limb: return StrandPalette.textPrimary
        case .farLimb: return StrandPalette.textTertiary
        case .highlight: return StrandPalette.accent
        case .ground: return StrandPalette.hairlineStrong
        case .equipment: return StrandPalette.textTertiary.opacity(0.55)
        case .cable: return StrandPalette.textTertiary
        case .plate, .weight: return StrandPalette.textSecondary
        }
    }
}

// MARK: - The tile under an exercise's name

struct LiftExecutionTile: View {
    let exercise: String
    /// True for the exercise in hand: only its figure moves.
    let animated: Bool

    @AppStorage(LiftMovementChoice.storageKey) private var choicesRaw = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared
    @State private var showingSheet = false

    var body: some View {
        let movement = LiftMovementChoice.resolveMovement(exercise: exercise, choices: choicesRaw).movement
        Group {
            if let movement {
                tile(movement)
            } else {
                chooseLink
            }
        }
        .sheet(isPresented: $showingSheet) { LiftExecutionSheet(exercise: exercise) }
    }

    private func tile(_ movement: LiftMovement) -> some View {
        let moving = animated && !motion.poseStill(reduceMotion)
        return Button { showingSheet = true } label: {
            HStack(spacing: NoopMetrics.space3) {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !moving)) { timeline in
                    LiftFigureView(movement: movement,
                                   time: moving ? timeline.date.timeIntervalSinceReferenceDate : nil)
                }
                .frame(width: 96, height: 76)
                VStack(alignment: .leading, spacing: NoopMetrics.spaceHalf) {
                    Text("Execution")
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(movement.tempoLine)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Tap to enlarge")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.accent)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(NoopMetrics.space2)
            .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Show the execution: \(movement.label)"))
    }

    /// A name nothing recognised: one quiet line, which opens the sheet on the list of movements.
    private var chooseLink: some View {
        Button { showingSheet = true } label: {
            HStack(spacing: NoopMetrics.space1) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 12, weight: .semibold))
                Text("Choose a movement to see the execution")
                    .font(StrandFont.caption)
            }
            .foregroundStyle(StrandPalette.accent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - The sheet

struct LiftExecutionSheet: View {
    let exercise: String

    @AppStorage(LiftMovementChoice.storageKey) private var choicesRaw = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared
    @State private var slow = false
    /// The figure's clock: `clockOffset` seconds at `clockBase`, running at full or half speed after it,
    /// so switching the slow motion never makes the figure jump.
    @State private var clockBase = Date()
    @State private var clockOffset = 0.0
    @State private var picking = false

    private var speed: Double { slow ? 0.5 : 1 }

    var body: some View {
        let resolved = LiftMovementChoice.resolveMovement(exercise: exercise, choices: choicesRaw)
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                header
                if let movement = resolved.movement {
                    figureCard(movement)
                    tempoRow(movement)
                    musclesRow(movement)
                    cuesCard(movement)
                }
                movementCard(resolved.movement, chosen: resolved.chosen)
            }
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.top, 18)
            .padding(.bottom, NoopMetrics.sectionGap)
        }
        .background(StrandPalette.surfaceBase)
        .onAppear { if resolved.movement == nil { picking = true } }
        #if os(iOS)
        .presentationDragIndicator(.visible)
        #else
        .frame(width: 460, height: 720)
        #endif
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: NoopMetrics.spaceHalf) {
                Text(verbatim: exercise)
                    .font(StrandFont.title2)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("Good form")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            Spacer(minLength: NoopMetrics.space3)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .frame(width: NoopMetrics.compactControlSize, height: NoopMetrics.compactControlSize)
                    .background(StrandPalette.surfaceRaised, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Close"))
        }
    }

    private func figureClock(at date: Date) -> Double {
        clockOffset + date.timeIntervalSince(clockBase) * speed
    }

    private func figureCard(_ movement: LiftMovement) -> some View {
        let moving = !motion.poseStill(reduceMotion)
        let spec = movement.figure
        return TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !moving)) { timeline in
            let t = figureClock(at: timeline.date)
            ZStack(alignment: .topLeading) {
                LiftFigureView(movement: movement, time: moving ? t : nil)
                    .padding(NoopMetrics.space3)
                if moving || spec.end == nil {
                    Text(spec.figurePose(at: t).phase.label)
                        .font(StrandFont.caption.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, NoopMetrics.space1)
                        .background(StrandPalette.surfaceRaised, in: Capsule())
                        .padding(NoopMetrics.space3)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 260)
        .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius,
                                                                     style: .continuous))
        .accessibilityElement()
        .accessibilityLabel(Text("Figure doing the movement: \(movement.label)"))
    }

    private func tempoRow(_ movement: LiftMovement) -> some View {
        HStack(spacing: NoopMetrics.space3) {
            Text(movement.tempoLine)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if movement.figure.end != nil {
                Button { toggleSlow() } label: {
                    Text("Slow motion")
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(slow ? StrandPalette.onDarkPrimary : StrandPalette.textPrimary)
                        .padding(.horizontal, NoopMetrics.space4)
                        .frame(minHeight: 44)
                        .background(slow ? StrandPalette.accent : StrandPalette.surfaceRaised, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(slow ? .isSelected : [])
            }
        }
    }

    private func toggleSlow() {
        let now = Date()
        clockOffset = figureClock(at: now)
        clockBase = now
        slow.toggle()
    }

    private func musclesRow(_ movement: LiftMovement) -> some View {
        let muscles = movement.muscles
        return HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
            Circle()
                .fill(StrandPalette.accent)
                .frame(width: 9, height: 9)
            Text(LiftMuscleSummary.line(primary: muscles.primary, secondaries: muscles.secondaries))
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textPrimary)
            Text("in blue on the figure")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
        }
    }

    private func cuesCard(_ movement: LiftMovement) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.rowSpacing) {
                ForEach(Array(movement.cues.enumerated()), id: \.offset) { index, cue in
                    HStack(alignment: .top, spacing: NoopMetrics.space3) {
                        Text(verbatim: "\(index + 1)")
                            .font(StrandFont.captionNumber.weight(.bold))
                            .foregroundStyle(StrandPalette.surfaceBase)
                            .frame(width: 22, height: 22)
                            .background(StrandPalette.textPrimary, in: Circle())
                        Text(cue)
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func movementCard(_ movement: LiftMovement?, chosen: Bool) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.rowSpacing) {
                HStack(spacing: NoopMetrics.space3) {
                    VStack(alignment: .leading, spacing: NoopMetrics.spaceHalf) {
                        if let movement {
                            Text("Movement: \(movement.label)")
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textPrimary)
                            if chosen {
                                Text("Chosen by you")
                                    .font(StrandFont.caption)
                                    .foregroundStyle(StrandPalette.textSecondary)
                            } else {
                                Text("Recognised from the name")
                                    .font(StrandFont.caption)
                                    .foregroundStyle(StrandPalette.textSecondary)
                            }
                        } else {
                            Text("Which movement is it?")
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textPrimary)
                            Text("Not recognised from the name")
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if movement != nil {
                        Button { picking.toggle() } label: {
                            Group {
                                if picking { Text("Close") } else { Text("Change") }
                            }
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.accent)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                if picking {
                    ForEach(LiftMovement.allCases) { option in
                        Button {
                            choicesRaw = LiftMovementChoice.choosingMovement(option, for: exercise, in: choicesRaw)
                            picking = false
                        } label: {
                            HStack {
                                Text(option.label)
                                    .font(StrandFont.subhead)
                                    .foregroundStyle(StrandPalette.textPrimary)
                                Spacer(minLength: 0)
                                if option == movement {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(StrandPalette.accent)
                                }
                            }
                            .frame(minHeight: 40)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(option == movement ? .isSelected : [])
                    }
                }
            }
        }
    }
}
