# Uisge Beatha

*uisge beatha* (Scottish Gaelic, "water of life") — a personal scotch whisky collection app for iPhone.

Scan a bottle's barcode or enter it by hand, and Uisge Beatha keeps your collection organised by Scotland's six whisky regions: what you own, what's open, how you rated it, and what you tasted in it. Everything lives on-device. Scotch only — the app politely turns away bourbon.

## Features

- **Barcode scanning** — point the camera at a bottle (EAN-13/EAN-8 via VisionKit). Lookups cascade through Open Food Facts, then UPCitemdb, with a 90-day on-disk cache so a rescan never hits the network. No camera? A manual barcode entry field takes over.
- **Label OCR fallback** — when a barcode comes back with no match, a "Scan the Label" button reads the bottle's own label via on-device text recognition (Vision) to guess the distillery, region, name, age, and ABV — the same best-effort text parsing the barcode path uses, just sourced from a photo instead of a database. Also offered proactively: a low-key "No barcode? Scan the label instead" button sits on the live scanner itself, so a damaged or missing barcode doesn't require sitting through a doomed scan first. Always a fill-in-and-confirm assist; the form stays fully editable.
- **Scotch gate** — looked-up products that are clearly not scotch (bourbon, rye, Irish whiskey…) are rejected with a friendly message and never enter the collection. Ambiguous results pass through to manual confirmation rather than being rejected.
- **Collection list** — searchable, sortable (name / distillery / region), with region-coloured thumbnails, status pills (Sealed → Open → Finished, cycled by swipe or tap), and half-star ratings.
- **Region map** — a MapKit view of Scotland with a badge at each region's centroid showing your bottle count there; tap a badge to browse that region's bottles.
- **Bottle detail** — hero photo (your camera shot, a stock photo from the lookup, or a monogram placeholder), facts grid, tappable status, and a half-star rating control that also works via VoiceOver adjustment.
- **Tasting notes** — dated Nose / Palate / Finish / Conclusion entries, newest first, with an original SwiftUI-drawn flavour wheel (8 categories × 24 descriptors) on hand while you write.
- **Distillery knowledge** — 126 bundled Scottish distilleries with region, coordinates, founding year, and owner; fuzzy name matching powers form autocomplete, and the detail screen enriches the card with a Wikipedia summary (30-day cache) and a Read-more link.
- **Duplicate detection** — scanning a barcode you already own jumps straight to that bottle instead of adding a twin.
- **Export** — the whole collection as JSON or CSV via the share sheet (photos excluded by design).
- **Fully accessible** — every screen works in light and dark mode and at accessibility Dynamic Type sizes; controls carry proper accessibility labels and actions.

## Architecture

**Swift 6 · SwiftUI · SwiftData · iOS 26+ · zero third-party dependencies.**

- **CloudKit-forward schema** — the SwiftData models (`Bottle`, `TastingNote`) use no unique constraints, only optional or defaulted attributes, and optional relationships with explicit inverses. Duplicate detection is a fetch, never a constraint. v1 is local-only, but the schema can adopt CloudKit sync without migration.
- **Data-driven regions** — the six regions (Highland, Lowland, Islay, Speyside, Islands, Campbeltown) are defined once in `RegionCatalog` (name, colour, map centroid, blurb). Nothing in the app switches over region cases; adding a region is a data change.
- **Policy as a value** — the scotch-only rule lives entirely in `CollectionPolicy`, an injectable value type. The rest of the app asks the policy; it never hard-codes the rule.
- **Protocol-first services**, injected through the SwiftUI environment (`@Entry`):
  - `BarcodeLookupServicing` — `CascadeBarcodeLookupService` walks an ordered list of `BarcodeLookupTier`s (Open Food Facts → UPCitemdb); adding a third source is one new conformance. Only definitive outcomes (hit or authoritative miss) are cached; transport errors are retried next time.
  - `WikipediaServicing` — REST summary endpoint with title-candidate fallback and a 30-day cache.
  - `ImageStore` — all photo I/O goes through this protocol. `LocalImageStore` downsamples JPEGs to 2000 px via ImageIO, always writes a 300 px thumbnail, and stores only filenames in SwiftData.
  - `LabelOCRServicing` — `VisionLabelOCRService` runs on-device text recognition on a label photo; the recognition pass runs `nonisolated` so it can't block the main actor the way a naive implementation would.
  - DEBUG stub implementations are swapped in by a launch argument so UI tests run deterministic and offline.
- **`DiskCache<Value>`** — a small generic actor for JSON-file caching with per-cache expiry, shared by the lookup and Wikipedia services.
- **One strings file** — every user-facing string lives in `Strings.swift` (always "Whisky", never "Whiskey").
- **Strict concurrency** — Swift 6 language mode, `MainActor` default isolation, warning-free build; no force unwraps outside tests.

```
UisgeBeatha/
├── Models/        Bottle, TastingNote, RegionCatalog, CollectionPolicy, Distillery
├── Services/      BarcodeLookupService, LabelOCRService, WikipediaService, DistilleryStore, ExportService
├── Support/       ImageStore, DiskCache, Strings, environment keys
├── Views/
│   ├── Collection/    list, sort, region map
│   ├── AddEdit/       bottle form with distillery autocomplete
│   ├── BottleDetail/  detail, notes, distillery card
│   ├── Scan/          scanner, lookup result sheet
│   ├── Settings/      export, about, debug
│   └── Components/    tasting wheel, rating control, pills, thumbnails
└── Resources/     distilleries.json (126 distilleries, region-tagged)
```

## Current release — v1.0

All six planned build phases are complete and merged to `main`:

| Phase | Delivered |
|---|---|
| 1 | SwiftData models, region catalog, distillery seed data + matching |
| 2 | Collection list, manual entry form, tab shell |
| 3 | Bottle detail, photos, rating, tasting notes, flavour wheel |
| 4 | Barcode scanner, lookup cascade, scotch gate, duplicate handling |
| 5 | Region map with centroid badges |
| 6 | Wikipedia card, JSON/CSV export, original app icon, accessibility audits |

Verified with 67 unit tests (Swift Testing) across 10 suites plus 5 end-to-end XCUITest flows, run green on fresh installs in light mode, dark mode, and at accessibility-XL Dynamic Type. Camera-dependent acceptance (live photo capture, real barcode scanning, and label OCR) requires a physical device.

Planned but deliberately out of v1: CloudKit sync, a stats dashboard, and world whisky — the schema, region catalog, and policy design above exist to keep those cheap.

### Since v1.0

Device testing surfaced scan-flow bugs the simulator can't reproduce (it has no camera). Fixed so far:

- **Scanner not resuming** — the scanner used to stay mounted (merely "paused") underneath every sheet. It now fully unmounts whenever a sheet is open and remounts fresh when it closes, which also fixed a UI freeze caused by a camera session lingering resident during form edits.
- **ABV / age not always populated from a scan** — neither lookup tier reliably returns them as structured data (UPCitemdb never returns ABV; neither returns age at all), so `WhiskyLabelParser` now backstops both by parsing whatever text a source provides — title, and UPCitemdb's longer description — recognizing "16 Year Old" style age statements and both `%` and "Proof" ABV formats.
- **Map badges** — redesigned for legibility (bold count circle + separate label pill) and the base map simplified (no points of interest, traffic, or 3D buildings).

One iteration briefly regressed live camera scanning (a custom container view controller sized the camera preview to zero at layout time); that was reverted in favor of the simpler approach that was proven working on-device. Real-camera behavior remains the one thing that can only be confirmed on a physical device, not in CI or the simulator.

Added since v1.0: the label OCR fallback described above, for when a barcode lookup comes back empty.

## Building

Requires Xcode 26 and an iOS 26 simulator or device. No package resolution — there are no dependencies.

```bash
# Build
xcodebuild -project UisgeBeatha.xcodeproj -scheme UisgeBeatha \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Unit tests
xcodebuild -project UisgeBeatha.xcodeproj -scheme UisgeBeatha \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# UI test drivers (uninstall first for the fresh-install flow)
xcrun simctl uninstall "iPhone 17 Pro" com.ryo.UisgeBeatha
xcodebuild -project UisgeBeatha.xcodeproj -scheme UisgeBeathaUITests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

The product requirements document and phase plan live in [`uisge-beatha-prd-build-plan.md`](uisge-beatha-prd-build-plan.md).

---

A personal project. Slàinte mhath. 🥃
