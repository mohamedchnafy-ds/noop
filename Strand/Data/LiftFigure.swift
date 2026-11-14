import Foundation
import CoreGraphics

// Fork chantier 21: the execution figure, the little person under an exercise who does the movement.
//
// WHY A SKELETON AND NOT IMAGES. NOOP ships no exercise catalogue and no pictures (an exercise is what
// the user typed, `LiftExerciseRow`), and licensed animations cannot be redistributed. A figure drawn
// from joint angles is original, costs no bytes in the IPA, works offline and takes the app's colours.
//
// THE MODEL. A side-view stick figure (one movement, a front view) made of fixed-length segments. A
// pose gives each segment an absolute angle, measured from straight up and turning clockwise (y grows
// downward, as on screen): 0 points up, 90 forward (to the right), 180 down. The figure is chained from
// one anchor (the front ankle, or the hip) so whatever must not slide, a foot on the floor, stays put.
// An arm is either two angles or a reach: a hand target that a two-bone solve meets, so a bar can travel
// in a straight line while the elbow finds its own place. A movement is two poses, `start` and `end`,
// eased into each other and back on a fixed tempo. Everything here is pure: tests read it without a view.

/// The segment lengths, in figure units (a standing figure is about 180 tall).
enum LiftFigureLength {
    static let shin = 46.0
    static let thigh = 48.0
    static let torso = 58.0
    static let upperArm = 32.0
    static let forearm = 30.0
    static let foot = 15.0
    static let neck = 17.0
}

/// One pose of the figure. Angles in degrees (0 = up, 90 = forward, 180 = down); `ax`/`ay` place the
/// anchor. A far-leg value left nil copies the near leg, so a figure standing on both feet is one leg
/// drawn twice. `a2x`/`a2y` are the far ankle when that leg reaches for a fixed foot (a lunge); `hx`/`hy`
/// the hand target when the arm reaches (relative to the joint the movement names).
struct LiftPose: Equatable {
    var ax = 0.0, ay = 0.0
    var shin = 0.0, thigh = 0.0, torso = 0.0, foot = 90.0, neck = 0.0
    var shin2: Double? = nil, thigh2: Double? = nil, foot2: Double? = nil
    var a2x = 0.0, a2y = 0.0
    var ua = 180.0, fa = 180.0
    var hx = 0.0, hy = 0.0

    /// This pose moved `u` of the way (0…1) toward `other`.
    func mixed(toward other: LiftPose, _ u: Double) -> LiftPose {
        func m(_ a: Double, _ b: Double) -> Double { a + (b - a) * u }
        func mo(_ a: Double?, _ b: Double?) -> Double? {
            guard let a else { return b }
            guard let b else { return a }
            return m(a, b)
        }
        return LiftPose(ax: m(ax, other.ax), ay: m(ay, other.ay),
                        shin: m(shin, other.shin), thigh: m(thigh, other.thigh), torso: m(torso, other.torso),
                        foot: m(foot, other.foot), neck: m(neck, other.neck),
                        shin2: mo(shin2, other.shin2), thigh2: mo(thigh2, other.thigh2), foot2: mo(foot2, other.foot2),
                        a2x: m(a2x, other.a2x), a2y: m(a2y, other.a2y),
                        ua: m(ua, other.ua), fa: m(fa, other.fa),
                        hx: m(hx, other.hx), hy: m(hy, other.hy))
    }
}

/// What a phase of a movement is called on screen ("Lowering 2 s").
enum LiftFigurePhase: Equatable {
    case ready, lowering, lifting, pushing, pulling, raising, curling, returning, pausing, holding
}

/// The parts of the figure that can be drawn in the highlight colour: the muscles a movement works.
enum LiftFigureHighlight: Hashable {
    case shin, thigh, upperArm, forearm
    /// The torso's top half (chest from the front, upper back from behind: one line in a side view).
    case upperTorso
    /// The torso's bottom half (abs, lower back).
    case lowerTorso
    /// A dot on the hip (glutes) and on the shoulders (delts).
    case hip, shoulders
}

/// How one movement is drawn and timed.
struct LiftFigureSpec {
    enum Anchor { case ankle, hip }
    /// The joint an arm's reach target is measured from.
    enum ReachBase { case shoulder, hip, world }
    enum Arm {
        case angles
        /// `torsoFrame`: the target turns with the torso (a bar on the back follows it down).
        /// `bend`: which side of the shoulder→hand line the elbow goes (+1 or −1).
        case reach(base: ReachBase, torsoFrame: Bool, bend: Double)
    }
    enum FarLeg { case angles, reach(bend: Double) }
    enum Prop { case none, plate, plateOnHip, dumbbell, dumbbellPair, handle, bar }
    enum Bench { case none, flat, prone, seat, incline, thrust }
    enum Ground { case none, underFeet, at(Double) }

    var anchor: Anchor
    var arm: Arm = .angles
    var farLeg: FarLeg = .angles
    /// Front view only: half the hip / shoulder width, and the far arm mirrors the near one.
    var hipHalfWidth = 0.0
    var shoulderHalfWidth = 0.0
    var mirrorsFarArm = false
    var prop: Prop = .none
    var cable = false
    /// The roller pad of a leg machine, on the ankle.
    var pad = false
    var bench: Bench = .none
    var ground: Ground = .underFeet
    var highlights: Set<LiftFigureHighlight> = []
    var start: LiftPose
    /// Nil: a hold (the plank), drawn still.
    var end: LiftPose?
    var first: (phase: LiftFigurePhase, seconds: Int) = (.lowering, 2)
    var second: (phase: LiftFigurePhase, seconds: Int) = (.lifting, 1)

    static let holdAtStart = 0.5
    static let holdAtEnd = 0.3

    /// One full repetition, in seconds.
    var cycleSeconds: Double {
        guard end != nil else { return 1 }
        return Self.holdAtStart + Double(first.seconds) + Self.holdAtEnd + Double(second.seconds)
    }

    /// The pose and its phase `t` seconds into the loop. Each move is eased (slow in, slow out).
    func figurePose(at t: Double) -> (pose: LiftPose, phase: LiftFigurePhase) {
        guard let end else { return (start, .holding) }
        let total = cycleSeconds
        var x = t.truncatingRemainder(dividingBy: total)
        if x < 0 { x += total }
        let a = Double(first.seconds), b = Double(second.seconds)
        func ease(_ u: Double) -> Double { 0.5 - 0.5 * cos(Double.pi * u) }
        if x < Self.holdAtStart { return (start, .ready) }
        x -= Self.holdAtStart
        if x < a { return (start.mixed(toward: end, ease(x / a)), first.phase) }
        x -= a
        if x < Self.holdAtEnd { return (end, .pausing) }
        x -= Self.holdAtEnd
        return (start.mixed(toward: end, 1 - ease(min(1, x / b))), second.phase)
    }

    /// The still frame shown when the figure does not move: halfway down the first phase, where the
    /// movement reads best (the plank's only pose).
    var stillPose: LiftPose {
        guard let end else { return start }
        return start.mixed(toward: end, 0.6)
    }
}

/// The figure's joints for one pose, in figure units.
struct LiftFigureJoints {
    var ankle, knee, hip, hipNear, hipFar, shoulder, shoulderNear, shoulderFar, head, toe: CGPoint
    var elbow, hand, knee2, ankle2, toe2, elbow2, hand2: CGPoint

    var all: [CGPoint] {
        [ankle, knee, hip, hipNear, hipFar, shoulder, shoulderNear, shoulderFar, head, toe,
         elbow, hand, knee2, ankle2, toe2, elbow2, hand2]
    }
}

enum LiftFigureSolver {

    static func direction(_ degrees: Double) -> CGPoint {
        let r = degrees * .pi / 180
        return CGPoint(x: sin(r), y: -cos(r))
    }

    static func figureStep(_ p: CGPoint, _ degrees: Double, _ length: Double) -> CGPoint {
        let r = degrees * .pi / 180
        return CGPoint(x: Double(p.x) + sin(r) * length, y: Double(p.y) - cos(r) * length)
    }

    static func rotate(_ v: CGPoint, _ degrees: Double) -> CGPoint {
        let r = degrees * .pi / 180, c = cos(r), s = sin(r)
        let x = Double(v.x), y = Double(v.y)
        return CGPoint(x: x * c - y * s, y: x * s + y * c)
    }

    /// Two segments from `root` toward `target`: the middle joint and the end. A target out of reach is
    /// met at full stretch, on the line toward it.
    static func reach(from root: CGPoint, to target: CGPoint, _ l1: Double, _ l2: Double,
                      bend: Double) -> (joint: CGPoint, end: CGPoint) {
        let rx = Double(root.x), ry = Double(root.y)
        let dx = Double(target.x) - rx, dy = Double(target.y) - ry
        let raw = Swift.max((dx * dx + dy * dy).squareRoot(), 0.001)
        let d = Swift.min(raw, l1 + l2 - 0.01)
        let a = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
        let h = Swift.max(0, l1 * l1 - a * a).squareRoot()
        let ux = dx / raw, uy = dy / raw
        let joint = CGPoint(x: rx + ux * a - uy * h * bend, y: ry + uy * a + ux * h * bend)
        return (joint, CGPoint(x: rx + ux * d, y: ry + uy * d))
    }

    static func solve(_ spec: LiftFigureSpec, _ p: LiftPose) -> LiftFigureJoints {
        typealias L = LiftFigureLength
        let hip: CGPoint
        var ankle: CGPoint, knee: CGPoint
        switch spec.anchor {
        case .ankle:
            ankle = CGPoint(x: p.ax, y: p.ay)
            knee = figureStep(ankle, p.shin, L.shin)
            hip = figureStep(knee, p.thigh, L.thigh)
        case .hip:
            hip = CGPoint(x: p.ax, y: p.ay)
            knee = figureStep(hip, p.thigh, -L.thigh)
            ankle = figureStep(knee, p.shin, -L.shin)
        }
        let hipNear = CGPoint(x: Double(hip.x) - spec.hipHalfWidth, y: Double(hip.y))
        let hipFar = CGPoint(x: Double(hip.x) + spec.hipHalfWidth, y: Double(hip.y))
        if spec.hipHalfWidth != 0 {
            // Front view: the near leg hangs from its own side of the hips.
            knee = figureStep(hipNear, p.thigh, -L.thigh)
            ankle = figureStep(knee, p.shin, -L.shin)
        }
        let toe = figureStep(ankle, p.foot, L.foot)

        let knee2: CGPoint, ankle2: CGPoint
        switch spec.farLeg {
        case .angles:
            knee2 = figureStep(hipFar, p.thigh2 ?? p.thigh, -L.thigh)
            ankle2 = figureStep(knee2, p.shin2 ?? p.shin, -L.shin)
        case .reach(let bend):
            let leg = reach(from: hipFar, to: CGPoint(x: p.a2x, y: p.a2y), L.thigh, L.shin, bend: bend)
            knee2 = leg.joint
            ankle2 = leg.end
        }
        let toe2 = figureStep(ankle2, p.foot2 ?? p.foot, L.foot)

        let shoulder = figureStep(hip, p.torso, L.torso)
        let head = figureStep(shoulder, p.torso + p.neck, L.neck)
        let shoulderNear = CGPoint(x: Double(shoulder.x) - spec.shoulderHalfWidth, y: Double(shoulder.y))
        let shoulderFar = CGPoint(x: Double(shoulder.x) + spec.shoulderHalfWidth, y: Double(shoulder.y))

        func armJoints(from root: CGPoint, ua: Double, fa: Double) -> (CGPoint, CGPoint) {
            switch spec.arm {
            case .angles:
                let elbow = figureStep(root, ua, L.upperArm)
                return (elbow, figureStep(elbow, fa, L.forearm))
            case .reach(let base, let torsoFrame, let bend):
                var rel = CGPoint(x: p.hx, y: p.hy)
                if torsoFrame { rel = rotate(rel, p.torso) }
                let origin: CGPoint
                switch base {
                case .shoulder: origin = shoulder
                case .hip: origin = hip
                case .world: origin = .zero
                }
                let target = CGPoint(x: origin.x + rel.x, y: origin.y + rel.y)
                let r = reach(from: root, to: target, L.upperArm, L.forearm, bend: bend)
                return (r.joint, r.end)
            }
        }
        let near = armJoints(from: shoulderNear, ua: p.ua, fa: p.fa)
        let far = armJoints(from: shoulderFar, ua: spec.mirrorsFarArm ? -p.ua : p.ua,
                      fa: spec.mirrorsFarArm ? -p.fa : p.fa)
        let elbow = near.0, hand = near.1, elbow2 = far.0, hand2 = far.1

        return LiftFigureJoints(ankle: ankle, knee: knee, hip: hip, hipNear: hipNear, hipFar: hipFar,
                                shoulder: shoulder, shoulderNear: shoulderNear, shoulderFar: shoulderFar,
                                head: head, toe: toe, elbow: elbow, hand: hand, knee2: knee2, ankle2: ankle2,
                                toe2: toe2, elbow2: elbow2, hand2: hand2)
    }
}

/// What the figure is drawn with: plain shapes and a role each, so the view only picks colours.
struct LiftFigureShape: Equatable {
    enum Role { case ground, equipment, cable, plate, weight, farLimb, limb, highlight }
    enum Kind: Equatable {
        case line(CGPoint, CGPoint, width: Double)
        case disc(CGPoint, radius: Double)
        /// A plate seen edge-on from the side: a ring with a filled centre.
        case ring(CGPoint, radius: Double, width: Double)
        case bar(CGRect)
    }
    var kind: Kind
    var role: Role
}

enum LiftFigureDrawing {

    /// The box every frame of the movement fits in, padded so a plate or a head never touches its edge.
    /// Fixed for the movement, so the figure does not breathe with the zoom while it moves.
    static func bounds(_ spec: LiftFigureSpec) -> CGRect {
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        let steps = spec.end == nil ? 0 : 20
        for i in 0...steps {
            let pose = spec.end.map { spec.start.mixed(toward: $0, Double(i) / 20) } ?? spec.start
            for p in LiftFigureSolver.solve(spec, pose).all {
                let x = Double(p.x), y = Double(p.y)
                minX = Swift.min(minX, x); minY = Swift.min(minY, y)
                maxX = Swift.max(maxX, x); maxY = Swift.max(maxY, y)
            }
        }
        let pad = 30.0
        return CGRect(x: minX - pad, y: minY - pad, width: maxX - minX + 2 * pad, height: maxY - minY + 2 * pad)
    }

    /// The shapes of one frame, back to front.
    static func shapes(_ spec: LiftFigureSpec, _ pose: LiftPose, in box: CGRect) -> [LiftFigureShape] {
        let j = LiftFigureSolver.solve(spec, pose)
        let rest = LiftFigureSolver.solve(spec, spec.start)
        var out: [LiftFigureShape] = []
        func figureLine(_ a: CGPoint, _ b: CGPoint, _ w: Double, _ role: LiftFigureShape.Role) {
            out.append(LiftFigureShape(kind: .line(a, b, width: w), role: role))
        }
        func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
            guard w > 0, h > 0 else { return }
            out.append(LiftFigureShape(kind: .bar(CGRect(x: x, y: y, width: w, height: h)), role: .equipment))
        }
        func mid(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
            let ax = Double(a.x), ay = Double(a.y)
            return CGPoint(x: ax + (Double(b.x) - ax) * t, y: ay + (Double(b.y) - ay) * t)
        }
        func role(_ part: LiftFigureHighlight) -> LiftFigureShape.Role {
            spec.highlights.contains(part) ? .highlight : .limb
        }

        // The floor, from the resting pose so it never moves.
        let groundY: Double?
        switch spec.ground {
        case .none: groundY = nil
        case .at(let y): groundY = y
        case .underFeet: groundY = Swift.max(Double(rest.ankle.y), Double(rest.ankle2.y)) + 4
        }
        if let groundY {
            figureLine(CGPoint(x: Double(box.minX) + 4, y: groundY), CGPoint(x: Double(box.maxX) - 4, y: groundY),
                       2, .ground)
        }
        let floor: Double = groundY ?? Double(box.maxY)
        // The resting joints as plain numbers, for the bench's rectangles.
        let sx = Double(rest.shoulder.x), sy = Double(rest.shoulder.y)
        let hx = Double(rest.hip.x), hy = Double(rest.hip.y), kx = Double(rest.knee.x)

        // The bench, also from the resting pose.
        switch spec.bench {
        case .none: break
        case .flat, .prone:
            let left = sx - 16
            let right = spec.bench == .flat ? hx + 14 : kx + 6
            let top = hy + 5
            rect(left, top, right - left, 7)
            rect(sx - 4, top + 7, 5, floor - top - 7)
            rect(spec.bench == .flat ? hx + 2 : kx - 6, top + 7, 5, floor - top - 7)
        case .seat, .incline:
            rect(hx - 14, hy + 5, 40, 7)
            rect(hx + 4, hy + 12, 5, floor - hy - 12)
            if spec.bench == .incline {
                figureLine(CGPoint(x: hx - 4, y: hy + 6), CGPoint(x: sx - 7, y: sy + 4), 7, .equipment)
            }
        case .thrust:
            rect(sx - 30, sy + 6, 40, 7)
            rect(sx - 14, sy + 13, 6, floor - sy - 13)
        }

        // What hangs behind the body: the cable, the pull-up / dip bar, a plate.
        if spec.cable { figureLine(j.hand, CGPoint(x: j.hand.x, y: box.minY + 6), 1.5, .cable) }
        if spec.prop == .bar {
            figureLine(CGPoint(x: j.hand.x - 14, y: j.hand.y), CGPoint(x: j.hand.x + 14, y: j.hand.y), 5, .weight)
        }
        switch spec.prop {
        case .plate: out.append(LiftFigureShape(kind: .ring(j.hand, radius: 17, width: 2.5), role: .plate))
        case .plateOnHip:
            out.append(LiftFigureShape(kind: .ring(CGPoint(x: j.hip.x, y: j.hip.y - 14), radius: 17, width: 2.5),
                                       role: .plate))
        default: break
        }

        // The far limbs, dimmed, then the near ones.
        figureLine(j.ankle2, j.toe2, 6, .farLimb)
        figureLine(j.ankle2, j.knee2, 6, .farLimb)
        figureLine(j.knee2, j.hipFar, 7, .farLimb)
        figureLine(j.shoulderFar, j.elbow2, 6, .farLimb)
        figureLine(j.elbow2, j.hand2, 5, .farLimb)

        figureLine(j.ankle, j.toe, 6, .limb)
        figureLine(j.ankle, j.knee, 6, role(.shin))
        figureLine(j.knee, j.hipNear, 7, role(.thigh))
        if spec.hipHalfWidth != 0 { figureLine(j.hipNear, j.hipFar, 7, .limb) }
        if spec.shoulderHalfWidth != 0 { figureLine(j.shoulderNear, j.shoulderFar, 7, .limb) }
        figureLine(j.hip, j.shoulder, 8, .limb)
        if spec.highlights.contains(.upperTorso) { figureLine(j.shoulder, mid(j.shoulder, j.hip, 0.45), 8, .highlight) }
        if spec.highlights.contains(.lowerTorso) { figureLine(mid(j.shoulder, j.hip, 0.45), j.hip, 8, .highlight) }
        if spec.highlights.contains(.hip) { out.append(LiftFigureShape(kind: .disc(j.hip, radius: 6), role: .highlight)) }
        out.append(LiftFigureShape(kind: .disc(j.head, radius: 10), role: .limb))
        figureLine(j.shoulderNear, j.elbow, 6, role(.upperArm))
        figureLine(j.elbow, j.hand, 5, role(.forearm))
        if spec.highlights.contains(.shoulders) {
            out.append(LiftFigureShape(kind: .disc(j.shoulderNear, radius: 6), role: .highlight))
            if spec.shoulderHalfWidth != 0 {
                out.append(LiftFigureShape(kind: .disc(j.shoulderFar, radius: 6), role: .highlight))
            }
        }

        // What the hands hold, in front.
        switch spec.prop {
        case .dumbbell:
            figureLine(CGPoint(x: j.hand.x - 6, y: j.hand.y), CGPoint(x: j.hand.x + 6, y: j.hand.y), 9, .weight)
        case .dumbbellPair:
            for h in [j.hand, j.hand2] {
                figureLine(CGPoint(x: h.x, y: h.y - 6), CGPoint(x: h.x, y: h.y + 6), 9, .weight)
            }
        case .handle:
            out.append(LiftFigureShape(kind: .disc(j.hand, radius: 4), role: .weight))
        default: break
        }
        if spec.pad { out.append(LiftFigureShape(kind: .disc(j.ankle, radius: 6), role: .weight)) }
        return out
    }
}
