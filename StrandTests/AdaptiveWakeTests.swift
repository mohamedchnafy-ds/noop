import XCTest
@testable import Strand

/// Personal fork, chantier 25: the adaptive wake and the Fajr alarm. Pins the plan (deadline never later,
/// Fajr never after the adhan, the 45-minute merge), the overnight detector and session, the learning from the
/// wake question, the MAWAQIT timetable and the on-phone calculation, and the Coach's ALARMS block.
final class AdaptiveWakeTests: XCTestCase {

    private var paris: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        paris.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    private func mainConfig(minutes: Int = 6 * 60 + 30, adaptive: Bool, window: Int = 30,
                            weekdays: Set<Int> = [], overrides: [Int: Int] = [:]) -> WakeMainConfig {
        WakeMainConfig(enabled: true, minutes: minutes, weekdays: weekdays, overrides: overrides,
                       adaptive: adaptive, windowMinutes: window)
    }

    private func adhanAt(_ hour: Int, _ minute: Int) -> (Date) -> Date? {
        let calendar = paris
        return { day in calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) }
    }

    // MARK: - Plan: the main alarm

    func testClassicMainKeepsTheArmedTimeOfBefore() {
        let now = at(2026, 11, 16, 22, 0)
        let windows = WakePlan.mainWindows(mainConfig(adaptive: false), from: now, calendar: paris)
        let legacy = AppModel.nextSmartAlarmDate(minutes: 6 * 60 + 30, weekdays: [], from: now, calendar: paris)
        XCTAssertEqual(windows.first?.deadline, legacy)
        XCTAssertEqual(windows.first?.start, windows.first?.deadline)
        XCTAssertEqual(windows.first?.adaptive, false)
    }

    func testAdaptiveMainWindowEndsWindowMinutesAfterTheEarliestTime() {
        let now = at(2026, 11, 16, 22, 0)
        let windows = WakePlan.mainWindows(mainConfig(adaptive: true, window: 30), from: now, calendar: paris)
        XCTAssertEqual(windows.first?.start, at(2026, 11, 17, 6, 30))
        XCTAssertEqual(windows.first?.deadline, at(2026, 11, 17, 7, 0))
        XCTAssertEqual(windows.count, WakePlan.horizonDays)
        for window in windows {
            XCTAssertEqual(window.deadline.timeIntervalSince(window.start), 30 * 60)
        }
    }

    func testAdaptiveWindowIsClampedAndFollowsTheDeadlineDay() {
        let now = at(2026, 11, 16, 22, 0)
        // Tuesday only: the deadline lands on Tuesday 17 November.
        let tuesday = WakePlan.mainWindows(mainConfig(adaptive: true, window: 30, weekdays: [3]), from: now, calendar: paris)
        XCTAssertEqual(tuesday.first?.deadline, at(2026, 11, 17, 7, 0))
        XCTAssertEqual(tuesday.dropFirst().first?.deadline, at(2026, 11, 24, 7, 0))
        // A corrupted 600-minute window is clamped to an hour.
        let clamped = WakePlan.mainWindows(mainConfig(adaptive: true, window: 600), from: now, calendar: paris)
        XCTAssertEqual(clamped.first?.deadline, at(2026, 11, 17, 7, 30))
    }

    func testPerDayTimeMovesThatDaysWindow() {
        let now = at(2026, 11, 16, 22, 0)
        let windows = WakePlan.mainWindows(mainConfig(adaptive: true, window: 20, overrides: [3: 5 * 60]),
                                           from: now, calendar: paris)
        XCTAssertEqual(windows.first?.start, at(2026, 11, 17, 5, 0))
        XCTAssertEqual(windows.first?.deadline, at(2026, 11, 17, 5, 20))
        XCTAssertEqual(windows.dropFirst().first?.deadline, at(2026, 11, 18, 6, 50))
    }

    // MARK: - Plan: Fajr

    func testFajrAdaptiveEndsAtTheAdhanAndClassicBuzzesAtTheLead() {
        let now = at(2026, 11, 16, 22, 0)
        let adaptive = WakePlan.fajrWindows(WakeFajrConfig(enabled: true, leadMinutes: 20, adaptive: true),
                                            adhan: adhanAt(6, 17), from: now, calendar: paris)
        XCTAssertEqual(adaptive.first?.start, at(2026, 11, 17, 5, 57))
        XCTAssertEqual(adaptive.first?.deadline, at(2026, 11, 17, 6, 17))
        let classic = WakePlan.fajrWindows(WakeFajrConfig(enabled: true, leadMinutes: 40, adaptive: false),
                                           adhan: adhanAt(6, 17), from: now, calendar: paris)
        XCTAssertEqual(classic.first?.deadline, at(2026, 11, 17, 5, 37))
        XCTAssertEqual(classic.first?.start, classic.first?.deadline)
        for window in adaptive + classic {
            let adhan = paris.date(bySettingHour: 6, minute: 17, second: 0, of: window.deadline)!
            XCTAssertLessThanOrEqual(window.deadline, adhan, "never after the adhan")
        }
    }

    func testFajrOffOrMainOffMakesNoWindow() {
        let now = at(2026, 11, 16, 22, 0)
        XCTAssertTrue(WakePlan.fajrWindows(WakeFajrConfig(enabled: false, leadMinutes: 20, adaptive: true),
                                           adhan: adhanAt(6, 17), from: now, calendar: paris).isEmpty)
        var off = mainConfig(adaptive: true)
        off.enabled = false
        XCTAssertTrue(WakePlan.mainWindows(off, from: now, calendar: paris).isEmpty)
    }

    // MARK: - Plan: the merge

    func testCloseAlarmsMergeIntoTheEarlierOne() {
        let now = at(2026, 11, 16, 22, 0)
        let upcoming = WakePlan.upcoming(main: mainConfig(adaptive: true),
                                         fajr: WakeFajrConfig(enabled: true, leadMinutes: 20, adaptive: true),
                                         adhan: adhanAt(6, 30), dismissed: [], from: now, calendar: paris)
        // Fajr 06:30 and the main deadline 07:00 are 30 min apart: only Fajr rings.
        XCTAssertEqual(upcoming.first?.kind, .fajr)
        XCTAssertEqual(upcoming.first?.deadline, at(2026, 11, 17, 6, 30))
        XCTAssertFalse(upcoming.contains { $0.kind == .main })
    }

    func testDistantAlarmsBothRing() {
        let now = at(2026, 11, 16, 22, 0)
        let upcoming = WakePlan.upcoming(main: mainConfig(adaptive: true),
                                         fajr: WakeFajrConfig(enabled: true, leadMinutes: 20, adaptive: true),
                                         adhan: adhanAt(5, 0), dismissed: [], from: now, calendar: paris)
        XCTAssertEqual(upcoming.prefix(2).map(\.kind), [.fajr, .main])
        XCTAssertEqual(upcoming.dropFirst().first?.deadline, at(2026, 11, 17, 7, 0))
    }

    func testEarlierMainAbsorbsFajrAndKeepsTheAdhanPromise() {
        let now = at(2026, 11, 16, 22, 0)
        let upcoming = WakePlan.upcoming(main: mainConfig(minutes: 6 * 60, adaptive: false),
                                         fajr: WakeFajrConfig(enabled: true, leadMinutes: 10, adaptive: true),
                                         adhan: adhanAt(6, 30), dismissed: [], from: now, calendar: paris)
        XCTAssertEqual(upcoming.first?.kind, .main)
        XCTAssertEqual(upcoming.first?.deadline, at(2026, 11, 17, 6, 0))
        XCTAssertFalse(upcoming.contains { $0.kind == .fajr })
    }

    func testMergeHoldsAfterTheFirstDeadlinePassed() {
        // 06:40: Fajr rang at 06:30; the main deadline at 07:00 must stay absorbed.
        let now = at(2026, 11, 17, 6, 40)
        let upcoming = WakePlan.upcoming(main: mainConfig(adaptive: true),
                                         fajr: WakeFajrConfig(enabled: true, leadMinutes: 20, adaptive: true),
                                         adhan: adhanAt(6, 30), dismissed: [], from: now, calendar: paris)
        XCTAssertEqual(upcoming.first?.kind, .fajr)
        XCTAssertEqual(upcoming.first?.deadline, at(2026, 11, 18, 6, 30))
    }

    func testDismissedMorningDropsOnlyThatWindow() {
        let now = at(2026, 11, 16, 22, 0)
        let main = mainConfig(adaptive: true)
        let fajr = WakeFajrConfig(enabled: true, leadMinutes: 20, adaptive: true)
        let first = WakePlan.upcoming(main: main, fajr: fajr, adhan: adhanAt(6, 30), dismissed: [],
                                      from: now, calendar: paris).first!
        let after = WakePlan.upcoming(main: main, fajr: fajr, adhan: adhanAt(6, 30), dismissed: [first.id],
                                      from: now, calendar: paris)
        XCTAssertEqual(after.first?.deadline, at(2026, 11, 18, 6, 30))
        XCTAssertFalse(after.contains { $0.kind == .main }, "a dismissed Fajr does not bring back the merged main")
    }

    // MARK: - Detector

    func testDetectorNeedsTheTroughAndASustainedRise() {
        var detector = AdaptiveWakeDetector(riseBpm: 6)
        for _ in 0..<30 { XCTAssertFalse(detector.feed(52, inWindow: false)) }
        XCTAssertEqual(detector.trough, 52)
        XCTAssertFalse(detector.feed(57, inWindow: true), "5 bpm is under the threshold")
        XCTAssertFalse(detector.feed(58, inWindow: true))
        XCTAssertFalse(detector.feed(58, inWindow: true))
        XCTAssertTrue(detector.feed(58, inWindow: true), "three samples at +6 fire")
        XCTAssertFalse(detector.feed(70, inWindow: true), "fires once")
    }

    func testDetectorIgnoresASpikeAndTheTimeBeforeTheWindow() {
        var detector = AdaptiveWakeDetector(riseBpm: 6)
        for _ in 0..<30 { _ = detector.feed(52, inWindow: false) }
        for _ in 0..<10 { XCTAssertFalse(detector.feed(70, inWindow: false), "never before the window") }
        for _ in 0..<5 {
            XCTAssertFalse(detector.feed(60, inWindow: true))
            XCTAssertFalse(detector.feed(52, inWindow: true))
        }
        var cold = AdaptiveWakeDetector(riseBpm: 6)
        for _ in 0..<10 { XCTAssertFalse(cold.feed(70, inWindow: true), "no trough trusted before 30 samples") }
        XCTAssertFalse(cold.feed(0, inWindow: true))
    }

    // MARK: - Session

    func testSessionSamplesBuzzesAndRepeats() {
        let start = at(2026, 11, 17, 6, 30)
        let window = WakeWindow(kind: .main, start: start, deadline: start.addingTimeInterval(1800), adaptive: true)
        var session = AdaptiveWakeSession(window: window, riseBpm: 6)
        XCTAssertFalse(session.isObserving(at: start.addingTimeInterval(-4 * 3600)))
        XCTAssertEqual(session.observe(bpm: 52, at: start.addingTimeInterval(-4 * 3600)), .none)
        XCTAssertEqual(session.detector.samples, 0)
        var t = start.addingTimeInterval(-3600)
        for _ in 0..<40 {
            XCTAssertEqual(session.observe(bpm: 52, at: t), .none)
            XCTAssertEqual(session.observe(bpm: 52, at: t.addingTimeInterval(5)), .none)
            t = t.addingTimeInterval(10)
        }
        XCTAssertEqual(session.detector.samples, 40, "one sample per 10 s")
        XCTAssertEqual(session.observe(bpm: 60, at: start.addingTimeInterval(60)), .none)
        XCTAssertEqual(session.observe(bpm: 60, at: start.addingTimeInterval(70)), .none)
        XCTAssertEqual(session.observe(bpm: 60, at: start.addingTimeInterval(80)), .wake)
        XCTAssertEqual(session.firedBpm, 60)
        XCTAssertEqual(session.observe(bpm: 60, at: start.addingTimeInterval(100)), .none)
        XCTAssertEqual(session.observe(bpm: nil, at: start.addingTimeInterval(125)), .rebuzz)
        XCTAssertEqual(session.observe(bpm: nil, at: start.addingTimeInterval(171)), .rebuzz)
        XCTAssertEqual(session.observe(bpm: nil, at: start.addingTimeInterval(220)), .none, "three buzzes at most")
    }

    func testStoppedOrClassicSessionNeverBuzzes() {
        let start = at(2026, 11, 17, 6, 30)
        let window = WakeWindow(kind: .main, start: start, deadline: start.addingTimeInterval(1800), adaptive: true)
        var session = AdaptiveWakeSession(window: window, riseBpm: 6)
        session.stop()
        XCTAssertEqual(session.observe(bpm: 52, at: start), .none)
        let classic = WakeWindow(kind: .fajr, start: start, deadline: start, adaptive: false)
        XCTAssertFalse(AdaptiveWakeSession(window: classic, riseBpm: 6).isObserving(at: start.addingTimeInterval(-60)))
        var late = AdaptiveWakeSession(window: window, riseBpm: 6)
        XCTAssertEqual(late.observe(bpm: 52, at: window.deadline), .none, "nothing at or after the deadline")
    }

    // MARK: - Learning

    private func event(_ index: Int, _ feeling: WakeFeeling?, adaptive: Bool = true,
                       kind: WakeAlarmKind = .main) -> WakeEvent {
        let woke = at(2026, 11, 1, 6, 40).addingTimeInterval(TimeInterval(index) * 86400)
        return WakeEvent(id: "\(kind.rawValue)-\(index)", kind: kind, windowStart: woke, deadline: woke,
                         wokeAt: woke, adaptive: adaptive, trough: 52, bpmAtWake: 59, riseBpm: 6,
                         feeling: feeling, answeredAt: feeling == nil ? nil : woke)
    }

    func testTiredWakesRaiseTheThresholdOnce() {
        XCTAssertEqual(WakeLearning.riseBpm(history: [], kind: .main), 6)
        let three = (0..<3).map { event($0, .tired) }
        XCTAssertEqual(WakeLearning.riseBpm(history: three, kind: .main), 7)
        let mixed: [WakeFeeling] = [.tired, .fresh, .tired, .fresh, .tired]
        XCTAssertEqual(WakeLearning.riseBpm(history: mixed.enumerated().map { event($0.offset, $0.element) }, kind: .main), 7)
        let six = (0..<6).map { event($0, .tired) }
        XCTAssertEqual(WakeLearning.riseBpm(history: six, kind: .main), 8, "each decision starts a new count")
        let many = (0..<60).map { event($0, .tired) }
        XCTAssertEqual(WakeLearning.riseBpm(history: many, kind: .main), WakeLearning.maxRiseBpm)
    }

    func testRestedWakesLowerItAndOnlyAdaptiveAnswersOfTheKindCount() {
        let four = (0..<4).map { event($0, .fresh) }
        XCTAssertEqual(WakeLearning.riseBpm(history: four, kind: .main), 5)
        let many = (0..<40).map { event($0, .fresh) }
        XCTAssertEqual(WakeLearning.riseBpm(history: many, kind: .main), WakeLearning.minRiseBpm)
        let deadline = (0..<5).map { event($0, .tired, adaptive: false) }
        XCTAssertEqual(WakeLearning.riseBpm(history: deadline, kind: .main), 6)
        let fajr = (0..<5).map { event($0, .tired, kind: .fajr) }
        XCTAssertEqual(WakeLearning.riseBpm(history: fajr, kind: .main), 6)
        XCTAssertEqual(WakeLearning.riseBpm(history: fajr, kind: .fajr), 7)
        XCTAssertEqual(WakeLearning.answeredCount(history: fajr + deadline, kind: .fajr), 5)
    }

    func testPendingQuestionAndUpsert() {
        let woke = at(2026, 11, 17, 6, 41)
        let adaptive = WakeEvent(id: "main-1", kind: .main, windowStart: at(2026, 11, 17, 6, 30),
                                 deadline: at(2026, 11, 17, 7, 0), wokeAt: woke, adaptive: true, trough: 51,
                                 bpmAtWake: 58, riseBpm: 6, feeling: nil, answeredAt: nil)
        var deadline = adaptive
        deadline.wokeAt = at(2026, 11, 17, 7, 0)
        deadline.adaptive = false
        deadline.trough = nil
        let merged = WakeLearning.upserting(deadline, into: [adaptive])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.wokeAt, woke, "the earlier, adaptive wake is kept")
        XCTAssertEqual(merged.first?.adaptive, true)
        XCTAssertEqual(merged.first?.trough, 51)
        XCTAssertEqual(WakeLearning.pendingQuestion(history: merged, now: at(2026, 11, 17, 7, 30))?.id, "main-1")
        XCTAssertNil(WakeLearning.pendingQuestion(history: merged, now: at(2026, 11, 17, 19, 0)), "12 h at most")
        var answered = adaptive
        answered.feeling = .tired
        let kept = WakeLearning.upserting(deadline, into: [answered])
        XCTAssertEqual(kept.first?.feeling, .tired, "a later entry does not erase the answer")
        XCTAssertNil(WakeLearning.pendingQuestion(history: kept, now: at(2026, 11, 17, 7, 30)))
    }

    // MARK: - MAWAQIT and the calculation

    private func timetableJSON(november16: [String]) -> Data {
        var months: [[String: [String]]] = Array(repeating: [:], count: 12)
        months[10] = ["16": november16]
        let root: [String: Any] = ["uuid": Mawaqit.mosqueUUID, "name": "MASJID AT-TAWBA - BAGNOLS-SUR-CEZE",
                                   "timezone": "Europe/Paris", "calendar": months]
        return try! JSONSerialization.data(withJSONObject: root)
    }

    func testTimetableGivesTheMosquesFajr() {
        let fetched = at(2026, 11, 16, 3, 0)
        let six = Mawaqit.parsePrayerTimes(timetableJSON(november16: ["06:17", "07:39", "12:32", "14:55", "17:19", "18:35"]),
                                           fetchedAt: fetched)
        XCTAssertEqual(six?.year, 2026)
        XCTAssertEqual(six.flatMap { Mawaqit.fajrAdhan(on: at(2026, 11, 16, 12, 0), timetable: $0) }, at(2026, 11, 16, 6, 17))
        let seven = Mawaqit.parsePrayerTimes(timetableJSON(november16: ["05:57", "06:17", "07:39", "12:32", "14:55", "17:19", "18:35"]),
                                             fetchedAt: fetched)
        XCTAssertEqual(seven.flatMap { Mawaqit.fajrAdhan(on: at(2026, 11, 16, 12, 0), timetable: $0) },
                       at(2026, 11, 16, 6, 17), "Sabah is the Fajr of a mosque displaying Imsak")
        XCTAssertNil(Mawaqit.parsePrayerTimes(Data("{\"calendar\": []}".utf8), fetchedAt: fetched))
        XCTAssertNil(Mawaqit.parsePrayerTimes(Data("not json".utf8), fetchedAt: fetched))
    }

    func testOtherYearOrBadTimeFallsBackToTheCalculation() {
        let fetched = at(2026, 11, 16, 3, 0)
        let timetable = Mawaqit.parsePrayerTimes(timetableJSON(november16: ["06:17", "07:39", "12:32", "14:55", "17:19", "18:35"]),
                                                 fetchedAt: fetched)!
        XCTAssertNil(Mawaqit.fajrAdhan(on: at(2027, 11, 16, 12, 0), timetable: timetable))
        if case .calculated? = FajrTimes.adhan(on: at(2027, 11, 16, 12, 0), timetable: timetable)?.source {} else {
            XCTFail("another year is calculated")
        }
        if case .mosque? = FajrTimes.adhan(on: at(2026, 11, 16, 12, 0), timetable: timetable)?.source {} else {
            XCTFail("the timetable's own day comes from the mosque")
        }
        XCTAssertNil(Mawaqit.fajrClock("6h17"))
        XCTAssertNil(Mawaqit.fajrClock("24:00"))
        XCTAssertEqual(Mawaqit.fajrClock("06:17")?.minute, 17)
    }

    func testCalculationLandsJustBeforeTheMosquesAdhan() {
        // The mosque's own 2026 Fajr (mawaqit.net/fr/m/masjid-tawba), across the seasons and both sides of DST.
        let mosque: [(Int, Int, Int, Int)] = [(1, 15, 6, 51), (3, 15, 5, 38), (6, 21, 4, 10),
                                              (9, 15, 6, 2), (11, 16, 6, 17), (12, 21, 6, 49)]
        for (month, day, hour, minute) in mosque {
            let official = at(2026, month, day, hour, minute)
            guard let calculated = FajrCalculator.fajr(on: at(2026, month, day, 12, 0)) else {
                return XCTFail("no Fajr on \(month)/\(day)")
            }
            XCTAssertLessThanOrEqual(calculated, official, "\(month)/\(day): never after the adhan")
            XCTAssertLessThanOrEqual(official.timeIntervalSince(calculated), 10 * 60, "\(month)/\(day): within 10 min")
        }
    }

    func testDailyRefreshAndOutcomes() {
        let now = at(2026, 11, 16, 12, 0)
        XCTAssertTrue(Mawaqit.needsRefresh(nil, now: now))
        var cached = MawaqitTimetable(uuid: Mawaqit.mosqueUUID, name: "M", timezone: "Europe/Paris",
                                      calendar: Array(repeating: [:], count: 12),
                                      fetchedAt: now.addingTimeInterval(-3600), year: 2026)
        XCTAssertFalse(Mawaqit.needsRefresh(cached, now: now))
        cached.fetchedAt = now.addingTimeInterval(-21 * 3600)
        XCTAssertTrue(Mawaqit.needsRefresh(cached, now: now))
        cached.fetchedAt = now.addingTimeInterval(-3600)
        cached.year = 2025
        XCTAssertTrue(Mawaqit.needsRefresh(cached, now: now))

        let body = timetableJSON(november16: ["06:17", "07:39", "12:32", "14:55", "17:19", "18:35"])
        XCTAssertEqual(MawaqitClient.outcome(status: 200, data: body, now: now).1, .ok)
        XCTAssertEqual(MawaqitClient.outcome(status: 200, data: Data("{}".utf8), now: now).1, .invalid)
        XCTAssertEqual(MawaqitClient.outcome(status: 401, data: Data(), now: now).1, .unauthorized)
        XCTAssertEqual(MawaqitClient.outcome(status: 503, data: Data(), now: now).1, .network)
    }

    // MARK: - Notifications and the Coach

    func testNotificationActionsCarryTheirWindow() {
        let window = WakeWindow(kind: .fajr, start: at(2026, 11, 17, 5, 57), deadline: at(2026, 11, 17, 6, 17),
                                adaptive: true)
        let info = WakeNotification.userInfo(window)
        let tired = WakeNotification.response(category: WakeNotification.adaptiveCategoryId,
                                              actionIdentifier: WakeNotification.tiredActionId, userInfo: info)
        XCTAssertEqual(tired, WakeNotification.Response(window: window, feeling: .tired, awake: true, adaptive: true))
        let up = WakeNotification.response(category: WakeNotification.deadlineCategoryId,
                                           actionIdentifier: WakeNotification.awakeActionId, userInfo: info)
        XCTAssertEqual(up?.feeling, nil)
        XCTAssertEqual(up?.adaptive, false)
        XCTAssertNil(WakeNotification.response(category: "other", actionIdentifier: WakeNotification.tiredActionId,
                                               userInfo: info))
        XCTAssertNil(WakeNotification.response(category: WakeNotification.adaptiveCategoryId,
                                               actionIdentifier: "com.apple.UNNotificationDefaultActionIdentifier",
                                               userInfo: info))
    }

    func testCoachAlarmBlockStatesTheWakeAndTheAlarms() {
        let zone = TimeZone(identifier: "Europe/Paris")!
        let next = WakeWindow(kind: .fajr, start: at(2026, 11, 17, 5, 57), deadline: at(2026, 11, 17, 6, 17), adaptive: true)
        let facts = WakeAlarmFacts(mainEnabled: true, mainMinutes: 6 * 60 + 30, mainWeekdays: [], adaptive: true,
                                   windowMinutes: 30, fajrEnabled: true, fajrLeadMinutes: 20, fajrAdaptive: true,
                                   nextAdhan: at(2026, 11, 17, 6, 17), adhanFromMosque: false, next: next,
                                   mainRiseBpm: 7, mainAnswers: 3, fajrRiseBpm: 6, fajrAnswers: 0, lastWake: nil)
        let block = CoachFiche.alarmBlock(facts, zone: zone)
        XCTAssertTrue(block.hasPrefix("ALARMS"))
        XCTAssertTrue(block.contains("main alarm: on, adaptive, earliest 06:30, window 30 min, guaranteed by 07:00, every day"))
        XCTAssertTrue(block.contains("Fajr alarm: on, 20 min before the adhan, adaptive in that margin, never after the adhan"))
        XCTAssertTrue(block.contains("next adhan Tue 2026-11-17 06:17 (calculated on the phone"))
        XCTAssertTrue(block.contains("next wake: Fajr, window Tue 2026-11-17 05:57 to Tue 2026-11-17 06:17"))
        XCTAssertTrue(block.contains("learned threshold: main +7 bpm (3 answers)"))

        var off = facts
        off.mainEnabled = false
        off.fajrEnabled = false
        off.next = nil
        let quiet = CoachFiche.alarmBlock(off, zone: zone)
        XCTAssertTrue(quiet.contains("main alarm: off"))
        XCTAssertTrue(quiet.contains("Fajr alarm: off"))
        XCTAssertFalse(quiet.contains("next wake"))
    }
}
