# v2.0 build: what was built, and what to do first on the Mac

Branch `claude/gracious-rubin-cgi79e`, built phase by phase from PRD v2.0. Each phase is its own commit, so any one can be reverted on its own.

**Nothing here has been compiled or run.** It was written in a Linux container with no Xcode or Swift toolchain. A tree-sitter parse of every Swift file is clean, so syntax is fine, but type checking, strict-concurrency checking and SwiftData/Generable macro expansion have never run. Expect a first build with some compile errors. They should be small and local.

## First hour on the Mac

1. **Back up first.** If your phone has the v1 build with real data, open it and export JSON from Settings before installing this build over it. The V1 to V2 store migration is covered by a test, but a backup costs nothing.
2. Open in **Xcode 27**. Set the iOS 27 SDK; the deployment target stays 26.0. Build.
3. Fix compile errors. Likeliest places, in order:
   - `Services/Recognition/FoundationModelsExtractor.swift`: the Foundation Models API surface (`@Generable`, `@Guide`, `GenerationOptions(sampling: .greedy)`, `respond(to:generating:options:)`) was written from memory of the iOS 26 API. If it won't compile, delete the file's `#if canImport(FoundationModels)` body and keep the two factory functions returning the no-op types. The app then runs exactly as it did without a model.
   - `Models/Schema/SchemaV1.swift` / `SchemaV2.swift`: `VersionedSchema` conformances under the project's `MainActor` default isolation. If Xcode complains about isolated conformances, mark the two schema enums and `UisgeMigrationPlan` `nonisolated`.
   - `Views/Scan/ScanView.swift`, `Views/Collection/CollectionView.swift`: the most restructured SwiftUI.
   - `Support/ContextualDismiss.swift`: a `DynamicProperty` wrapping two `@Environment` values.
4. Run unit tests. New suites: `ScanFlowTests`, `BottleDraftTests`, `LiveLabelReaderTests`, `AppContainerTests`, `ThumbnailCacheTests`, `CollectionSelectionTests`, `ExtractionMergerTests`, `TastingWheelTests`, `ExtractorAccuracyTests`, `ContrastTests`, `SchemaMigrationTests`, `PhotoSyncTests`, `BottleDeduplicatorTests`, `SyncStatusTests`. A failing test is as likely to be a wrong guess in the test as in the code; read both.
5. Run the UI tests. They launch with `-disableCloudSync` (the simulator has no iCloud account).

## iCloud setup (Phase 3)

- `Config/UisgeBeatha.entitlements` declares the CloudKit container `iCloud.com.ryo.UisgeBeatha` and push. `CODE_SIGN_ENTITLEMENTS` and the remote-notification background mode are already set in the project.
- In Xcode, Signing & Capabilities for the app target: confirm iCloud (CloudKit) and Background Modes show up and the container is ticked. Automatic signing registers the container with your paid team.
- If the entitlement is missing or the container can't be created, the app falls back to a local-only store on the same data and Settings says so. It never strands the collection.
- Run once from Xcode in Debug so SwiftData creates the CloudKit schema. **Deploy the schema to Production in the CloudKit Console before any TestFlight or App Store build.** This is the classic shipped-sync failure.

## What was built

| Phase | Commit | Summary |
|---|---|---|
| 0 | `chore: v2.0 project settings` | Version 2.0, iPhone-only, `DESIGN.md` removed |
| 1 | `feat(foundations)` | `SchemaV1` + migration plan, recovery screen instead of `fatalError`, async off-main `ImageStore`, thumbnail cache, throttled off-main live label parsing, `ScanFlow` and `BottleDraft`, Cancel during lookup |
| 2 | `feat(layout)` | Compact stack vs regular-width `NavigationSplitView`, two-column detail, hero `scaledToFit`, single photo menu, scan result panel with live camera, `EditorRouter` so forms survive fold/unfold, region/cask/status search |
| 4 | `feat(intelligence)` | Foundation Models enhancer behind a no-op fallback, validation and merge rules, tappable wheel with list alternative, Suggest Words, 24 new accuracy fixtures |
| 5 | `feat(design)` | `onAccent` token and button style, motion spec with Reduce Motion variants, zoom transition, haptics, Dynamic Type scaling, contrast tests |
| 3 | `feat(sync)` | `SchemaV2` (`BottlePhoto`, attribution, last tasted, exact price), CloudKit config with local fallback, photo migrator, stock photo download-once, dedupe, sync status in Settings |

## Decisions made for you

- **iPhone only** (`TARGETED_DEVICE_FAMILY = 1`). The Duo is an iPhone, so the two-column layout still applies.
- **Phase order**: sync last, as its own commit.
- **Stock photo attribution** is a source line ("Photo via Wikimedia Commons"), not the full author and license. Getting those needs Commons `extmetadata` in the search request; that's a follow-up before App Store review.
- **Price** is stored twice (`purchasePrice` Decimal and `priceMinorUnits` Int) and read from the integer, because CloudKit mirrors Decimal through a Double. Everything reads `bottle.price`.
- **Bottle title in a serif face** (PRD 8.2: "decide with screenshots"): not done, because no screenshots were possible. Sans stays.

## Not done

- **Icon Composer app icon** (needs the Icon Composer app). The flat PNG trio is still the icon.
- **Xcode Cloud workflow** (configured in Xcode, not in the repo).
- **App Store checklist** (PRD 12): name check, privacy policy URL, UPCitemdb terms, screenshots, TestFlight.
- **F9** App Intents and Spotlight (PRD marks it v2.1), JSON import (v2.x).
- **Real verification of anything camera, Duo or iCloud shaped.**

## On-device checklist

1. Existing v1 store opens, photos appear, and the files in Application Support/Photos are gone afterwards.
2. Instruments Time Profiler during photo apply and live label mode: no ImageIO or parse work on the main thread. `BottleThumbnailView` still reads `bottle.primaryPhoto` (a SwiftData relationship fetch) in `body`; if scrolling 300 bottles hitches, cache the primary photo id on the bottle.
3. Label mode: "Use This Label" is quick, and the live parse doesn't drop camera frames.
4. Cancel during "Looking up…" returns to the camera and does not immediately re-scan the same barcode.
5. Two devices on one Apple ID: add, edit, delete, photos and notes converge within a minute. A barcode added on both while offline merges into one bottle.
6. Duo inner display: split view, two-column detail, scan panel with live camera. Fold mid-form keeps the draft. 50/50 Split View falls back to one column. Fold mid-scan returns to scanning.
7. The model-gated test `ExtractorAccuracyTests.modelNeverRegressesTheHeuristicsAndHelpsOverall` runs only where Apple Intelligence is available. Its printed scorecard is the release gate for the extractor (PRD section 9).
8. Rating control: tap, scrub, and a vertical scroll that starts on the stars.
9. Region colors and the accent in both appearances; Accessibility Inspector pass.
