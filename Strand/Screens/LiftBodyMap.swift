import SwiftUI
import StrandDesign
import WhoopStore

// A front or back body map, each muscle coloured by its weekly sets (personal fork).
//
// Built from plain shapes (capsules, ellipses and a few soft paths), one or two per muscle, drawn in a
// 150 × 316 box and mirrored for the other side, over a body silhouette. The geometry is the one in the
// « NOOP – Progression (Carnet de force) » mockups. Each muscle is its own shape so a tap can open it.

struct LiftBodyMap: View {
    enum Side { case front, back }

    let side: Side
    /// Weekly sets per muscle; a muscle absent from the map reads 0.
    let sets: [LiftMuscle: Double]
    /// Muscles drawn with the priority outline.
    var highlighted: Set<LiftMuscle> = []
    var onTap: ((LiftMuscle) -> Void)?

    static let canvas = CGSize(width: 150, height: 316)

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / Self.canvas.width
            ZStack(alignment: .topLeading) {
                ForEach(Array(LiftBodyGeometry.silhouette.enumerated()), id: \.offset) { _, path in
                    LiftBodyShape(outline: path).fill(LiftBodyMapStyle.silhouette)
                }
                ForEach(pieces, id: \.id) { piece in
                    let hot = highlighted.contains(piece.muscle)
                    LiftBodyShape(outline: piece.path)
                        .fill(LiftBodyMapStyle.color(sets[piece.muscle] ?? 0))
                        .overlay(LiftBodyShape(outline: piece.path)
                            .stroke(hot ? StrandPalette.statusWarning : LiftBodyMapStyle.silhouette,
                                    style: StrokeStyle(lineWidth: (hot ? 2.2 : 2) * scale, lineJoin: .round)))
                        .contentShape(LiftBodyShape(outline: piece.path))
                        .onTapGesture { onTap?(piece.muscle) }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(Self.canvas.width / Self.canvas.height, contentMode: .fit)
    }

    /// Every muscle piece of this side, mirrored pairs included; highlighted muscles last so their
    /// outline is never covered by a neighbour.
    private var pieces: [LiftBodyPiece] {
        let all = LiftBodyGeometry.pieces(side)
        return all.filter { !highlighted.contains($0.muscle) } + all.filter { highlighted.contains($0.muscle) }
    }
}

/// One muscle shape, in the 150 × 316 drawing box.
struct LiftBodyPiece {
    let id: String
    let muscle: LiftMuscle
    let path: Path
}

/// A path drawn in the 150 × 316 box, scaled to whatever frame it is given.
struct LiftBodyShape: Shape {
    let outline: Path

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / LiftBodyMap.canvas.width
        let sy = rect.height / LiftBodyMap.canvas.height
        return outline.applying(CGAffineTransform(scaleX: sx, y: sy).translatedBy(x: rect.minX / sx, y: rect.minY / sy))
    }
}

/// The map's colours, all from the palette: a blue ramp in the Lift Log's Effort colour world.
enum LiftBodyMapStyle {
    static var silhouette: Color { StrandPalette.hairline }

    /// Upper bounds (exclusive) of the bands, and their colours, lightest last.
    static var bands: [(upper: Double, color: Color, label: String)] {
        [(0.01, StrandPalette.textTertiary.opacity(0.45), "0"),
         (2, StrandPalette.effortDeep.opacity(0.6), "< 2"),
         (4, StrandPalette.effortDeep, "2–4"),
         (8, StrandPalette.effortColor, "4–8"),
         (12, StrandPalette.effortBright, "8–12"),
         (Double.greatestFiniteMagnitude, StrandPalette.goldLight, "12+")]
    }

    static func color(_ sets: Double) -> Color {
        bands.first { sets < $0.upper }?.color ?? StrandPalette.goldLight
    }
}

/// The shapes. Left side only (x < 75) for paired muscles, mirrored for the right; centre pieces once.
enum LiftBodyGeometry {
    private enum Spec {
        case capsule(CGFloat, CGFloat, CGFloat, CGFloat, rotation: CGFloat)
        case ellipse(CGFloat, CGFloat, CGFloat, CGFloat, rotation: CGFloat)
        case svg(String)

        var path: Path {
            switch self {
            case let .capsule(x, y, w, h, rotation):
                let rect = CGRect(x: x, y: y, width: w, height: h)
                return Path(roundedRect: rect, cornerRadius: min(w, h) / 2)
                    .applying(rotate(rotation, about: CGPoint(x: rect.midX, y: rect.midY)))
            case let .ellipse(cx, cy, rx, ry, rotation):
                return Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
                    .applying(rotate(rotation, about: CGPoint(x: cx, y: cy)))
            case let .svg(d):
                return LiftBodyGeometry.parse(d)
            }
        }

        private func rotate(_ degrees: CGFloat, about c: CGPoint) -> CGAffineTransform {
            CGAffineTransform(translationX: c.x, y: c.y)
                .rotated(by: degrees * .pi / 180)
                .translatedBy(x: -c.x, y: -c.y)
        }
    }

    private static let mirror = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: LiftBodyMap.canvas.width, ty: 0)

    private static let frontSide: [(LiftMuscle, [Spec])] = [
        (.traps, [.svg("M67 41 C63 46 57 49 50 51 L52 55 L67 51 Z")]),
        (.sideDelts, [.ellipse(39, 65, 6.5, 11.5, rotation: 12)]),
        (.frontDelts, [.ellipse(50, 61, 7.5, 9.5, rotation: -14)]),
        (.chest, [.svg("M74 57 L74 83 C66 87 58 85 54.5 78 C52 71 54 62 59.5 57.5 Z")]),
        (.biceps, [.capsule(33.5, 77, 11, 31, rotation: 9)]),
        (.forearms, [.capsule(28, 111, 10, 35, rotation: 13)]),
        (.obliques, [.capsule(54.5, 88, 8.5, 40, rotation: -5)]),
        (.abs, [.capsule(64.5, 88, 9.5, 12.5, rotation: 0), .capsule(64.5, 102, 9.5, 12.5, rotation: 0),
                .capsule(64.5, 116, 9.5, 15, rotation: 0)]),
        (.abductors, [.ellipse(55, 142, 5.5, 10, rotation: -8)]),
        (.quads, [.svg("M57.5 136 C62 133 67.5 133 70 137 L71 194 C69.5 204 61.5 205 59 198 C55.5 180 55 154 57.5 136 Z")]),
        (.adductors, [.svg("M71.5 137 L75 137 L74.5 172 C73.5 176 72 173 71.5 166 Z")]),
        (.calves, [.capsule(57.5, 215, 11, 45, rotation: -2)]),
    ]

    private static let backSide: [(LiftMuscle, [Spec])] = [
        (.sideDelts, [.ellipse(39, 65, 6.5, 11.5, rotation: 12)]),
        (.rearDelts, [.ellipse(50.5, 60.5, 7.5, 8.5, rotation: -10)]),
        (.upperBack, [.svg("M58 57 L69 61 L69.5 80 L59 77 C56 71 55.5 63 58 57 Z")]),
        (.lats, [.svg("M55 80 C60 85 67 98 72.5 112 L72.5 124 C63 118 55 105 51.5 92 C50.5 86 51.5 81 55 80 Z")]),
        (.triceps, [.capsule(33, 75, 12, 32, rotation: 9)]),
        (.forearms, [.capsule(28, 111, 10, 35, rotation: 13)]),
        (.lowerBack, [.capsule(67, 95, 7, 36, rotation: 0)]),
        (.abductors, [.ellipse(55.5, 129, 6, 7.5, rotation: -10)]),
        (.glutes, [.svg("M58 134 C64 131 72 132 74 135 L74 154 C68 159 60 158 57.5 152 C55.5 146 55.5 139 58 134 Z")]),
        (.hamstrings, [.svg("M58.5 160 C63 158 69 158 71 161 L70.5 200 C68 206 61 206 59.5 200 C57.5 186 57 172 58.5 160 Z")]),
        (.calves, [.svg("M57.5 216 C61 211 68 211 71 216 C73 228 71 246 66 258 C63 260 61 259 60 256 C56 244 55 228 57.5 216 Z")]),
    ]

    private static let neck: Spec = .capsule(69, 33, 12, 13, rotation: 0)
    private static let backTraps: Spec = .svg(
        "M75 37 C70 44 64 48 57 51 L60 54 C65 55 69 58 71 62 L75 86 L79 62 C81 58 85 55 90 54 L93 51 C86 48 80 44 75 37 Z")

    /// The muscle pieces of one side.
    static func pieces(_ side: LiftBodyMap.Side) -> [LiftBodyPiece] {
        let paired = side == .front ? frontSide : backSide
        var out: [LiftBodyPiece] = []
        for (muscle, specs) in paired {
            for (index, spec) in specs.enumerated() {
                let path = spec.path
                out.append(LiftBodyPiece(id: "\(muscle.rawValue)-\(index)-l", muscle: muscle, path: path))
                out.append(LiftBodyPiece(id: "\(muscle.rawValue)-\(index)-r", muscle: muscle,
                                         path: path.applying(mirror)))
            }
        }
        out.append(LiftBodyPiece(id: "neck", muscle: .neck, path: neck.path))
        if side == .back {
            out.append(LiftBodyPiece(id: "traps-back", muscle: .traps, path: backTraps.path))
        }
        return out
    }

    /// The body under the muscles: head, trunk, arms, legs, hands and feet, both sides.
    static let silhouette: [Path] = {
        let half: [Spec] = [
            .svg("M75 44 L67 44 C60 48 52 50 45 52 L42 56 L46 78 L52 90 L53.5 128 C52 136 51.5 142 53 148 L75 150 Z"),
            .ellipse(43, 64, 11, 13.5, rotation: 8),
            .capsule(31.5, 70, 15, 44, rotation: 9),
            .capsule(25.5, 106, 13.5, 44, rotation: 13),
            .svg("M53.5 130 C61 127 71 128 76 133 L75.5 200 C74 211 60 213 57 203 C52.5 182 51.5 154 53.5 130 Z"),
            .svg("M57 200 C61 196 70 197 72 202 C74 224 72 248 69 262 L69.5 300 L58.5 300 L58.5 262 C54 246 54 222 57 200 Z"),
            .ellipse(26, 153, 5.5, 7, rotation: 12),
            .ellipse(63.5, 303, 7.5, 4, rotation: 0),
        ]
        let left = half.map(\.path)
        return [Path(ellipseIn: CGRect(x: 62, y: 5, width: 26, height: 26))] + left + left.map { $0.applying(LiftBodyGeometry.mirror) }
    }()

    /// A path from absolute SVG commands (M, L, C, Z), the only ones the geometry above uses.
    static func parse(_ d: String) -> Path {
        var tokens: [String] = []
        var current = ""
        for ch in d {
            if ch.isLetter {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(ch))
            } else if ch == " " || ch == "," {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }

        var path = Path()
        var index = 0
        var command = "M"
        func number() -> CGFloat {
            defer { index += 1 }
            return index < tokens.count ? CGFloat(Double(tokens[index]) ?? 0) : 0
        }
        func point() -> CGPoint {
            let x = number()
            let y = number()
            return CGPoint(x: x, y: y)
        }
        while index < tokens.count {
            if let first = tokens[index].first, first.isLetter {
                command = tokens[index]
                index += 1
                if command == "Z" { path.closeSubpath(); continue }
            }
            switch command {
            case "M":
                path.move(to: point())
                command = "L"
            case "L":
                path.addLine(to: point())
            case "C":
                let c1 = point()
                let c2 = point()
                let end = point()
                path.addCurve(to: end, control1: c1, control2: c2)
            default:
                index += 1
            }
        }
        return path
    }
}
