import Foundation

/// Polls `condition` until it holds or `timeout` passes. Flow models do
/// their work in unstructured tasks, so tests wait on observable state
/// instead of sleeping for a fixed time.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(3),
    _ condition: @MainActor () -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
