import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Heart rate over the stage lanes (personal fork)
//
// The scaling of the night's one-minute sleeping-HR buckets for the curve `SleepPhasesChart` draws over
// the stage lanes: the lanes' own time axis, a bpm scale of its own, and the night's first lowest rate.

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

/// The persisted switch for the heart-rate curve over the Sleep tab's stage lanes (`SleepPhasesChart`).
enum SleepHROverlay {
    static let enabledKey = "sleep.hrOverlay"
}
