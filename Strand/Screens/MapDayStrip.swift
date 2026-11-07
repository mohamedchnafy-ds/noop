import SwiftUI
import StrandDesign

// MARK: - The day's frise under the Map (personal fork, chantier 14, Carte v2)
//
// The heart rate (five-minute buckets) or the hourly stress of one day, midnight to midnight, with a tick
// under each point kept that day. Dragging a finger along it moves a cursor on the map to where the
// iPhone was at that moment (between two points, on the line joining them); a point touched on the map
// puts its time on the frise. One day, one clock: the frise and the map read the same `selectedTs`.

/// What the frise draws.
enum MapStripMode: String, CaseIterable, Identifiable {
    case heartRate, stress
    var id: String { rawValue }
}

/// One point of the day, for the frise's ticks and the cursor.
struct MapStripPoint: Equatable {
    /// Unix seconds.
    var ts: Int
    var lat: Double
    var lon: Double
}

/// The frise's rules. PURE: tested in `MapDayStripTests`.
enum MapDayStripMath {

    /// Two buckets further apart than this break the heart-rate line (strap off).
    static let hrGapSeconds = 15 * 60
    /// Before the first point or after the last one, the cursor shows for this long at most.
    static let cursorReachSeconds = 30 * 60

    /// The time under `x` on a frise `width` wide running from `dayStart` to `dayEnd`.
    static func stripTime(x: CGFloat, width: CGFloat, dayStart: Int, dayEnd: Int) -> Int {
        guard width > 0 else { return dayStart }
        let share = min(max(Double(x / width), 0), 1)
        return dayStart + Int((share * Double(dayEnd - dayStart)).rounded())
    }

    /// Where `ts` is on the frise, 0…1.
    static func stripShare(_ ts: Int, dayStart: Int, dayEnd: Int) -> Double {
        guard dayEnd > dayStart else { return 0 }
        return min(max(Double(ts - dayStart) / Double(dayEnd - dayStart), 0), 1)
    }

    /// The heart-rate buckets cut into runs at every gap longer than `hrGapSeconds`.
    static func heartRateRuns(_ buckets: [PlaceHRBucket]) -> [[PlaceHRBucket]] {
        var runs: [[PlaceHRBucket]] = []
        var current: [PlaceHRBucket] = []
        for bucket in buckets.sorted(by: { $0.ts < $1.ts }) {
            if let last = current.last, bucket.ts - last.ts > hrGapSeconds {
                runs.append(current)
                current = []
            }
            current.append(bucket)
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    /// Where the iPhone was at `ts`: on the straight line between the two points around it when they
    /// are less than `LayeredMapGeometry.pathBreakSeconds` apart, else at the nearest point within
    /// `cursorReachSeconds`; nil when no point is that close.
    static func cursorPosition(at ts: Int, points: [MapStripPoint]) -> LayeredMapCursor? {
        let sorted = points.sorted { $0.ts < $1.ts }
        guard let first = sorted.first, let last = sorted.last else { return nil }
        if ts <= first.ts {
            return first.ts - ts <= cursorReachSeconds ? LayeredMapCursor(lat: first.lat, lon: first.lon) : nil
        }
        if ts >= last.ts {
            return ts - last.ts <= cursorReachSeconds ? LayeredMapCursor(lat: last.lat, lon: last.lon) : nil
        }
        guard let next = sorted.firstIndex(where: { $0.ts >= ts }), next > 0 else { return nil }
        let a = sorted[next - 1], b = sorted[next]
        if Int64(b.ts - a.ts) <= LayeredMapGeometry.pathBreakSeconds, b.ts > a.ts {
            let f = Double(ts - a.ts) / Double(b.ts - a.ts)
            return LayeredMapCursor(lat: a.lat + (b.lat - a.lat) * f, lon: a.lon + (b.lon - a.lon) * f)
        }
        let nearest = ts - a.ts <= b.ts - ts ? a : b
        return abs(nearest.ts - ts) <= cursorReachSeconds ? LayeredMapCursor(lat: nearest.lat, lon: nearest.lon) : nil
    }

    /// The stress window holding `ts`.
    static func stressWindow(at ts: Int, in windows: [PlaceStressWindow]) -> PlaceStressWindow? {
        windows.first { ts >= $0.start && ts < $0.end }
    }
}

struct MapDayStrip: View {
    let timeline: PlaceDayTimeline
    let mode: MapStripMode
    let points: [MapStripPoint]
    /// The moment shown (unix seconds), nil when none.
    @Binding var selectedTs: Int?

    private let chartHeight: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: readout)
                .font(StrandFont.number(13, weight: .semibold))
                .foregroundStyle(selectedTs == nil ? StrandPalette.textSecondary : StrandPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    grid(width: geometry.size.width)
                    switch mode {
                    case .heartRate: heartRateLine(size: geometry.size)
                    case .stress: stressBars(size: geometry.size)
                    }
                    pointTicks(width: geometry.size.width)
                    if let ts = selectedTs { marker(ts, size: geometry.size) }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    selectedTs = MapDayStripMath.stripTime(x: value.location.x, width: geometry.size.width,
                                                           dayStart: timeline.dayStart, dayEnd: timeline.dayEnd)
                })
            }
            .frame(height: chartHeight + 10)
            axis
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: readout))
    }

    // MARK: Readout

    private var readout: String {
        guard let ts = selectedTs else { return String(localized: "Drag along the day to follow it on the map") }
        let time = Date(timeIntervalSince1970: TimeInterval(ts)).formatted(date: .omitted, time: .shortened)
        switch mode {
        case .heartRate:
            guard let bpm = PlaceMetrics.heartRateAt(ts, buckets: timeline.heartRate) else {
                return time + " · " + String(localized: "No heart rate")
            }
            return time + " · " + String(localized: "\(Int(bpm.rounded())) bpm")
        case .stress:
            guard let window = MapDayStripMath.stressWindow(at: ts, in: timeline.stress) else {
                return time + " · " + String(localized: "Not scored")
            }
            if window.moving { return time + " · " + String(localized: "Moving") }
            guard let level = window.level else { return time + " · " + String(localized: "Not scored") }
            return time + " · " + TodayStressLogic.bandName(StressBand(score: level))
        }
    }

    // MARK: Drawing

    private func x(_ ts: Int, width: CGFloat) -> CGFloat {
        CGFloat(MapDayStripMath.stripShare(ts, dayStart: timeline.dayStart, dayEnd: timeline.dayEnd)) * width
    }

    private func grid(width: CGFloat) -> some View {
        Path { path in
            for hour in stride(from: 0, through: 24, by: 6) {
                let px = width * CGFloat(hour) / 24
                path.move(to: CGPoint(x: px, y: 0))
                path.addLine(to: CGPoint(x: px, y: chartHeight))
            }
        }
        .stroke(StrandPalette.hairline, lineWidth: 1)
    }

    private func heartRateLine(size: CGSize) -> some View {
        let values = timeline.heartRate.map(\.bpm)
        let low = (values.min() ?? 50) - 5
        let high = max((values.max() ?? 120) + 5, low + 20)
        let runs = MapDayStripMath.heartRateRuns(timeline.heartRate)
        return Path { path in
            for run in runs {
                for (index, bucket) in run.enumerated() {
                    let point = CGPoint(x: x(bucket.ts + 150, width: size.width),
                                        y: chartHeight * CGFloat(1 - (bucket.bpm - low) / (high - low)))
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
        }
        .stroke(StrandPalette.metricRose, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
    }

    private func stressBars(size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(timeline.stress.enumerated()), id: \.offset) { _, window in
                let left = x(window.start, width: size.width)
                let width = max(1, x(window.end, width: size.width) - left - 1)
                if window.moving {
                    Rectangle().fill(StrandPalette.stressMoving.opacity(0.6))
                        .frame(width: width, height: chartHeight * 0.25)
                        .offset(x: left, y: chartHeight * 0.75)
                } else if let level = window.level {
                    let share = CGFloat(min(max(level / 3, 0.08), 1))
                    Rectangle().fill(stressColor(level))
                        .frame(width: width, height: chartHeight * share)
                        .offset(x: left, y: chartHeight * (1 - share))
                }
            }
        }
    }

    private func stressColor(_ level: Double) -> Color {
        switch StressBand(score: level) {
        case .low: return StrandPalette.stressCalm
        case .medium: return StrandPalette.stressModerate
        case .high: return StrandPalette.stressHigh
        }
    }

    private func pointTicks(width: CGFloat) -> some View {
        Path { path in
            for point in points {
                let px = x(point.ts, width: width)
                path.addEllipse(in: CGRect(x: px - 2, y: chartHeight + 4, width: 4, height: 4))
            }
        }
        .fill(StrandPalette.textSecondary)
    }

    private func marker(_ ts: Int, size: CGSize) -> some View {
        let px = x(ts, width: size.width)
        return Path { path in
            path.move(to: CGPoint(x: px, y: 0))
            path.addLine(to: CGPoint(x: px, y: chartHeight + 8))
        }
        .stroke(StrandPalette.textPrimary, lineWidth: 1.5)
    }

    /// « 06:00 », « 24:00 ».
    static func axisHourLabel(_ hour: Int) -> String {
        (hour < 10 ? "0" : "") + String(hour) + ":00"
    }

    private var axis: some View {
        HStack {
            ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                Text(verbatim: Self.axisHourLabel(hour))
                    .font(StrandFont.caption2)
                    .foregroundStyle(StrandPalette.textTertiary)
                if hour < 24 { Spacer(minLength: 0) }
            }
        }
    }
}
