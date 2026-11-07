import XCTest
import WhoopStore
@testable import Strand

/// Personal fork, chantier 14 step 2: how an iOS visit becomes a place and a stay (`PlaceVisitPlan`).
final class PlaceLogTests: XCTestCase {

    private let home = PlaceRow(id: "home", lat: 48.8566, lon: 2.3522, radiusM: 150, createdAt: 0)
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func ids() -> () -> String {
        var n = 0
        return { n += 1; return "id\(n)" }
    }

    private func open(_ id: String, place: String, at arrived: Date) -> PlaceVisitRow {
        PlaceVisitRow(id: id, placeId: place, arrivedAt: Int(arrived.timeIntervalSince1970), departedAt: nil,
                      lat: home.lat, lon: home.lon, accuracyM: 40)
    }

    func testAPositionMatchesThePlaceWhoseZoneContainsIt() {
        // ~100 m north of home: inside; ~400 m: outside.
        XCTAssertEqual(PlaceVisitPlan.matchingPlace(lat: 48.8575, lon: 2.3522, in: [home])?.id, "home")
        XCTAssertNil(PlaceVisitPlan.matchingPlace(lat: 48.8602, lon: 2.3522, in: [home]))
        let near = PlaceRow(id: "near", lat: 48.8570, lon: 2.3522, radiusM: 150, createdAt: 1)
        XCTAssertEqual(PlaceVisitPlan.matchingPlace(lat: 48.8571, lon: 2.3522, in: [home, near])?.id, "near",
                       "the nearest place wins")
    }

    func testAnArrivalSomewhereNewCreatesAPlaceAndOpensAStay() {
        let make = ids()
        let out = PlaceVisitPlan.planVisit(lat: 45.76, lon: 4.83, accuracyM: 35, arrival: t0, departure: nil,
                                           places: [home], open: [], now: t0, makeId: make)
        XCTAssertEqual(out.newPlace?.id, "id1")
        XCTAssertEqual(out.newPlace?.radiusM, PlaceVisitPlan.newPlaceRadiusM)
        XCTAssertNil(out.newPlace?.name)
        XCTAssertEqual(out.visits.count, 1)
        XCTAssertEqual(out.visits.first?.placeId, "id1")
        XCTAssertNil(out.visits.first?.departedAt)
    }

    func testAnArrivalClosesTheStayWhoseDepartureWasMissed() {
        let stay = open("old", place: "work", at: t0)
        let later = t0.addingTimeInterval(3_600)
        let out = PlaceVisitPlan.planVisit(lat: home.lat, lon: home.lon, accuracyM: 30, arrival: later,
                                           departure: nil, places: [home], open: [stay], now: later,
                                           makeId: ids())
        XCTAssertNil(out.newPlace)
        XCTAssertEqual(out.visits.map(\.id), ["old", "id1"])
        XCTAssertEqual(out.visits.first?.departedAt, Int(later.timeIntervalSince1970))
        XCTAssertEqual(out.visits.last?.placeId, "home")
    }

    func testTheSameArrivalReportedTwiceChangesNothing() {
        let stay = open("s", place: "home", at: t0)
        let out = PlaceVisitPlan.planVisit(lat: home.lat, lon: home.lon, accuracyM: 30,
                                           arrival: t0.addingTimeInterval(60), departure: nil, places: [home],
                                           open: [stay], now: t0, makeId: ids())
        XCTAssertEqual(out, PlaceVisitPlan.Outcome(newPlace: nil, visits: []))
    }

    func testADepartureClosesTheStayWithTheSameArrivalEvenIfItsCentreMoved() {
        let stay = open("s", place: "home", at: t0)
        let leave = t0.addingTimeInterval(7_200)
        let out = PlaceVisitPlan.planVisit(lat: 48.9, lon: 2.4, accuracyM: 80, arrival: t0.addingTimeInterval(30),
                                           departure: leave, places: [home], open: [stay], now: leave,
                                           makeId: ids())
        XCTAssertNil(out.newPlace, "no place is created for a stay that already has one")
        XCTAssertEqual(out.visits.map(\.id), ["s"])
        XCTAssertEqual(out.visits.first?.departedAt, Int(leave.timeIntervalSince1970))
    }

    func testADepartureWithoutArrivalClosesTheStayAtThatPlaceOrChangesNothing() {
        let stay = open("s", place: "home", at: t0)
        let leave = t0.addingTimeInterval(600)
        var out = PlaceVisitPlan.planVisit(lat: home.lat, lon: home.lon, accuracyM: 30, arrival: nil,
                                           departure: leave, places: [home], open: [stay], now: leave,
                                           makeId: ids())
        XCTAssertEqual(out.visits.map(\.id), ["s"])
        out = PlaceVisitPlan.planVisit(lat: 45.76, lon: 4.83, accuracyM: 30, arrival: nil, departure: leave,
                                       places: [home], open: [], now: leave, makeId: ids())
        XCTAssertEqual(out, PlaceVisitPlan.Outcome(newPlace: nil, visits: []))
    }

    func testAWholeStayReportedAtOnceIsWrittenClosed() {
        let leave = t0.addingTimeInterval(5_400)
        let out = PlaceVisitPlan.planVisit(lat: home.lat, lon: home.lon, accuracyM: 30, arrival: t0,
                                           departure: leave, places: [home], open: [], now: leave,
                                           makeId: ids())
        XCTAssertNil(out.newPlace)
        XCTAssertEqual(out.visits.count, 1)
        XCTAssertEqual(out.visits.first?.arrivedAt, Int(t0.timeIntervalSince1970))
        XCTAssertEqual(out.visits.first?.departedAt, Int(leave.timeIntervalSince1970))
    }
}
