import XCTest
@testable import Strand
import StrandAnalytics

/// Personal fork (2 Nov 2026): Today turns at midnight. The logical day rolls at 00:00 when the day cycle
/// is set to midnight and at 04:00 while it follows sleep, and the midnight default is applied once.
@MainActor
final class MidnightDayTests: XCTestCase {

    private let keys = [DayCycleMode.storageKey, Repository.midnightDayDefaultKey]
    private var saved: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        for key in keys { saved[key] = defaults.object(forKey: key) }
    }

    override func tearDown() {
        let defaults = UserDefaults.standard
        for key in keys {
            if let value = saved[key] { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        super.tearDown()
    }

    private func date(_ hour: Int, _ minute: Int) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 2; c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c)!
    }

    func testMidnightCycleTurnsTheDayAtMidnight() {
        UserDefaults.standard.set(DayCycleMode.midnight.rawValue, forKey: DayCycleMode.storageKey)
        XCTAssertEqual(Repository.logicalDayRolloverHour, 0)
        XCTAssertEqual(Repository.logicalDayKey(date(1, 42)), "2026-11-02")
        XCTAssertEqual(Repository.logicalDayKey(date(0, 0)), "2026-11-02")
        XCTAssertEqual(BodyVitalSigns.logicalDayKey(date(1, 42)), "2026-11-02")
    }

    func testSleepCycleKeepsTheFourOClockRoll() {
        UserDefaults.standard.set(DayCycleMode.sleepOnset.rawValue, forKey: DayCycleMode.storageKey)
        XCTAssertEqual(Repository.logicalDayRolloverHour, 4)
        XCTAssertEqual(Repository.logicalDayKey(date(1, 42)), "2026-11-01")
        XCTAssertEqual(Repository.logicalDayKey(date(4, 1)), "2026-11-02")
    }

    func testMidnightDefaultIsAppliedOnceAndALaterChoiceIsKept() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Repository.midnightDayDefaultKey)
        defaults.set(DayCycleMode.sleepOnset.rawValue, forKey: DayCycleMode.storageKey)
        Repository.applyMidnightDayDefaultOnce(defaults)
        XCTAssertEqual(defaults.string(forKey: DayCycleMode.storageKey), DayCycleMode.midnight.rawValue)
        defaults.set(DayCycleMode.sleepOnset.rawValue, forKey: DayCycleMode.storageKey)   // chosen in Settings
        Repository.applyMidnightDayDefaultOnce(defaults)
        XCTAssertEqual(defaults.string(forKey: DayCycleMode.storageKey), DayCycleMode.sleepOnset.rawValue)
    }
}
