//
//  UisgeBeathaApp.swift
//  UisgeBeatha
//

import SwiftData
import SwiftUI

@main
struct UisgeBeathaApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            // Local-only in v1. The schema follows the CloudKit-forward rules
            // in the PRD, so enabling mirroring later is a configuration
            // change, not a migration.
            modelContainer = try ModelContainer(for: Bottle.self, TastingNote.self)
        } catch {
            // Without a store the app cannot function at all.
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
