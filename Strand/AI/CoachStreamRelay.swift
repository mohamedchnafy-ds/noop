import Foundation

/// Carries a provider's streamed reply from the network thread to the main actor.
///
/// `AIProviderClient.stream` reports each text chunk through a plain callback, and the provider calls
/// it from wherever `URLSession.AsyncBytes` resumes, which is NOT the main thread. The Coach engine is
/// `@MainActor` and its transcript is `@Published`, so a callback that wrote the transcript directly
/// mutated SwiftUI state off the main thread while the screen was reading it. Under
/// `SWIFT_STRICT_CONCURRENCY: minimal` the compiler says nothing about that, and the result was an
/// intermittent crash, most often when switching tab or scrolling during a reply.
///
/// The relay runs the provider on a detached task and hands every chunk through an
/// `AsyncThrowingStream`, which is safe to yield into from any thread. The engine iterates the
/// stream on the main actor, so every transcript write happens there. Cancelling the iterating task
/// (the Coach "Stop" button) ends the stream and cancels the provider task, which cancels the HTTP
/// request with it.
enum CoachStreamRelay {

    /// Run `produce` off the main actor and stream every chunk it reports, in order.
    ///
    /// The stream finishes when `produce` returns, finishes throwing what `produce` throws, and
    /// cancels `produce` as soon as the consumer stops iterating.
    static func deltas(
        _ produce: @escaping @Sendable (_ onDelta: @escaping @Sendable (String) -> Void) async throws -> Void
    ) -> AsyncThrowingStream<String, Error> {
        events(produce)
    }

    /// The same relay for any event type (personal fork): a tool round streams its text and then the
    /// finished turn (`AnthropicStreamEvent`), through the same detached producer and the same
    /// cancellation.
    static func events<Event: Sendable>(
        _ produce: @escaping @Sendable (_ emit: @escaping @Sendable (Event) -> Void) async throws -> Void
    ) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            let producer = Task.detached {
                do {
                    try await produce { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
    }
}

/// Decides when a streamed reply is worth re-publishing to the screen.
///
/// Providers can deliver dozens of chunks a second, and each publish re-renders the transcript
/// (Markdown included). Publishing at most every `interval` keeps the reply visibly streaming while
/// bounding that work to about ten renders a second. The first chunk is always published, so the
/// reply starts appearing at once. The caller publishes the full text once more when the stream
/// ends, so nothing received is ever left unshown.
struct CoachStreamThrottle {

    /// Minimum time between two publishes.
    static let interval: TimeInterval = 0.1

    private var lastPublish: Date?

    /// True when the text accumulated so far should be published at `now`; records the publish.
    mutating func shouldPublish(at now: Date) -> Bool {
        if let lastPublish, now.timeIntervalSince(lastPublish) < Self.interval { return false }
        lastPublish = now
        return true
    }
}
