//
//  UisgeBeathaApp.swift
//  UisgeBeatha
//

import OSLog
import SwiftData
import SwiftUI

@main
struct UisgeBeathaApp: App {
    let modelContainer: ModelContainer
    let distilleryStore: DistilleryStore

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

        do {
            distilleryStore = try DistilleryStore.loadBundled()
        } catch {
            // Autocomplete and region auto-fill degrade quietly; manual entry
            // still works with an empty store.
            Logger(subsystem: "com.ryo.UisgeBeatha", category: "App")
                .error("Failed to load distillery seed data: \(error)")
            distilleryStore = DistilleryStore(distilleries: [])
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.distilleryStore, distilleryStore)
        }
        .modelContainer(modelContainer)
    }
}
