import SwiftUI

extension EnvironmentValues {
    /// The namespace a list shares with the detail it pushes, so a row's
    /// thumbnail can grow into the detail's hero. nil outside the compact
    /// collection list.
    @Entry var zoomNamespace: Namespace.ID?
}

/// Marks a row thumbnail as the origin of a zoom transition.
struct ZoomSource: ViewModifier {
    let id: UUID
    @Environment(\.zoomNamespace) private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if let namespace, !reduceMotion {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

/// Makes a pushed detail zoom out of its row's thumbnail. Under Reduce
/// Motion the push keeps the system's default transition.
struct ZoomDestination: ViewModifier {
    let id: UUID
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        }
    }
}
