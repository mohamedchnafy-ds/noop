import XCTest
import WhoopStore
@testable import Strand

/// Personal fork, chantier 14 step 2: the place layers and the points layer (`PlaceMetrics`).
final class PlaceMetricsTests: XCTestCase {

    private func stay(_ id: String, _ place: String, _ from: Int, _ to: Int?) -> PlaceVisitRow {
        PlaceVisitRow(id: id, placeId: place, arrivedAt: from, departedAt: to, lat: 0, lon: 0, accuracyM: 30)
    }

    private func night(_ day: String, start: Int, hrv: Double?, recovery: Double? = nil,
                       minutes: Double? = nil) -> PlaceNight {
        PlaceNight(day: day, sleepStart: start, durationMin: minutes, hrvMs: hrv, recoveryPct: recovery)
    }

    func testAVerdictReadsTheDirectionOfTheMetric() {
        XCTAssertEqual(PlaceMetrics.placeVerdict(delta: 5, band: 3, higherIsBetter: true), .better)
        XCTAssertEqual(PlaceMetrics.placeVerdict(delta: -5, band: 3, higherIsBetter: true), .worse)
        XCTAssertEqual(PlaceMetrics.placeVerdict(delta: 5, band: 3, higherIsBetter: false), .worse, "a higher heart rate")
        XCTAssertEqual(PlaceMetrics.placeVerdict(delta: 2.9, band: 3, higherIsBetter: false), .close)
    }

    func testANightBelongsToThePlaceOfTheBedtime() {
        let visits = [stay("a", "home", 0, 1_000), stay("b", "parents", 1_000, nil)]
        XCTAssertEqual(PlaceMetrics.nightPlace(night("d", start: 500, hrv: 50), visits: visits), "home")
        XCTAssertEqual(PlaceMetrics.nightPlace(night("d", start: 5_000, hrv: 50), visits: visits), "parents")
        let gap = [stay("a", "hotel", 0, 100)]
        XCTAssertEqual(PlaceMetrics.nightPlace(night("d", start: 3_000, hrv: 50), visits: gap), "hotel",
                       "the last stay begun in the 12 hours before")
        XCTAssertNil(PlaceMetrics.nightPlace(night("d", start: 50_000, hrv: 50), visits: gap))
    }

    func testANightFigureNeedsThreeNightsBeforeAVerdict() {
        let all = [night("1", start: 0, hrv: 50), night("2", start: 0, hrv: 50), night("3", start: 0, hrv: 50),
                   night("4", start: 0, hrv: 40), night("5", start: 0, hrv: 40)]
        let two = PlaceMetrics.nightFigure(Array(all.suffix(2)), all: all, value: { $0.hrvMs }, band: 3,
                                           higherIsBetter: true)
        XCTAssertEqual(two.verdict, .tooFew)
        XCTAssertEqual(two.value, 40)
        XCTAssertEqual(two.normal, 46)
        XCTAssertEqual(two.count, 2)
        let three = PlaceMetrics.nightFigure(Array(all.prefix(3)), all: all, value: { $0.hrvMs }, band: 3,
                                             higherIsBetter: true)
        XCTAssertEqual(three.verdict, .better, "50 against a normal of 46")
        let none = PlaceMetrics.nightFigure([], all: all, value: { $0.hrvMs }, band: 3, higherIsBetter: true)
        XCTAssertEqual(none.verdict, .none)
    }

    func testAwakeTimeLeavesOutSleepAndWorkouts() {
        let spans = PlaceMetrics.awakeSpans(of: stay("a", "home", 0, 1_000), until: 5_000,
                                            excluding: [(start: 200, end: 300), (start: 900, end: 2_000)])
        XCTAssertEqual(spans.map { $0.start }, [0, 300])
        XCTAssertEqual(spans.map { $0.end }, [200, 900])
        let open = PlaceMetrics.awakeSpans(of: stay("b", "home", 100, nil), until: 400, excluding: [])
        XCTAssertEqual(open.map { $0.end }, [400], "a stay still going ends now")
    }

    /// Home is visited in the evening at 70 bpm; elsewhere the evenings run at 80 and the mornings at 60.
    /// The place is compared with the SAME hours elsewhere: −10 bpm, not −0.
    func testHeartRateIsComparedWithTheSameHoursElsewhere() {
        let hour = 3_600
        let hourOf: (Int) -> Int = { ($0 / 3_600) % 24 }
        var visits: [PlaceVisitRow] = []
        var buckets: [PlaceHRBucket] = []
        for day in 0..<4 {
            let base = day * 86_400
            visits.append(stay("h\(day)", "home", base + 19 * hour, base + 20 * hour))
            visits.append(stay("w\(day)", "work", base + 8 * hour, base + 9 * hour))
            visits.append(stay("e\(day)", "work", base + 20 * hour, base + 21 * hour))
            buckets.append(PlaceHRBucket(ts: base + 19 * hour + 600, bpm: 70))
            buckets.append(PlaceHRBucket(ts: base + 8 * hour + 600, bpm: 60))
            buckets.append(PlaceHRBucket(ts: base + 19 * hour + 1_200, bpm: 70))
        }
        // Evening elsewhere at hour 19: another place visited at 19:00 on day 5.
        visits.append(stay("x", "gym", 5 * 86_400 + 19 * hour, 5 * 86_400 + 20 * hour))
        buckets.append(PlaceHRBucket(ts: 5 * 86_400 + 19 * hour + 600, bpm: 80))
        buckets.sort { $0.ts < $1.ts }
        let figure = PlaceMetrics.heartRateFigure(placeId: "home", visits: visits, buckets: buckets, excluding: [],
                                                  now: 10 * 86_400, hourOf: hourOf)
        XCTAssertEqual(figure.value, 70)
        XCTAssertEqual(figure.normal, 80, "the 19:00 hour elsewhere, not the morning")
        XCTAssertEqual(figure.delta, -10)
        XCTAssertEqual(figure.verdict, .better)
        XCTAssertEqual(figure.count, 4)
    }

    func testStressCountsTheShareOfScoredTimeInHigh() {
        let visits = [stay("a", "work", 0, 7_200), stay("b", "work", 10_000, 17_200), stay("c", "work", 20_000, 27_200)]
        let windows = [
            PlaceStressWindow(start: 0, end: 3_600, level: 2.5),
            PlaceStressWindow(start: 3_600, end: 7_200, level: 0.5),
            PlaceStressWindow(start: 10_000, end: 13_600, level: 2.1),
            PlaceStressWindow(start: 20_000, end: 23_600, level: nil, moving: true),
            PlaceStressWindow(start: 23_600, end: 27_200, level: 1.0),
            PlaceStressWindow(start: 40_000, end: 43_600, level: 0.2),
        ]
        let figure = PlaceMetrics.stressFigure(placeId: "work", visits: visits, windows: windows, excluding: [],
                                               now: 50_000)
        XCTAssertEqual(figure.value, 50, "2 of the 4 scored windows at work are High")
        XCTAssertEqual(figure.normal, 40, "2 of the 5 scored windows overall")
        XCTAssertEqual(figure.count, 3)
        XCTAssertEqual(figure.verdict, .worse)
    }

    func testAPointReadsItsBucketAndItsHour() {
        let buckets = [PlaceHRBucket(ts: 0, bpm: 60), PlaceHRBucket(ts: 300, bpm: 90)]
        XCTAssertEqual(PlaceMetrics.heartRateAt(320, buckets: buckets), 90)
        XCTAssertNil(PlaceMetrics.heartRateAt(5_000, buckets: buckets))
        let habit = PlaceMetrics.habitualHeartRateByHour(buckets, hourOf: { _ in 7 })
        XCTAssertEqual(habit[7], 75)
        XCTAssertEqual(PlaceMetrics.pointVerdict(bpm: 77, habitual: 75), .close)
        XCTAssertEqual(PlaceMetrics.pointVerdict(bpm: 80, habitual: 75), .worse)
        XCTAssertEqual(PlaceMetrics.pointVerdict(bpm: 70, habitual: 75), .better)
        XCTAssertEqual(PlaceMetrics.pointVerdict(bpm: nil, habitual: 75), .none)
    }
}
