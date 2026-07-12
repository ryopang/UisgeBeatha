import SwiftUI

/// The bundled seed data is loaded once at launch and injected here so any
/// view (autocomplete, lookup result matching) can read it.
extension EnvironmentValues {
    @Entry var distilleryStore = DistilleryStore(distilleries: [])
}
