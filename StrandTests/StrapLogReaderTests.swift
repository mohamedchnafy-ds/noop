import XCTest
@testable import Strand

/// The strap log in plain words (personal fork, Démarrer tools): fixed rules on each line's own text, routine
/// lines folded, unknown lines kept as technical lines, and nothing stated that the line does not say.
final class StrapLogReaderTests: XCTestCase {

    private let flushAttempt = "[19:40:39] standard-hr transport flush-attempt reason=cadence offeredHRRows=28 offeredRRRows=2"
    private let flushOK = "[19:40:39] standard-hr transport flush-succeeded reason=cadence offeredHRRows=28 offeredRRRows=2 insertedHRRows=27 insertedRRRows=2"
    private let realtime = "[19:40:39] → Toggle Realtime HR payload=01"
    private let battery = "[19:40:39] → Get Battery Level payload=00"
    private let pending = "Command response: TOGGLE_REALTIME_HR(3) → PENDING(2)"

    private func read(_ lines: [String]) -> StrapLogReading {
        StrapLogReader.readStrapLog(lines[lines.startIndex...])
    }

    func testTheStampIsSplitOffAndADomainTagIsNotAStamp() {
        let (clock, body) = StrapLogReader.splitStrapLogClock("[19:40:39] Connected — discovering services")
        XCTAssertEqual(clock, "19:40")
        XCTAssertEqual(String(body), "Connected — discovering services")
        let tagged = StrapLogReader.splitStrapLogClock("[connection] connect up gen=3")
        XCTAssertNil(tagged.clock)
        XCTAssertEqual(String(tagged.body), "[connection] connect up gen=3")
    }

    func testTheHeartRateFlushReadsItsCountsAndItsAttemptHasNoSentence() {
        let phrase = StrapLogReader.strapLogPhrase(for: StrapLogReader.splitStrapLogClock(flushOK).body)
        XCTAssertEqual(phrase?.topic, .heartRate)
        XCTAssertEqual(phrase?.title, "Heart rate saved")
        XCTAssertEqual(phrase?.detail, "Heart-rate readings: 27 · beat intervals: 2")
        XCTAssertNil(StrapLogReader.strapLogPhrase(for: StrapLogReader.splitStrapLogClock(flushAttempt).body))
    }

    func testABatteryRequestNeverStatesAPercentage() {
        let phrase = StrapLogReader.strapLogPhrase(for: StrapLogReader.splitStrapLogClock(battery).body)
        XCTAssertEqual(phrase?.topic, .battery)
        XCTAssertEqual(phrase?.title, "Battery level requested")
        XCTAssertNil(phrase?.detail)
    }

    func testRoutineLinesFoldWithACounterNewestFirst() {
        var lines: [String] = []
        for _ in 0..<3 { lines += [flushAttempt, flushOK, realtime, battery, pending] }
        let reading = read(lines)
        let sentences = reading.strapLogRows(topic: nil, technical: false)
        XCTAssertEqual(sentences.count, 4)
        XCTAssertEqual(sentences.map(\.repeats), [3, 3, 3, 3])
        XCTAssertEqual(sentences.first?.phrase?.title, "Strap's reply: in progress")
        XCTAssertEqual(sentences.first?.phrase?.detail, "About live heart rate")
        XCTAssertEqual(reading.technicalLines, 3)
    }

    func testASentenceWithoutAFoldKeyStopsTheFold() {
        let lines = [flushOK, "[19:41:02] Disconnected — The connection has timed out unexpectedly. [CBError.6]", flushOK]
        let sentences = read(lines).strapLogRows(topic: nil, technical: false)
        XCTAssertEqual(sentences.map(\.phrase?.title), ["Heart rate saved", "Strap disconnected", "Heart rate saved"])
        XCTAssertEqual(sentences[1].phrase?.topic, .problem)
        XCTAssertEqual(sentences[1].phrase?.detail, "The connection has timed out unexpectedly.")
    }

    func testAnUnstampedLineTakesTheClockOfTheLineBeforeIt() {
        let sentences = read([realtime, pending]).strapLogRows(topic: nil, technical: false)
        XCTAssertEqual(sentences.first?.clock, "19:40")
    }

    func testUnknownLinesAreTechnicalAndOnlyShownWithTheSwitch() {
        let lines = ["[19:31:20] Services discovered: 180A, 180F", "[19:31:20] Notify active 61080003",
                     "[19:31:21] BONDED (confirmed write acknowledged) — custom channels should now flow"]
        let reading = read(lines)
        XCTAssertEqual(reading.technicalLines, 2)
        XCTAssertEqual(reading.strapLogRows(topic: nil, technical: false).count, 1)
        let all = reading.strapLogRows(topic: nil, technical: true)
        XCTAssertEqual(all.count, 2)
        XCTAssertNil(all[1].phrase)
        XCTAssertEqual(all[1].lineCount, 2)
        XCTAssertEqual(reading.strapLogRows(topic: .connection, technical: true).count, 1)
    }

    func testTheHistoryEndingSaysWhatTheLineSays() {
        func title(_ line: String) -> String? { StrapLogReader.strapLogPhrase(for: Substring(line))?.title }
        XCTAssertEqual(title("Backfill: session ended — reason=HISTORY_COMPLETE"), "History up to date")
        XCTAssertEqual(title("Backfill: session ended — reason=timeout outcome=drained"), "History fetch finished")
        XCTAssertEqual(title("Backfill: session ended — reason=timeout outcome=nothing-banked"), "History sync interrupted")
        XCTAssertEqual(title("Backfill: session ended — reason=keepalive"), "History fetch stopped")
        XCTAssertEqual(StrapLogReader.strapLogPhrase(for: "Backfill: session persisted 412 rows (3 with motion, 0 skin-temp) across 1 night(s).")?.detail,
                       "Readings saved: 412")
    }

    func testTheSignalStrengthBands() {
        XCTAssertEqual(StrapLogReader.strapLogSignal(-61), "Signal good (−61 dBm)")
        XCTAssertEqual(StrapLogReader.strapLogSignal(-80), "Signal fair (−80 dBm)")
        XCTAssertEqual(StrapLogReader.strapLogSignal(-92), "Signal weak (−92 dBm)")
    }

    func testTheLinkSummary() {
        let off = StrapLinkSummary.strapLinkSummary(deviceName: "WHOOP 4.0", connected: false, trusted: false,
                                                    liveHeartRate: false, syncing: false, batteryPercent: nil,
                                                    lastSyncLabel: "2 min ago")
        XCTAssertEqual(off.level, .off)
        XCTAssertEqual(off.title, "WHOOP 4.0 not connected")
        XCTAssertEqual(off.detail, "History synced 2 min ago")
        let good = StrapLinkSummary.strapLinkSummary(deviceName: "WHOOP 4.0", connected: true, trusted: true,
                                                     liveHeartRate: true, syncing: false, batteryPercent: 73,
                                                     lastSyncLabel: "2 min ago")
        XCTAssertEqual(good.level, .good)
        XCTAssertEqual(good.title, "Connected to WHOOP 4.0")
        XCTAssertEqual(good.detail, "live heart rate arriving · history synced 2 min ago · battery \(StrapLogReader.strapLogPercent(73))")
        let half = StrapLinkSummary.strapLinkSummary(deviceName: "WHOOP 4.0", connected: true, trusted: false,
                                                     liveHeartRate: false, syncing: true, batteryPercent: nil,
                                                     lastSyncLabel: nil)
        XCTAssertEqual(half.level, .warning)
        XCTAssertEqual(half.detail, "fetching the history")
        let shortcut = StrapLinkSummary.strapLinkSummary(deviceName: "WHOOP 5.0", connected: true, trusted: true,
                                                         liveHeartRateOnly: true, liveHeartRate: true, syncing: false,
                                                         batteryPercent: nil, lastSyncLabel: nil)
        XCTAssertEqual(shortcut.level, .warning)
        XCTAssertEqual(shortcut.title, "Connected to WHOOP 5.0: live heart rate only")
    }
}
