//
//  UisgeBeathaApp.swift
//  UisgeBeatha
//

import OSLog
import SwiftData
import SwiftUI

@main
struct UisgeBeathaApp: App {
    /// Opening the store can fail (corruption, a failed migration). The
    /// app shows a recovery screen rather than crashing on every launch.
    enum ContainerState {
        case ready(ModelContainer)
        case failed(String)
    }

    @State private var containerState: ContainerState
    let distilleryStore: DistilleryStore
    let expressionStore: ExpressionStore
    let stockPhotoBackfill: StockPhotoBackfill

    private static let logger = Logger(subsystem: "com.ryo.UisgeBeatha", category: "App")

    init() {
        AppNetwork.configureSharedImageCache()
        _containerState = State(initialValue: Self.openContainer())

        do {
            distilleryStore = try DistilleryStore.loadBundled()
        } catch {
            // Autocomplete and region auto-fill degrade quietly; manual entry
            // still works with an empty store.
            Self.logger.error("Failed to load distillery seed data: \(error)")
            distilleryStore = DistilleryStore(distilleries: [])
        }

        do {
            expressionStore = try ExpressionStore.loadBundled()
        } catch {
            // Label-scan name/age/ABV resolution degrades to OCR-only
            // reads; nothing else depends on this catalog.
            Self.logger.error("Failed to load expression catalog: \(error)")
            expressionStore = ExpressionStore(expressions: [])
        }

        stockPhotoBackfill = StockPhotoBackfill(search: Self.productImageSearchService())
    }

    var body: some Scene {
        WindowGroup {
            switch containerState {
            case .ready(let container):
                RootTabView()
                    .environment(\.distilleryStore, distilleryStore)
                    .environment(\.expressionStore, expressionStore)
                    .environment(\.barcodeLookup, Self.lookupService())
                    .environment(\.wikipedia, Self.wikipediaService())
                    .environment(\.labelOCR, Self.labelOCRService(distilleryStore: distilleryStore, expressionStore: expressionStore))
                    .environment(\.stockPhotoBackfill, stockPhotoBackfill)
                    .modelContainer(container)
            case .failed(let message):
                ContainerRecoveryView(
                    errorDescription: message,
                    onRetry: { containerState = Self.openContainer() },
                    onReset: {
                        do {
                            try AppContainer.resetStore()
                        } catch {
                            Self.logger.error("Failed to reset store: \(error)")
                        }
                        containerState = Self.openContainer()
                    }
                )
            }
        }
    }

    private static func openContainer() -> ContainerState {
        do {
            return .ready(try AppContainer.make())
        } catch {
            logger.error("Failed to create ModelContainer: \(error)")
            return .failed(String(describing: error))
        }
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
