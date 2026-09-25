import CoreGraphics

/// Swipe handling shared by the touch controls on iPhone and iPad.
enum TouchGesture {
    /// How far a finger must travel before a drag is tracked at all.
    static let minimumDistance: CGFloat = 24
    /// How far a drag must travel to count as a swipe.
    static let swipeDistance: CGFloat = 60
}

/// The dominant direction of a finished drag, or `nil` if it was too short to be a swipe.
enum SwipeDirection {
    case up
    case down
    case left
    case right

    init?(translation: CGSize) {
        let isVertical = abs(translation.height) > abs(translation.width)
        let distance = isVertical ? translation.height : translation.width
        guard abs(distance) >= TouchGesture.swipeDistance else { return nil }
        switch (isVertical, distance < .zero) {
        case (true, true): self = .up
        case (true, false): self = .down
        case (false, true): self = .left
        case (false, false): self = .right
        }
    }
}
