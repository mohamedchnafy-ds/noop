import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - The fasting ring (personal fork, chantier 15)
//
// The Jeûne page's hero and, smaller, the Nutrition card's badge: a horseshoe open at the bottom, read like
// the Sleep tab's night ring (the start at the bottom left, the planned end at the bottom right, clockwise),
// but joyful rather than nocturnal: the part done in a vivid green, the part left in a soft red, a white
// dot with a green halo at « now », a badge at each start of phase inside the goal (fork and knife at the
// start, a sun at the end). Display only: every number arrives from `FastingState`, resolved once.

/// Pure geometry, kept apart so it is tested without drawing (`FastingPageTests`).
enum FastingRingMath {
    /// The opening at the bottom, degrees, between the start and the planned end.
    static let gapDegrees: Double = 90

    /// The ring angle of a share of the goal, in permille: from just left of 6 o'clock (the start)
    /// clockwise over the top to just right of it (the goal), degrees from 12 o'clock.
    static func angle(permille: Int) -> Double {
        let t = Double(min(max(permille, 0), 1000)) / 1000
        return 180 + gapDegrees / 2 + t * (360 - gapDegrees)
    }

    /// Where a point of the ring sits, for a centre `c` and radius `r`.
    static func point(_ c: CGPoint, _ r: CGFloat, degrees: Double) -> CGPoint {
        let rad = degrees * .pi / 180
        return CGPoint(x: c.x + r * CGFloat(sin(rad)), y: c.y - r * CGFloat(cos(rad)))
    }
}

/// What the ring shows: nothing running, a fast running, or a fast over (goal reached or not).
enum FastingRingMode: Equatable {
    case idle
    case running
    case done(reached: Bool)
}

struct FastingRing<Center: View>: View {
    let mode: FastingRingMode
    /// The share of the goal done, 0…1000 (`FastingState.progressPermille`).
    let progressPermille: Int
    /// Fork chantier 12: the share of the progress drawn, 0…1, animated from the start; 1 draws it whole.
    var trace: Double = 1
    /// The phase starts inside the goal (`FastingState.markers`).
    var markers: [FastingTimeline.Marker] = []
    /// The phase reached (`FastingState.phaseIndex`); its badge is filled, the ones before are green.
    var currentPhase: Int = 0
    var diameter: CGFloat = 250
    /// 0…1, the halo of the « now » dot breathing (the caller's clock); 0 leaves it still.
    var breath: Double = 0
    /// A tap on a phase badge. Nil leaves the badges as marks.
    var onMarker: ((Int) -> Void)? = nil
    @ViewBuilder let center: () -> Center

    private var lineWidth: CGFloat { max(8, diameter * 0.072) }
    /// Room around the ring for the badges that sit on it.
    private var margin: CGFloat { diameter >= 160 ? 18 : 10 }
    private var radius: CGFloat { diameter / 2 - lineWidth / 2 }
    private var side: CGFloat { diameter + margin * 2 }
    private var centerPoint: CGPoint { CGPoint(x: side / 2, y: side / 2) }

    /// The angle the green arc reaches, with the trace.
    private var reachDegrees: Double {
        FastingRingMath.angle(permille: Int((Double(progressPermille) * min(max(trace, 0), 1)).rounded()))
    }

    private var trackColor: Color {
        switch mode {
        case .idle: return StrandPalette.hairlineStrong
        case .running: return StrandPalette.fastingRemaining
        case .done(let reached): return reached ? StrandPalette.fastingDone.opacity(0.28) : StrandPalette.fastingRemaining
        }
    }

    private var endBadgeHidden: Bool { markers.contains { $0.permille >= 1000 } }

    var body: some View {
        ZStack {
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let from = FastingRingMath.angle(permille: 0)
                let to = FastingRingMath.angle(permille: 1000)
                ctx.stroke(arcPath(center: c, from: from, to: to), with: .color(trackColor),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                if mode != .idle, reachDegrees > from + 0.5 {
                    ctx.stroke(arcPath(center: c, from: from, to: reachDegrees), with: .color(StrandPalette.fastingDone),
                               style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                }
                if mode == .running, progressPermille > 0, trace > 0.01 {
                    drawHead(ctx, center: c)
                }
            }
            badge("fork.knife", tint: StrandPalette.fastingDone, at: FastingRingMath.angle(permille: 0))
            if !endBadgeHidden {
                badge("sun.max.fill", tint: mode == .done(reached: true) ? StrandPalette.fastingDone : StrandPalette.fastingRemaining,
                      at: FastingRingMath.angle(permille: 1000))
            }
            ForEach(markers, id: \.phaseIndex) { marker in
                phaseBadge(marker)
            }
            center()
                .frame(width: diameter - lineWidth * 3, height: diameter - lineWidth * 3)
        }
        .frame(width: side, height: side)
    }

    // MARK: Drawing

    /// The white dot at « now », with its green halo drawn as a gradient (never a blur: the page scrolls).
    private func drawHead(_ ctx: GraphicsContext, center c: CGPoint) {
        let head = FastingRingMath.point(c, radius, degrees: reachDegrees)
        let haloRadius = lineWidth * (0.9 + 0.35 * min(max(breath, 0), 1))
        let halo = Path(ellipseIn: CGRect(x: head.x - haloRadius, y: head.y - haloRadius,
                                          width: haloRadius * 2, height: haloRadius * 2))
        ctx.fill(halo, with: .radialGradient(
            Gradient(colors: [StrandPalette.fastingDone.opacity(0.55), StrandPalette.fastingDone.opacity(0)]),
            center: head, startRadius: 0, endRadius: haloRadius))
        let dotRadius = lineWidth * 0.36
        let dot = Path(ellipseIn: CGRect(x: head.x - dotRadius, y: head.y - dotRadius,
                                         width: dotRadius * 2, height: dotRadius * 2))
        ctx.fill(dot, with: .color(StrandPalette.textPrimary))
    }

    /// A circular arc sampled every degree, clockwise from `from` to `to` (degrees from 12 o'clock).
    private func arcPath(center c: CGPoint, from a0: Double, to a1: Double) -> Path {
        var path = Path()
        guard a1 > a0 else { return path }
        path.move(to: FastingRingMath.point(c, radius, degrees: a0))
        var a = a0 + 1
        while a < a1 {
            path.addLine(to: FastingRingMath.point(c, radius, degrees: a))
            a += 1
        }
        path.addLine(to: FastingRingMath.point(c, radius, degrees: a1))
        return path
    }

    // MARK: Badges

    private var badgeSize: CGFloat { diameter >= 160 ? 28 : 16 }

    /// The start and end badges, on the ring at either side of the opening.
    private func badge(_ symbol: String, tint: Color, at degrees: Double) -> some View {
        let p = FastingRingMath.point(.zero, radius, degrees: degrees)
        return ZStack {
            Circle().fill(StrandPalette.surfaceRaised)
            Circle().strokeBorder(tint, lineWidth: diameter >= 160 ? 2 : 1.5)
            Image(systemName: symbol)
                .font(.system(size: badgeSize * 0.43, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: badgeSize, height: badgeSize)
        .offset(x: p.x, y: p.y)
        .accessibilityHidden(true)
    }

    /// A phase's badge: green once passed, filled with its tint while current, soft red while to come;
    /// grey when nothing runs.
    @ViewBuilder
    private func phaseBadge(_ marker: FastingTimeline.Marker) -> some View {
        let p = FastingRingMath.point(.zero, radius, degrees: FastingRingMath.angle(permille: marker.permille))
        let passed = mode != .idle && marker.phaseIndex < currentPhase
        let current = mode != .idle && marker.phaseIndex == currentPhase
        let tint = FastingPhaseText.tint(marker.phaseIndex)
        let ring: Color = mode == .idle ? StrandPalette.hairlineStrong
            : passed ? StrandPalette.fastingDone : current ? tint : StrandPalette.fastingRemaining
        let fill: Color = current ? tint : StrandPalette.surfaceRaised
        let icon: Color = current ? StrandPalette.surfaceBase : ring
        let face = ZStack {
            Circle().fill(fill)
            Circle().strokeBorder(ring, lineWidth: current ? 0 : (diameter >= 160 ? 2 : 1.5))
            if current {
                Circle().strokeBorder(StrandPalette.textPrimary, lineWidth: diameter >= 160 ? 2 : 1.5)
            }
            Image(systemName: FastingPhaseText.symbol(marker.phaseIndex))
                .font(.system(size: badgeSize * 0.43, weight: .semibold))
                .foregroundStyle(icon)
        }
        .frame(width: badgeSize, height: badgeSize)
        // Fork chantier 12: the badge of the phase just reached grows a little as it lights up.
        .scaleEffect(current ? 1.12 : 1)
        .animation(NoopMotion.value, value: current)
        if let onMarker {
            Button { onMarker(marker.phaseIndex) } label: { face.contentShape(Circle()) }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(FastingPhaseText.name(marker.phaseIndex)))
                .accessibilityHint(Text("Shows the phase"))
                .offset(x: p.x, y: p.y)
        } else {
            face.offset(x: p.x, y: p.y).accessibilityHidden(true)
        }
    }
}
