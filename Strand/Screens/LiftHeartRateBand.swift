import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopProtocol
import WhoopStore

// The heart-rate band of a strength session (fork chantier 18, maquette 3): under the exercise's name on the
// session sheet and under a superset's tiles, the live heart rate with its zone, the curve of the last ten
// minutes (rests in amber, the end of each set as a tick), the two previous sessions of the same program in
// dashed grey behind it (« Compare », remembered), and three figures: average, max, recovery between sets.
//
// `LiftHeartRateBand` is pure (values in) so it can be drawn without a strap; `LiftLiveHeartRateBand` feeds it
// from the strap's recorded heart rate, every ten seconds, the curve's own bucket.

/// The remembered « Compare » switch, shared by the live band, the finished session and the live workout.
enum LiftHeartRateCompare {
    static let key = "lift.hr.compare"
}

struct LiftHeartRateBand: View {

    struct Content: Equatable {
        var bpm: Int?
        /// 1…5, 0 below zone 1.
        var zone: Int
        var isResting: Bool
        /// The window's heart rate, one value per bucket, nil where there is no sample.
        var curve: [Double?]
        /// The previous sessions' curves in the same buckets, empty when there is nothing to compare.
        var comparisons: [[Double?]]
        /// The rests inside the window and the end of each set, as fractions of it.
        var rests: [ClosedRange<Double>]
        var setEnds: [Double]
        var average: Int?
        var peak: Int?
        /// The recovery of the rest running now, else of the last rest.
        var recovery: Int?
        var recoveryIsLive: Bool
        /// A running session: the live number heads the band. A finished one shows no header, so its
        /// average is stated once, in the figures.
        var isLive: Bool = true
        /// False where the screen already states the session's average (a superset's tiles), so it is
        /// not stated twice from two refreshes.
        var showsAverage: Bool = true
        /// No heart rate at all: live, the band says it is waiting for the strap.
        var waiting: Bool { bpm == nil && curve.allSatisfy { $0 == nil } }
    }

    let content: Content
    @Binding var compare: Bool
    /// The caption under the curve, start and end ("10 min ago" / "now", or "0 min" / "52 min").
    var leading: Text = Text("10 min ago")
    var trailing: Text = Text("now")

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            if content.isLive { header }
            if content.waiting {
                Group {
                    if content.isLive {
                        Text("Waiting for the strap's heart rate.")
                    } else {
                        Text("No heart rate was recorded during this session.")
                    }
                }
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                LiftHeartRateCurve(curve: content.curve,
                                   comparisons: compare ? content.comparisons : [],
                                   rests: content.rests, setEnds: content.setEnds)
                    .frame(height: 84)
                    .accessibilityHidden(true)
                HStack {
                    leading
                    Spacer(minLength: NoopMetrics.space2)
                    trailing
                }
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                if !content.comparisons.isEmpty {
                    Toggle(isOn: $compare) {
                        Text("Compare with the last 2 sessions")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                figures
            }
        }
        .padding(NoopMetrics.space3)
        .background(StrandPalette.metricRose.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius - 4, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: NoopMetrics.space2) {
            Image(systemName: "heart.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(content.bpm == nil ? StrandPalette.textTertiary : StrandPalette.metricRose)
            Text(verbatim: content.bpm.map(String.init) ?? "—")
                .font(StrandFont.number(22, weight: .bold))
                .foregroundStyle(StrandPalette.textPrimary)
            Text("bpm")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
            Spacer(minLength: NoopMetrics.space2)
            if content.zone >= 1 {
                Text("Z\(content.zone)")
                    .font(StrandFont.captionNumber.weight(.bold))
                    .foregroundStyle(StrandPalette.hrZoneColor(content.zone))
            }
            Group {
                if content.isResting { Text("recovering") } else { Text("in the set") }
            }
            .font(StrandFont.caption)
            .foregroundStyle(StrandPalette.textSecondary)
        }
    }

    private var figures: some View {
        HStack(spacing: NoopMetrics.space2) {
            if content.showsAverage {
                figure(content.average.map(String.init) ?? "—", Text("Average"))
            }
            figure(content.peak.map(String.init) ?? "—", Text("Max"))
            figure(content.recovery.map { "−\($0)" } ?? "—",
                   content.recoveryIsLive ? Text("Recovery · now") : Text("Recovery · last"))
        }
    }

    private func figure(_ value: String, _ label: Text) -> some View {
        VStack(spacing: NoopMetrics.spaceHalf) {
            Text(verbatim: value)
                .font(StrandFont.number(18, weight: .bold))
                .foregroundStyle(StrandPalette.textPrimary)
            label
                .font(StrandFont.caption2)
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The curve: the window's heart rate in pink, earlier sessions dashed in grey behind it, the rests as amber
/// bands and the end of each set as a thin tick. Scaled to everything it draws, with a little room.
struct LiftHeartRateCurve: View {
    let curve: [Double?]
    let comparisons: [[Double?]]
    let rests: [ClosedRange<Double>]
    let setEnds: [Double]

    var body: some View {
        GeometryReader { proxy in
            let known = (curve + comparisons.flatMap { $0 }).compactMap { $0 }
            let low = (known.min() ?? 60) - 4
            let high = max((known.max() ?? 120) + 4, low + 10)
            let width = proxy.size.width, height = proxy.size.height
            ZStack(alignment: .topLeading) {
                ForEach(rests.indices, id: \.self) { index in
                    let rest = rests[index]
                    Rectangle()
                        .fill(StrandPalette.metricAmber.opacity(0.18))
                        .frame(width: max(1, CGFloat(rest.upperBound - rest.lowerBound) * width), height: height)
                        .offset(x: CGFloat(rest.lowerBound) * width)
                }
                ForEach(setEnds.indices, id: \.self) { index in
                    let end = setEnds[index]
                    Rectangle()
                        .fill(StrandPalette.textSecondary.opacity(0.6))
                        .frame(width: 1, height: height)
                        .offset(x: CGFloat(end) * width)
                }
                ForEach(comparisons.indices, id: \.self) { index in
                    Self.path(comparisons[index], width: width, height: height, low: low, high: high)
                        .stroke(StrandPalette.textTertiary,
                                style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [3, 3]))
                }
                Self.path(curve, width: width, height: height, low: low, high: high)
                    .stroke(StrandPalette.metricRose,
                            style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }
        }
    }

    /// One line, broken where a bucket has no sample.
    static func path(_ values: [Double?], width: CGFloat, height: CGFloat, low: Double, high: Double) -> Path {
        Path { path in
            let step = values.count > 1 ? width / CGFloat(values.count - 1) : 0
            var drawing = false
            for (index, value) in values.enumerated() {
                guard let value else { drawing = false; continue }
                let point = CGPoint(x: CGFloat(index) * step,
                                    y: height * CGFloat(1 - (value - low) / (high - low)))
                if drawing { path.addLine(to: point) } else { path.move(to: point) }
                drawing = true
            }
        }
    }
}

/// The live band of a running session: the number from `AppModel.bpm`, the curve and the figures from the
/// strap's recorded heart rate since the session began, re-read every `refreshSec`. The previous sessions of
/// the same program are read once. Its own view, so the beats and the refresh redraw this band alone.
struct LiftLiveHeartRateBand: View {
    /// What the band needs from the session, taken when the session changes (a set done, a rest started).
    struct Session: Equatable {
        var startTs: Int
        var programId: String?
        var isResting: Bool
        var sets: [LiftHeartRateMath.SetSpan]
    }

    let session: Session
    /// See `LiftHeartRateBand.Content.showsAverage`.
    var showsAverage = true

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var repo: Repository
    @AppStorage(LiftHeartRateCompare.key) private var compare = true
    @State private var samples: [HRSample] = []
    @State private var previous: [(start: Int, samples: [HRSample])] = []
    @State private var now = Int(Date().timeIntervalSince1970)

    static let refreshSec: UInt64 = 10

    var body: some View {
        LiftHeartRateBand(content: content, compare: $compare)
            .task(id: session.startTs) {
                previous = await LiftHeartRateHistory.previousSessions(
                    repo: repo, programId: session.programId, before: session.startTs)
                while !Task.isCancelled {
                    now = Int(Date().timeIntervalSince1970)
                    samples = await repo.hrSamples(from: session.startTs, to: now)
                    try? await Task.sleep(nanoseconds: Self.refreshSec * 1_000_000_000)
                }
            }
    }

    private var content: LiftHeartRateBand.Content {
        let window = LiftHeartRateMath.liveWindowSec
        let bucket = LiftHeartRateMath.liveBucketSec
        let from = now - window
        let elapsed = now - session.startTs
        let stats = LiftHeartRateMath.averageAndPeak(samples)
        let live = session.isResting ? session.sets.last : nil
        let liveRecovery = live.flatMap { LiftHeartRateMath.recovery(after: $0, samples: samples, now: now) }
        let done = session.sets.filter { $0.restSec != nil }
        let lastRecovery = done.last.flatMap { LiftHeartRateMath.recovery(after: $0, samples: samples, now: now) }
        return LiftHeartRateBand.Content(
            bpm: model.bpm,
            zone: model.bpm.map { model.profile.hrZoneSet.zoneNumber(forBPM: Double($0)) } ?? 0,
            isResting: session.isResting,
            curve: LiftHeartRateMath.bucketCurve(samples, from: from, to: now, bucket: bucket),
            comparisons: previous.map {
                LiftHeartRateMath.alignedCurve($0.samples, sessionStart: $0.start,
                                               fromElapsed: elapsed - window, toElapsed: elapsed, bucket: bucket)
            }.filter { $0.contains { $0 != nil } },
            rests: LiftHeartRateMath.restSpans(session.sets, from: from, to: now, now: now),
            setEnds: session.sets.compactMap { LiftHeartRateMath.fraction($0.end, from: from, to: now) },
            average: stats?.average,
            peak: stats?.peak,
            recovery: liveRecovery ?? lastRecovery,
            recoveryIsLive: liveRecovery != nil,
            showsAverage: showsAverage)
    }
}

/// The earlier sessions a band compares with: the last `LiftHeartRateMath.comparedSessions` finished
/// sessions of the same program before this one, each with its heart rate. None for a freehand session.
enum LiftHeartRateHistory {
    /// How far back the comparison looks.
    static let lookbackDays = 120

    static func previousSessions(repo: Repository, programId: String?,
                                 before start: Int) async -> [(start: Int, samples: [HRSample])] {
        guard let programId, let store = await repo.storeHandle() else { return [] }
        let rows = (try? await store.liftSessions(deviceId: repo.deviceId,
                                                  fromTs: start - lookbackDays * 86_400, toTs: start - 1)) ?? []
        let picked = rows
            .filter { $0.programId == programId && $0.endTs != nil && $0.startTs < start }
            .sorted { $0.startTs > $1.startTs }
            .prefix(LiftHeartRateMath.comparedSessions)
        var out: [(start: Int, samples: [HRSample])] = []
        for row in picked {
            guard let end = row.endTs else { continue }
            out.append((row.startTs, await repo.hrSamples(from: row.startTs, to: end)))
        }
        return out
    }
}

/// The heart rate of a finished session (fork chantier 18, maquette 3, « fiche terminée »): the curve of the
/// whole session with its rests and the ends of its sets, the two previous sessions of the same program
/// dashed behind it, average · max · mean recovery, the time in each zone, and each exercise's average.
/// Read once from the strap's recorded heart rate over the session's window; nothing is stored.
struct LiftSessionHeartRateSection: View {
    let session: LiftSessionRow
    let sets: [LiftSetRow]

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var repo: Repository
    @AppStorage(LiftHeartRateCompare.key) private var compare = true
    @State private var samples: [HRSample] = []
    @State private var previous: [(start: Int, samples: [HRSample])] = []
    @State private var loaded = false
    @State private var waterMl = 0

    /// About this many points across the whole session, never finer than the live curve's bucket.
    static let targetPoints = 120

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Heart rate", overline: "From the strap")
            if loaded {
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        LiftHeartRateBand(content: content, compare: $compare,
                                          leading: Text(String(localized: "\(0) min")),
                                          trailing: Text(String(localized: "\(durationSec / 60) min")))
                        if !samples.isEmpty {
                            zonesRow
                            byExercise
                        }
                        // Fork chantier 18, lot C: the water logged during the session (« + glass »).
                        if waterMl > 0 {
                            HStack(spacing: NoopMetrics.space2) {
                                Image(systemName: "drop.fill")
                                    .foregroundStyle(StrandPalette.accent)
                                Text("Water during the session")
                                    .font(StrandFont.subhead)
                                    .foregroundStyle(StrandPalette.textPrimary)
                                Spacer(minLength: NoopMetrics.space2)
                                Text(String(localized: "\(waterMl / 10) cl"))
                                    .font(StrandFont.captionNumber)
                                    .foregroundStyle(StrandPalette.textSecondary)
                            }
                        }
                    }
                }
            }
        }
        .task(id: session.id) { await load() }
    }

    private var end: Int { session.endTs ?? session.startTs }
    private var durationSec: Int { max(0, end - session.startTs) }
    private var bucket: Int {
        max(LiftHeartRateMath.liveBucketSec, Int((Double(durationSec) / Double(Self.targetPoints)).rounded(.up)))
    }

    /// Each done set once (a superset's round shares its timing), in time order.
    private var spans: [LiftHeartRateMath.SetSpan] {
        var seen = Set<Int>()
        return sets
            .compactMap { row -> LiftHeartRateMath.SetSpan? in
                guard let start = row.startTs, let stop = row.endTs, LiftMetrics.isPerformed(reps: row.reps),
                      seen.insert(stop).inserted else { return nil }
                return LiftHeartRateMath.SetSpan(start: start, end: stop, restSec: row.restSec ?? 0)
            }
            .sorted { $0.start < $1.start }
    }

    private var content: LiftHeartRateBand.Content {
        let stats = LiftHeartRateMath.averageAndPeak(samples)
        let recovery = LiftHeartRateMath.mean(LiftHeartRateMath.recoveries(spans, samples: samples, now: end))
        return LiftHeartRateBand.Content(
            bpm: nil,
            zone: 0,
            isResting: false,
            curve: LiftHeartRateMath.bucketCurve(samples, from: session.startTs, to: end, bucket: bucket),
            comparisons: previous.map {
                LiftHeartRateMath.alignedCurve($0.samples, sessionStart: $0.start,
                                               fromElapsed: 0, toElapsed: durationSec, bucket: bucket)
            }.filter { $0.contains { $0 != nil } },
            rests: LiftHeartRateMath.restSpans(spans, from: session.startTs, to: end, now: end),
            setEnds: spans.compactMap { LiftHeartRateMath.fraction($0.end, from: session.startTs, to: end) },
            average: stats?.average,
            peak: stats?.peak,
            recovery: recovery,
            recoveryIsLive: false,
            isLive: false)
    }

    /// Minutes in each zone, as five coloured segments with their minutes under them.
    private var zonesRow: some View {
        let seconds = LiveWorkoutMath.zoneSeconds(samples, zoneSet: model.profile.hrZoneSet)
        let total = max(1, seconds.reduce(0, +))
        return VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Text("Time in zones")
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(StrandPalette.textPrimary)
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { zone in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(StrandPalette.hrZoneColor(zone))
                            .frame(width: max(0, proxy.size.width * CGFloat(seconds[zone - 1]) / CGFloat(total) - 2))
                    }
                }
            }
            .frame(height: 10)
            HStack {
                ForEach(1...5, id: \.self) { zone in
                    VStack(spacing: 0) {
                        Text("Z\(zone)")
                            .font(StrandFont.caption2.weight(.semibold))
                            .foregroundStyle(StrandPalette.hrZoneColor(zone))
                        Text(verbatim: "\(Int((Double(seconds[zone - 1]) / 60).rounded()))")
                            .font(StrandFont.captionNumber)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text("minutes per zone")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
        }
    }

    /// Each exercise's average heart rate over its own sets.
    @ViewBuilder
    private var byExercise: some View {
        let rows = LiftHeartRateMath.averageByExercise(
            sets.compactMap { row -> (exercise: String, start: Int, end: Int)? in
                guard let start = row.startTs, let stop = row.endTs, LiftMetrics.isPerformed(reps: row.reps) else {
                    return nil
                }
                return (row.exercise, start, stop)
            },
            samples: samples)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Text("Average heart rate per exercise")
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                ForEach(rows.indices, id: \.self) { index in
                    let row = rows[index]
                    HStack {
                        Text(verbatim: row.exercise)
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: NoopMetrics.space2)
                        Text(String(localized: "\(row.average) bpm"))
                            .font(StrandFont.captionNumber)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
            }
        }
    }

    private func load() async {
        guard session.endTs != nil else { loaded = true; return }
        samples = await repo.hrSamples(from: session.startTs, to: end)
        let day = Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(session.startTs)))
        let from = Date(timeIntervalSince1970: TimeInterval(session.startTs))
        let to = Date(timeIntervalSince1970: TimeInterval(end))
        waterMl = repo.hydrationEntries(day: day).filter { $0.loggedAt >= from && $0.loggedAt <= to }
            .reduce(0) { $0 + $1.amountMl }
        previous = await LiftHeartRateHistory.previousSessions(
            repo: repo, programId: session.programId, before: session.startTs)
        loaded = true
    }
}
