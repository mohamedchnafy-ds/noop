#if os(iOS)
import SwiftUI
import UIKit

/// Today's swipe between days on iPhone, as a UIKit pan (personal fork, 8 Nov.).
///
/// The SwiftUI `DragGesture` it replaces was attached simultaneously over the page's scroll view, so it ran
/// beside every vertical scroll and the start of a scroll hitched. This pan refuses to BEGIN unless the
/// finger moves sideways (`gestureRecognizerShouldBegin`): a vertical drag fails it at once and the scroll
/// has the touch alone. Once begun it still runs beside the scroll, as before. macOS keeps the DragGesture.
struct TodayDaySwipeRecognizer: UIGestureRecognizerRepresentable {
    /// The named coordinate space the start point is reported in: the one the chart frames are read in.
    let space: String
    /// Called once per finished sideways pan: its start point in `space`, then its travel in x and y.
    let onEnded: (CGPoint, CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let travel = recognizer.translation(in: recognizer.view)
        switch recognizer.state {
        case .began:
            // The pan begins once the finger has moved a little: step back by that travel to the touch-down
            // point, which is where a swipe starting on a chart is recognised.
            let now = context.converter.location(in: .named(space))
            context.coordinator.start = CGPoint(x: now.x - travel.x, y: now.y - travel.y)
        case .ended:
            onEnded(context.coordinator.start, travel.x, travel.y)
        default:
            break
        }
    }

    /// Holds the start point between the pan's actions, and keeps the pan from beginning on a vertical drag.
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var start: CGPoint = .zero

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.5
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
#endif
