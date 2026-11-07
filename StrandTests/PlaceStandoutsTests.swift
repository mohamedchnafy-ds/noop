import XCTest
import WhoopStore
@testable import Strand

/// Personal fork, chantier 14 (Carte v2): « Ce qui ressort » (`PlaceStandouts`) and the margin of error
/// of a place figure (`PlaceMetrics.marginOfPlaceMean`).
final class PlaceStandoutsTests: XCTestCase {

    private let none = PlaceFigure(value: nil, normal: nil, delta: nil, verdict: .none, count: 0)

    private func summary(_ id: String, hrv: PlaceFigure? = nil, heartRate: PlaceFigure? = nil) -> PlaceSummary {
        PlaceSummary(place: PlaceRow(id: id, lat: 0, lon: 0, radiusM: 150, createdAt: 0), name: id,
                     visits: 6, nights: 6, lastArrival: nil, heartRate: heartRate ?? none, stress: none,
                     hrv: hrv ?? none, recovery: none, sleep: none, nightBars: [])
    }

    private func figure(delta: Double, margin: Double?, verdict: PlaceVerdict, count: Int = 6) -> PlaceFigure {
        PlaceFigure(value: 50 + delta, normal: 50, delta: delta, verdict: verdict, count: count, margin: margin)
    }

    func testTheMarginIsTheNinetyFivePercentIntervalOfTheMean() {
        XCTAssertNil(PlaceMetrics.marginOfPlaceMean([]))
        XCTAssertNil(PlaceMetrics.marginOfPlaceMean([42]), "one value has no spread")
        XCTAssertEqual(PlaceMetrics.marginOfPlaceMean([50, 50, 50]), 0)
        // Values 48, 50, 52: sample sd 2, n 3 → 1.96 × 2 / √3 ≈ 2.263.
        XCTAssertEqual(PlaceMetrics.marginOfPlaceMean([48, 50, 52]) ?? 0, 2.263, accuracy: 0.001)
    }

    func testANightFigureCarriesItsMargin() {
        let nights = [48.0, 50, 52].enumerated().map { PlaceNight(day: "\($0.offset)", sleepStart: 0, durationMin: nil,
                                                                  hrvMs: $0.element, recoveryPct: nil) }
        let f = PlaceMetrics.nightFigure(nights, all: nights, value: { $0.hrvMs }, band: 3, higherIsBetter: true)
        XCTAssertEqual(f.margin ?? 0, 2.263, accuracy: 0.001)
    }

    func testOnlyDifferencesBeyondTheirMarginStandOut() {
        let places = [
            summary("parents", hrv: figure(delta: -7, margin: 4, verdict: .worse)),
            summary("office", hrv: figure(delta: 5, margin: 6, verdict: .better)),           // within its noise
            summary("gym", hrv: figure(delta: -1, margin: 0.5, verdict: .close)),            // inside the band
            summary("hotel", hrv: figure(delta: -9, margin: 2, verdict: .tooFew, count: 2)), // too few nights
            summary("park", hrv: figure(delta: 6, margin: nil, verdict: .better))            // no spread known
        ]
        let standouts = PlaceStandouts.placeStandouts(places)
        XCTAssertEqual(standouts.map(\.placeId), ["parents"])
        XCTAssertEqual(standouts.first?.metric, .hrv)
        XCTAssertEqual(standouts.first?.count, 6)
    }

    func testStandoutsAreRankedByMarginsThenSize() {
        let places = [
            summary("a", hrv: figure(delta: -8, margin: 4, verdict: .worse)),                 // 2 margins
            summary("b", hrv: figure(delta: 6, margin: 1, verdict: .better),                  // 6 margins
                    heartRate: figure(delta: 5, margin: 2, verdict: .worse))                  // 2.5 margins
        ]
        let standouts = PlaceStandouts.placeStandouts(places)
        XCTAssertEqual(standouts.map(\.id), ["b-hrv", "b-heartRate", "a-hrv"])
        XCTAssertEqual(PlaceStandouts.placeStandouts(places, limit: 1).map(\.id), ["b-hrv"])
    }
}
