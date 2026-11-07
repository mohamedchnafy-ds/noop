import XCTest
@testable import StrandAnalytics

/// Personal fork, chantier 15: the arithmetic of a fast. The `sharedOracle` block below is the SAME
/// literal as in the Kotlin `FastingTimelineTest`: both platforms print their results in this exact
/// shape and compare to it, so a divergence shows as a differing line, not as two logs that disagree.
final class FastingTimelineTests: XCTestCase {

    private static let sharedOracle = """
phase e=-5 -> 0
phase e=0 -> 0
phase e=239 -> 0
phase e=240 -> 1
phase e=479 -> 1
phase e=480 -> 2
phase e=719 -> 2
phase e=720 -> 3
phase e=959 -> 3
phase e=960 -> 4
phase e=1439 -> 4
phase e=1440 -> 5
phase e=3000 -> 5
progress e=0 g=960 -> 0
remaining e=0 g=960 -> 960
progress e=702 g=960 -> 731
remaining e=702 g=960 -> 258
progress e=960 g=960 -> 1000
remaining e=960 g=960 -> 0
progress e=1200 g=960 -> 1000
remaining e=1200 g=960 -> 0
progress e=-10 g=960 -> 0
remaining e=-10 g=960 -> 960
progress e=500 g=0 -> 0
remaining e=500 g=0 -> 0
progress e=1 g=1080 -> 0
remaining e=1 g=1080 -> 1079
progress e=1079 g=1080 -> 999
remaining e=1079 g=1080 -> 1
progress e=333 g=999 -> 333
remaining e=333 g=999 -> 666
markers g=0 -> -
markers g=720 -> 1:333,2:666,3:1000
markers g=840 -> 1:285,2:571,3:857
markers g=960 -> 1:250,2:500,3:750,4:1000
markers g=1080 -> 1:222,2:444,3:666,4:888
markers g=1200 -> 1:200,2:400,3:600,4:800
markers g=1440 -> 1:166,2:333,3:500,4:666,5:1000
markers g=2160 -> 1:111,2:222,3:333,4:444,5:666
summary d=972,1026,870,996,0,1080 g=960 -> 988,4,5,1
summary d=- g=960 -> 0,0,0,0
summary d=0,0 g=960 -> 0,0,0,0
summary d=960,960,960 g=960 -> 960,3,3,3
summary d=1000,500,1000,1000 g=960 -> 875,3,4,2
summary d=900,1000 g=0 -> 950,0,2,0
summary d=1500,0,1200 g=1080 -> 1350,2,2,1
clamp m=0 -> 720
clamp m=719 -> 720
clamp m=720 -> 720
clamp m=961 -> 961
clamp m=2160 -> 2160
clamp m=2161 -> 2160
clamp m=5000 -> 2160
"""

    private func markerLine(_ goal: Int) -> String {
        let markers = FastingTimeline.fastingMarkers(goalMinutes: goal)
        let body = markers.isEmpty ? "-" : markers.map { "\($0.phaseIndex):\($0.permille)" }.joined(separator: ",")
        return "markers g=\(goal) -> \(body)"
    }

    private func summaryLine(_ durations: [Int], _ goal: Int) -> String {
        let s = FastingTimeline.fastingSummary(durationsMinutes: durations, goalMinutes: goal)
        let d = durations.isEmpty ? "-" : durations.map(String.init).joined(separator: ",")
        return "summary d=\(d) g=\(goal) -> \(s.averageMinutes),\(s.keptCount),\(s.fastedCount),\(s.streak)"
    }

    func testSharedOracleBlock() {
        var lines: [String] = []
        for e in [-5, 0, 239, 240, 479, 480, 719, 720, 959, 960, 1439, 1440, 3000] {
            lines.append("phase e=\(e) -> \(FastingTimeline.fastingPhaseIndex(elapsedMinutes: e))")
        }
        for (e, g) in [(0, 960), (702, 960), (960, 960), (1200, 960), (-10, 960), (500, 0), (1, 1080), (1079, 1080), (333, 999)] {
            lines.append("progress e=\(e) g=\(g) -> \(FastingTimeline.fastingProgressPermille(elapsedMinutes: e, goalMinutes: g))")
            lines.append("remaining e=\(e) g=\(g) -> \(FastingTimeline.fastingRemainingMinutes(elapsedMinutes: e, goalMinutes: g))")
        }
        for g in [0, 720, 840, 960, 1080, 1200, 1440, 2160] { lines.append(markerLine(g)) }
        lines.append(summaryLine([972, 1026, 870, 996, 0, 1080], 960))
        lines.append(summaryLine([], 960))
        lines.append(summaryLine([0, 0], 960))
        lines.append(summaryLine([960, 960, 960], 960))
        lines.append(summaryLine([1000, 500, 1000, 1000], 960))
        lines.append(summaryLine([900, 1000], 0))
        lines.append(summaryLine([1500, 0, 1200], 1080))
        for m in [0, 719, 720, 961, 2160, 2161, 5000] {
            lines.append("clamp m=\(m) -> \(FastingTimeline.clampGoalMinutes(m))")
        }
        XCTAssertEqual(lines.joined(separator: "\n"), Self.sharedOracle)
    }

    func testConstantsAreTheOnesTheScreensRelyOn() {
        XCTAssertEqual(FastingTimeline.phaseStartHours.count, FastingTimeline.phaseIds.count)
        XCTAssertEqual(FastingTimeline.phaseIds.first, "digestion")
        XCTAssertEqual(FastingTimeline.phaseIds.last, "autophagy")
        XCTAssertEqual(FastingTimeline.defaultGoalMinutes, 16 * 60)
        XCTAssertEqual(FastingTimeline.quickGoalHours, [14, 16, 18, 20])
        XCTAssertTrue(FastingTimeline.quickGoalHours.allSatisfy {
            FastingTimeline.clampGoalMinutes($0 * 60) == $0 * 60
        }, "every quick pick is inside the bounds")
    }

    func testAtTheGoalTheLastMarkerSitsOnTheEnd() {
        let markers = FastingTimeline.fastingMarkers(goalMinutes: 960)
        XCTAssertEqual(markers.last, FastingTimeline.Marker(phaseIndex: 4, permille: 1000), "16 h goal: ketosis starts at the end")
        XCTAssertEqual(FastingTimeline.fastingPhaseIndex(elapsedMinutes: 702), 2, "11 h 42 min: glycogen running low")
        XCTAssertEqual(FastingTimeline.fastingProgressPermille(elapsedMinutes: 702, goalMinutes: 960), 731)
    }
}
