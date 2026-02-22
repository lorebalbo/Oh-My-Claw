import Foundation

/// Manages menu bar icon animation frames during file processing.
/// Cycles through SF Symbol variants at a fixed interval to convey activity.
@MainActor
@Observable
final class IconAnimator {
    private(set) var currentFrame: Int = 0
    private var timer: Timer?

    /// SF Symbol names to cycle through during processing.
    private let frames = [
        "arrow.down.doc",
        "arrow.down.doc.fill",
        "arrow.up.doc.fill"
    ]

    /// The SF Symbol name for the current animation frame.
    var currentIconName: String {
        frames[currentFrame % frames.count]
    }

    /// Start the animation timer. Idempotent — no-op if already running.
    func startAnimating() {
        guard timer == nil else { return }
        currentFrame = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.currentFrame += 1
            }
        }
    }

    /// Stop the animation and reset to the first frame.
    func stopAnimating() {
        timer?.invalidate()
        timer = nil
        currentFrame = 0
    }
}
