import SwiftUI
import StrandDesign

// MARK: - Coach, essential mode: the orbit (personal fork, chantier 20)
//
// The coach's star breathes in the middle while the four measures of the day turn round it in the rings'
// colours (activity, Charge, Effort, Rest), each at its own speed: the coach reads the day. They arrive
// in a spiral when the screen appears, and turn faster and closer while an answer is being written.

struct CoachOrbitView: View {
    /// An answer is being written.
    var thinking: Bool
    var diameter: CGFloat = 240

    @State var appeared = Date()
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @ObservedObject var motion = NoopMotionState.shared

    /// One measure on its orbit: its colour, its share of the radius, its period in seconds (negative
    /// turns the other way) and where it starts.
    private struct Orbit {
        var tint: Color
        var radius: CGFloat
        var period: Double
        var start: Double
    }

    private var orbits: [Orbit] {
        [Orbit(tint: StrandPalette.caloriesActivity, radius: 0.9, period: 14, start: 0),
         Orbit(tint: StrandPalette.chargeColor, radius: 0.73, period: -10, start: 0.39),
         Orbit(tint: StrandPalette.effortColor, radius: 0.57, period: 7, start: 0.64),
         Orbit(tint: StrandPalette.restRing, radius: 0.42, period: -5, start: 0.18)]
    }

    var body: some View {
        Group {
            if motion.poseStill(reduceMotion) {
                canvas(at: nil)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    canvas(at: context.date)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .onAppear { appeared = Date() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(thinking ? Text("The coach is writing") : Text("The coach reads your day"))
    }

    private func canvas(at date: Date?) -> some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let half = min(size.width, size.height) / 2
            let now = date?.timeIntervalSinceReferenceDate ?? 0
            // The spiral entrance, 1.4 s from the centre out.
            let since = date.map { $0.timeIntervalSince(appeared) } ?? 10
            let arrive = CGFloat(1 - pow(1 - min(1, max(0, since / 1.4)), 3))
            let speed = thinking ? 3.0 : 1.0
            let pull: CGFloat = thinking ? 0.85 + 0.05 * CGFloat(sin(now * 4)) : 1
            // The breath of the star and its halo, 4 s a cycle.
            let breath = date == nil ? 0.5 : 0.5 - 0.5 * cos(now.truncatingRemainder(dividingBy: 4) / 4 * 2 * .pi)
            let haloRadius = half * 0.22 * CGFloat(0.9 + 0.22 * breath)
            context.fill(Path(ellipseIn: CGRect(x: center.x - haloRadius, y: center.y - haloRadius,
                                                width: haloRadius * 2, height: haloRadius * 2)),
                         with: .color(StrandPalette.textPrimary.opacity(0.08 + 0.12 * breath)))
            for orbit in orbits {
                let r = half * orbit.radius
                context.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                               with: .color(StrandPalette.textPrimary.opacity(0.07)), lineWidth: 1)
            }
            for orbit in orbits {
                let turn = orbit.start + (date == nil ? 0 : now * speed / orbit.period)
                let r = half * orbit.radius * arrive * pull
                let p = EssentialTraceMath.point(center, radius: r, degrees: turn * 360)
                let dot = 5.5 * (0.4 + 0.6 * arrive)
                context.drawLayer { layer in
                    layer.addFilter(.shadow(color: orbit.tint, radius: 6))
                    layer.fill(Path(ellipseIn: CGRect(x: p.x - dot, y: p.y - dot, width: dot * 2, height: dot * 2)),
                               with: .color(orbit.tint))
                }
            }
            // The star: four points, curved sides.
            let s = half * 0.27 * CGFloat(0.92 + 0.16 * breath)
            var star = Path()
            star.move(to: CGPoint(x: center.x, y: center.y - s))
            star.addQuadCurve(to: CGPoint(x: center.x + s, y: center.y), control: CGPoint(x: center.x + s * 0.12, y: center.y - s * 0.12))
            star.addQuadCurve(to: CGPoint(x: center.x, y: center.y + s), control: CGPoint(x: center.x + s * 0.12, y: center.y + s * 0.12))
            star.addQuadCurve(to: CGPoint(x: center.x - s, y: center.y), control: CGPoint(x: center.x - s * 0.12, y: center.y + s * 0.12))
            star.addQuadCurve(to: CGPoint(x: center.x, y: center.y - s), control: CGPoint(x: center.x - s * 0.12, y: center.y - s * 0.12))
            star.closeSubpath()
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: StrandPalette.textPrimary.opacity(0.7), radius: 10))
                layer.fill(star, with: .color(StrandPalette.textPrimary))
            }
        }
    }
}
