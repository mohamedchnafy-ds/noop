import XCTest
@testable import Strand
import WhoopStore

/// The habitual-day heart-rate profile behind the Today card's dotted line (personal fork).
final class HabitualHRTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!
    private let day = 86_400

    private func bucket(_ ts: Int, _ bpm: Double) -> HRBucket {
        HRBucket(ts: ts, bpm: bpm, minBpm: bpm, maxBpm: bpm)
    }

    func testSlotFollowsTheLocalClockNotUTC() {
        let paris = TimeZone(identifier: "Europe/Paris")!
        // 2026-01-15 23:30 UTC is 00:30 the next day in Paris: slot 6 of the new day, not 282.
        let ts = 1_768_519_800
        XCTAssertEqual(HabitualHR.slot(ts, zone: utc), 282)
        XCTAssertEqual(HabitualHR.slot(ts, zone: paris), 6)
    }

    func testProfileAveragesEachSlotAcrossDaysAndDropsThinSlots() {
        var buckets: [HRBucket] = []
        for d in 0..<5 { buckets.append(bucket(d * day + 8 * 3600, 60 + Double(d))) }   // 08:00, five days
        buckets.append(bucket(9 * 3600, 90))                                            // 09:00, one day
        let p = HabitualHR.profile(buckets: buckets, zone: utc)
        XCTAssertEqual(p[8 * 12]!, 62, accuracy: 1e-9)
        XCTAssertNil(p[9 * 12], "a slot seen on one day is not a habit")
    }

    func testUsualAtReadsTheSlotOfTheInstant() {
        let p = [96: 55.0]
        XCTAssertEqual(HabitualHR.usual(at: 8 * 3600 + 299, profile: p, zone: utc), 55)
        XCTAssertNil(HabitualHR.usual(at: 8 * 3600 + 300, profile: p, zone: utc))
    }
}
