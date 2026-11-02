import SwiftUI

extension EnvironmentValues {
    /// Set when a view is shown in an inline panel (the iPhone Duo's scan
    /// result panel) instead of a sheet. SwiftUI's own `dismiss` does
    /// nothing in a panel, so the panel supplies its own closer here.
    @Entry var panelDismiss: (() -> Void)?
}

/// A `dismiss` that works in both presentations: it closes the panel when
/// one is present, and falls back to the system action for sheets.
///
/// Any sheet a panel view presents itself must reset `panelDismiss` to nil
/// on its content, or `Cancel` in that nested sheet would close the panel
/// underneath it.
struct ContextualDismiss: DynamicProperty {
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.panelDismiss) private var panelDismiss

    func callAsFunction() {
        if let panelDismiss {
            panelDismiss()
        } else {
            systemDismiss()
        }
    }
}
