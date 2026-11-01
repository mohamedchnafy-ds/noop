import XCTest
@testable import Strand

/// The Coach crash fix: a provider reports its streamed chunks from the network thread, and the engine
/// used to write them straight into its `@Published` transcript from there. `CoachStreamRelay` must
/// deliver every chunk, in order, to a main-actor consumer; pass the provider's error through; and
/// cancel the provider when the consumer stops (the Stop button).
@MainActor
final class CoachStreamRelayTests: XCTestCase {

    /// `Thread.isMainThread` read from a synchronous function, so the async tests can ask it.
    nonisolated private static func onMainThread() -> Bool { Thread.isMainThread }

    func testChunksFromABackgroundThreadArriveInOrderOnTheMainActor() async throws {
        let chunks = (0..<200).map { "c\($0) " }
        let stream = CoachStreamRelay.deltas { onDelta in
            XCTAssertFalse(Self.onMainThread(), "the provider must run off the main thread")
            for chunk in chunks { onDelta(chunk) }
        }

        var received: [String] = []
        for try await chunk in stream {
            XCTAssertTrue(Self.onMainThread(), "every chunk must be consumed on the main actor")
            received.append(chunk)
        }
        XCTAssertEqual(received, chunks)
    }

    func testTheProviderErrorEndsTheStreamAfterTheChunksBeforeIt() async {
        struct Boom: Error {}
        let stream = CoachStreamRelay.deltas { onDelta in
            onDelta("partial ")
            onDelta("reply")
            throw Boom()
        }

        var received = ""
        do {
            for try await chunk in stream { received += chunk }
            XCTFail("the provider's error must reach the consumer")
        } catch {
            XCTAssertTrue(error is Boom)
        }
        XCTAssertEqual(received, "partial reply")
    }

    func testStoppingTheConsumerCancelsTheProvider() async {
        let providerCancelled = expectation(description: "provider sees cancellation")
        let firstChunk = expectation(description: "first chunk consumed")
        let stream = CoachStreamRelay.deltas { onDelta in
            onDelta("start")
            // Stands in for a reply that keeps streaming until the request is cancelled.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            providerCancelled.fulfill()
        }

        let consumer = Task { @MainActor in
            var sawFirst = false
            for try await _ in stream where !sawFirst {
                sawFirst = true
                firstChunk.fulfill()
            }
        }
        await fulfillment(of: [firstChunk], timeout: 5)
        consumer.cancel()
        await fulfillment(of: [providerCancelled], timeout: 5)
    }

    func testThrottlePublishesTheFirstChunkThenAtMostEveryInterval() {
        var throttle = CoachStreamThrottle()
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(throttle.shouldPublish(at: start), "the reply starts showing at once")
        XCTAssertFalse(throttle.shouldPublish(at: start.addingTimeInterval(0.05)))
        XCTAssertFalse(throttle.shouldPublish(at: start.addingTimeInterval(0.099)))
        XCTAssertTrue(throttle.shouldPublish(at: start.addingTimeInterval(CoachStreamThrottle.interval)))
        XCTAssertFalse(throttle.shouldPublish(at: start.addingTimeInterval(0.15)))
        XCTAssertTrue(throttle.shouldPublish(at: start.addingTimeInterval(0.25)))
    }
}
