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
    let expressionStore: ExpressionStore
    let stockPhotoBackfill: StockPhotoBackfill

    init() {
        AppNetwork.configureSharedImageCache()

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

        do {
            expressionStore = try ExpressionStore.loadBundled()
        } catch {
            // Label-scan name/age/ABV resolution degrades to OCR-only
            // reads; nothing else depends on this catalog.
            Logger(subsystem: "com.ryo.UisgeBeatha", category: "App")
                .error("Failed to load expression catalog: \(error)")
            expressionStore = ExpressionStore(expressions: [])
        }

        stockPhotoBackfill = StockPhotoBackfill(search: Self.productImageSearchService())
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.distilleryStore, distilleryStore)
                .environment(\.expressionStore, expressionStore)
                .environment(\.barcodeLookup, Self.lookupService())
                .environment(\.wikipedia, Self.wikipediaService())
                .environment(\.labelOCR, Self.labelOCRService(distilleryStore: distilleryStore, expressionStore: expressionStore))
                .environment(\.stockPhotoBackfill, stockPhotoBackfill)
        }
        .modelContainer(modelContainer)
    }

    private static func lookupService() -> any BarcodeLookupServicing {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestLookupStub") {
            return StubBarcodeLookupService()
        }
        #endif
        return CascadeBarcodeLookupService()
    }

    private static func wikipediaService() -> any WikipediaServicing {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestLookupStub") {
            return StubWikipediaService()
        }
        #endif
        return WikipediaService()
    }

    private static func labelOCRService(
        distilleryStore: DistilleryStore, expressionStore: ExpressionStore
    ) -> any LabelOCRServicing {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestLookupStub") {
            return StubLabelOCRService()
        }
        #endif
        return VisionLabelOCRService(
            customWords: VisionLabelOCRService.customWords(
                distilleryStore: distilleryStore, expressionStore: expressionStore
            )
        )
    }

    private static func productImageSearchService() -> any ProductImageSearching {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestLookupStub") {
            return StubProductImageSearchService()
        }
        #endif
        return CascadeImageSearchService()
    }
}
