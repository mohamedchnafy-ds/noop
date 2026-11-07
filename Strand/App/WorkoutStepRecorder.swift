import Foundation
#if os(iOS)
import CoreMotion
#endif

// MARK: - The phone's steps during an outdoor walk, run or hike (personal fork, chantier 14)

/// Reads the iPhone's pedometer while an on-foot GPS workout runs and keeps one reading every five
/// seconds (`WorkoutStepMath.sampleSeconds`). A WHOOP 4.0 has no step count over Bluetooth, so this is the
/// workout's only live step source; the phone has to be carried.
///
/// Fail-safe like `GpsWorkoutRecorder`: no pedometer (a Mac), Motion & Fitness refused, or no update yet,
/// and it records nothing; the workout still saves its heart rate and route. The cadence shown live and on
/// the detail screen is computed from these readings by `WorkoutStepMath`, never from the pedometer's own
/// cadence field, so the two read-outs cannot disagree.
@MainActor
final class WorkoutStepRecorder: ObservableObject {

    /// The readings so far (steps since the start, pauses left out).
    @Published private(set) var samples: [WorkoutStepSample] = []
    /// True between `start` and `stop`.
    @Published private(set) var isRecording = false

    /// Steps so far, nil before the first reading.
    var steps: Int? { samples.last?.steps }

    #if os(iOS)
    private let pedometer = CMPedometer()
    #endif
    private var timer: Timer?
    /// The pedometer's count since the workout's start, as last reported.
    private var cumulative: Int?
    /// Steps the pedometer counted that are not the workout's: those taken while paused, and, after a
    /// relaunch, the difference between its count and the readings banked before the kill.
    private var offset = 0
    private var cumulativeAtPause: Int?
    private var isPaused = false
    /// After a relaunch, the last banked reading the first pedometer count is lined up with.
    private var rebaseTo: Int?
    private var persistedCount = 0

    /// Begin reading for a workout started at `start`.
    func start(at start: Date) {
        reset()
        isRecording = true
        beginUpdates(from: start)
    }

    /// Re-arm after an in-flight workout was restored from disk, continuing the readings banked before.
    func restore(start: Date, paused: Bool) {
        let banked = ActiveStepStore.load()
        reset()
        isRecording = true
        if let banked {
            samples = banked
            persistedCount = banked.count
            ActiveStepStore.store(banked)
            rebaseTo = banked.last?.steps
        }
        isPaused = paused
        beginUpdates(from: start)
    }

    func pause() {
        guard isRecording, !isPaused else { return }
        isPaused = true
        cumulativeAtPause = cumulative
    }

    func resume() {
        guard isRecording, isPaused else { return }
        isPaused = false
        if let atPause = cumulativeAtPause, let now = cumulative { offset += max(0, now - atPause) }
        cumulativeAtPause = nil
    }

    /// Stop reading and return the readings (possibly empty).
    @discardableResult
    func stop() -> [WorkoutStepSample] {
        #if os(iOS)
        pedometer.stopUpdates()
        #endif
        timer?.invalidate()
        timer = nil
        isRecording = false
        ActiveStepStore.clear()
        return samples
    }

    // MARK: Updates

    private func reset() {
        timer?.invalidate()
        timer = nil
        samples = []
        cumulative = nil
        offset = 0
        cumulativeAtPause = nil
        isPaused = false
        rebaseTo = nil
        persistedCount = 0
        ActiveStepStore.clear()
    }

    private func beginUpdates(from start: Date) {
        #if os(iOS)
        guard CMPedometer.isStepCountingAvailable() else { return }
        switch CMPedometer.authorizationStatus() {
        case .denied, .restricted: return
        default: break
        }
        pedometer.startUpdates(from: start) { [weak self] data, _ in
            guard let count = data?.numberOfSteps.intValue else { return }
            Task { @MainActor [weak self] in self?.takePedometerCount(count) }
        }
        let interval = TimeInterval(WorkoutStepMath.sampleSeconds)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.takeStepReading() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        #endif
    }

    private func takePedometerCount(_ count: Int) {
        guard isRecording else { return }
        if let target = rebaseTo {
            // The pedometer counts from the workout's start, pauses included; line its count up with the
            // last reading banked before the relaunch.
            offset = max(0, count - target)
            rebaseTo = nil
        }
        // Paused before the first count (or restored paused): the pause starts from this count.
        if isPaused, cumulativeAtPause == nil { cumulativeAtPause = count }
        cumulative = count
    }

    /// One reading every five seconds while running (none while paused).
    private func takeStepReading() {
        guard isRecording, !isPaused, let cumulative, rebaseTo == nil else { return }
        let active = max(samples.last?.steps ?? 0, cumulative - offset)
        samples.append(WorkoutStepSample(tMs: Int64(Date().timeIntervalSince1970 * 1000), steps: active))
        if samples.count - persistedCount >= ActiveStepStore.samplesPerWrite {
            ActiveStepStore.store(samples)
            persistedCount = samples.count
        }
    }
}
