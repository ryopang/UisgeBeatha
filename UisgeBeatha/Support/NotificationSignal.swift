import Foundation

/// A notification as a plain `AsyncStream<Void>`: "this happened", with no
/// payload. `Notification` itself isn't `Sendable`, which makes iterating
/// `NotificationCenter.notifications(named:)` awkward under strict
/// concurrency; the callers here only care that it fired.
nonisolated enum NotificationSignal {
    /// NSObjectProtocol observer tokens aren't `Sendable`; this box only ever
    /// hands the token back to the same center to remove it.
    private final class Token: @unchecked Sendable {
        let observer: NSObjectProtocol
        init(_ observer: NSObjectProtocol) { self.observer = observer }
    }

    static func stream(
        for name: Notification.Name, center: NotificationCenter = .default
    ) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let token = Token(
                center.addObserver(forName: name, object: nil, queue: nil) { _ in
                    continuation.yield()
                }
            )
            continuation.onTermination = { _ in
                center.removeObserver(token.observer)
            }
        }
    }
}
