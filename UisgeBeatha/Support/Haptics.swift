import UIKit

/// The few haptic moments the motion spec names. Feedback generators are
/// cheap and need no setup; a device without a Taptic Engine ignores them.
@MainActor
enum Haptics {
    /// A bottle was added, or a scan found something.
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// A discrete choice changed (status cycled).
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
