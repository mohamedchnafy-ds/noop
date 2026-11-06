import XCTest
@testable import StrandDesign

/// `Hypnogram.displaySmoothed` absorbs every fragment under its threshold, which erased the awake bouts of a
/// night (17 min awake over four short awakenings drew nothing on the ring nor in the « Awake » row, while the
/// tile said 17 min). An awake bout of a minute or more now stays; a shorter one is still a flicker. The
/// Kotlin twin (`StageDisplaySmoothingTest.keepsAnAwakeBoutOfAMinuteOrMore`) runs the same fixture.
final class HypnogramSmoothingTests: XCTestCase {

    private func iv(_ stage: SleepStage, _ start: TimeInterval, _ end: TimeInterval) -> SleepInterval {
        SleepInterval(stage: stage, start: start, end: end)
    }

    private func same(_ a: [SleepInterval], _ b: [SleepInterval], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.map { "\($0.stage) \($0.start) \($0.end)" }, b.map { "\($0.stage) \($0.start) \($0.end)" },
                       file: file, line: line)
    }

    func testKeepsAnAwakeBoutOfAMinuteOrMore() {
        let out = Hypnogram.displaySmoothed([
            iv(.light, 0, 600),
            iv(.awake, 600, 720),
            iv(.light, 720, 1320),
            iv(.awake, 1320, 1350),
            iv(.light, 1350, 1950),
        ], minDuration: 300)
        same(out, [iv(.light, 0, 600), iv(.awake, 600, 720), iv(.light, 720, 1950)])
    }

    func testASleepFragmentUnderTheThresholdIsStillAbsorbed() {
        let out = Hypnogram.displaySmoothed([
            iv(.light, 0, 600),
            iv(.rem, 600, 720),
            iv(.light, 720, 1320),
        ], minDuration: 300)
        same(out, [iv(.light, 0, 1320)])
    }

    func testTheAwakeFloorIsATokenCallersCanLower() {
        let out = Hypnogram.displaySmoothed([
            iv(.light, 0, 600),
            iv(.awake, 600, 640),
            iv(.light, 640, 1240),
        ], minDuration: 300, awakeFloor: 30)
        same(out, [iv(.light, 0, 600), iv(.awake, 600, 640), iv(.light, 640, 1240)])
    }
}
