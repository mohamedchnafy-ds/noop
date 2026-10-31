import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Heart rate over the stepped hypnogram (personal fork)
//
// The Filled / Ribbon sleep chart had no heart-rate read, while the Classic rows carry `SleepHRChart`
// above them. This draws the night's one-minute sleeping-HR buckets as a thin line OVER the stepped
// hypnogram, on the hypnogram's own time axis and a bpm scale of its own, with the night's lowest rate
// marked. It is a transparent, hit-test-free layer, so the hypnogram's hover and stage highlight keep
// working underneath it.

/// The geometry, kept pure so `SleepHROverlayTests` can pin it without a view.
enum SleepHROverlayMath {
    /// A plotted bucket: x and y as fractions of the plot (y = 0 at the top).
    struct Point: Equatable {
        let xFrac: Double
        let yFrac: Double
        let bpm: Double
    }

    struct Layout: Equatable {
        let points: [Point]
        /// Index into `points` of the night's lowest rate, when there is one.
        let minIndex: Int?
        /// The bpm scale the points were placed on, padded so the line never touches the edges.
        let lo: Double
        let hi: Double
    }

    /// Scale padding on each side of the night's range, in bpm.
    static let pad: Double = 4
    /// The line keeps to the band between these fractions of the plot height, leaving the lane labels
    /// and the stepped bands' edges readable; the hypnogram is the chart, the line a reading on it.
    static let topInset: Double = 0.08
    static let bottomInset: Double = 0.12

    /// Buckets inside the visible window (plus one minute of slack on each side so the line reaches the
    /// edges), placed on the hypnogram's `origin`/`span` axis. `nightStartTs` is the wall-clock second
    /// the hypnogram's `origin` is measured from.
    static func layout(buckets: [HRBucket], nightStartTs: Double, origin: Double, span: Double) -> Layout? {
        let visible = buckets.filter {
            let rel = Double($0.ts) - nightStartTs
            return rel >= origin - 60 && rel <= origin + span + 60
        }
        guard visible.count >= 2, span > 0 else { return nil }
        let bpms = visible.map(\.bpm)
        let lo = (bpms.min() ?? 40) - pad
        let hi = (bpms.max() ?? 90) + pad
        let range = max(1, hi - lo)
        let band = 1 - topInset - bottomInset
        let points = visible.map { b -> Point in
            let x = (Double(b.ts) - nightStartTs - origin) / span
            let y = topInset + (1 - (b.bpm - lo) / range) * band
            return Point(xFrac: max(0, min(1, x)), yFrac: y, bpm: b.bpm)
        }
        // The FIRST lowest reading: a night that bottoms out twice marks where it first got there.
        let minIndex = points.indices.min { points[$0].bpm < points[$1].bpm }
        return Layout(points: points, minIndex: minIndex, lo: lo, hi: hi)
    }
}

struct SleepHROverlay: View {
    /// The on/off switch for the line, shared by the card's button and whoever else wants to read it.
    static let enabledKey = "sleep.hrOverlay"

    let nightHR: [HRBucket]
    let nightStart: Date
    /// The hypnogram's visible window, as seconds after `nightStart`.
    let origin: TimeInterval
    let span: TimeInterval
    var tint: Color = StrandPalette.liquidHeart

    var body: some View {
        Canvas { ctx, size in
            guard let layout = SleepHROverlayMath.layout(buckets: nightHR,
                                                        nightStartTs: nightStart.timeIntervalSince1970,
                                                        origin: origin, span: span) else { return }
            func point(_ p: SleepHROverlayMath.Point) -> CGPoint {
                CGPoint(x: CGFloat(p.xFrac) * size.width, y: CGFloat(p.yFrac) * size.height)
            }
            var path = Path()
            for (i, p) in layout.points.enumerated() {
                if i == 0 { path.move(to: point(p)) } else { path.addLine(to: point(p)) }
            }
            // A dark halo under the line so it stays legible over a filled stage band of any colour.
            ctx.stroke(path, with: .color(StrandPalette.surfaceBase.opacity(0.55)),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            ctx.stroke(path, with: .color(tint.opacity(0.9)),
                       style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))

            // The night's lowest rate: a dot and its value, kept inside the plot.
            if let i = layout.minIndex {
                let p = layout.points[i]
                let c = point(p)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3.5, y: c.y - 3.5, width: 7, height: 7)),
                         with: .color(tint))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 1.5, y: c.y - 1.5, width: 3, height: 3)),
                         with: .color(StrandPalette.surfaceBase))
                let label = Text("\(Int(p.bpm.rounded())) bpm")
                    .font(StrandFont.captionNumber)
                    .foregroundColor(tint)
                let resolved = ctx.resolve(label)
                let labelSize = resolved.measure(in: size)
                let onLeftHalf = c.x < size.width / 2
                let x = onLeftHalf ? c.x + 8 : c.x - 8 - labelSize.width
                let y = min(size.height - labelSize.height, c.y + 6)
                ctx.fill(Path(roundedRect: CGRect(x: x - 3, y: y - 1, width: labelSize.width + 6,
                                                  height: labelSize.height + 2), cornerRadius: 3),
                         with: .color(StrandPalette.surfaceBase.opacity(0.8)))
                ctx.draw(resolved, at: CGPoint(x: x, y: y), anchor: .topLeading)
            }

            // The scale: top and bottom of the bpm range at the right edge, so the line's height means
            // something without an axis column.
            let hiText = ctx.resolve(Text("\(Int(layout.hi.rounded()))")
                .font(StrandFont.caption).foregroundColor(tint.opacity(0.8)))
            let loText = ctx.resolve(Text("\(Int(layout.lo.rounded()))")
                .font(StrandFont.caption).foregroundColor(tint.opacity(0.8)))
            ctx.draw(hiText, at: CGPoint(x: size.width - 2,
                                         y: CGFloat(SleepHROverlayMath.topInset) * size.height),
                     anchor: .topTrailing)
            ctx.draw(loText, at: CGPoint(x: size.width - 2,
                                         y: CGFloat(1 - SleepHROverlayMath.bottomInset) * size.height),
                     anchor: .bottomTrailing)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
