# Phase 1 plan: Models and seed data

Scope (per PRD section 9, Phase 1):

1. **Project settings**: bump `SWIFT_VERSION` to 6.0 (Swift 6 strict concurrency is a hard rule); add a `UisgeBeathaTests` unit test target + shared scheme so acceptance tests can run via `xcodebuild test`.
2. **Models** (`UisgeBeatha/Models/`), CloudKit-forward per PRD section 5:
   - `Bottle.swift` — `@Model`, all fields optional or defaulted, `notes` optional cascade relationship with explicit inverse, plus `BottleStatus` enum.
   - `TastingNote.swift` — `@Model`, optional `bottle` back-reference.
   - `RegionCatalog.swift` — data-driven definitions of the six Scotland regions (id, display name, country, accent color, centroid, blurb). No region switches anywhere else.
   - `CollectionPolicy.swift` — injectable scotch-only gate: allowed-country set, non-scotch category keywords, rejection copy.
   - `Distillery.swift` — Codable seed-data struct.
3. **Seed data**: `Resources/distilleries.json` (~125 active Scottish malt distilleries; region accuracy prioritized; the ten PRD-listed Islands distilleries marked `islands`).
4. **Services**: `DistilleryStore.swift` — bundled JSON loading, exact / case-insensitive contains / fuzzy (token overlap + Levenshtein) matching.
5. **Support**: `Strings.swift` — single home for user-facing strings (rejection copy, status labels).
6. **App entry**: explicit `ModelContainer` in `UisgeBeathaApp.swift`.
7. **Tests** (`UisgeBeathaTests/`): seed count > 120, all six regions present, spot checks (Lagavulin=islay, Glenfarclas=speyside, Springbank=campbeltown, Talisker=islands), fuzzy match ("LAGAVULIN 16 YEARS" → Lagavulin), region catalog integrity, in-memory ModelContainer schema smoke test.

Verification: `xcodebuild build` warning-free + `xcodebuild test` green on an iOS 26.5 simulator.

Out of scope here: all UI (Phase 2+), scanner, lookup services, ImageStore.

# Phase 2 plan: Collection list + manual entry

Scope (per PRD section 9, Phase 2):

1. **RootTabView** — Liquid Glass TabView with Collection and Settings tabs (Scan joins in Phase 4). Replaces the ContentView placeholder.
2. **Collection list** (`Views/Collection/`) — `@Query`-driven list: rows with region-colored monogram thumbnail (photos arrive in Phase 3), name, distillery, region tag, status pill, rating stars. Toolbar sort menu (name / distillery / region, persisted via `@AppStorage`), search on name + distillery, swipe actions (cycle status, delete with confirmation), empty state on fresh install.
3. **Sort logic** in `CollectionSort.swift` — region ordering reads `RegionCatalog.sortIndex`, unit-testable.
4. **Add/edit form** (`Views/AddEdit/BottleFormView.swift`) — name, distillery with seed-data autocomplete (picking a match auto-fills region), region picker driven by RegionCatalog, ABV, age with NAS toggle, cask type, price, purchase date, status, barcode (locked when it came from a scan). Validation: name + distillery non-empty, region selected. Same form reused for edit.
5. **Components** (`Views/Components/`) — RegionTagView, StatusPillView, RatingStarsView (display-only; the adjustable control is Phase 3), MonogramThumbnail.
6. **Settings** — About only for now (version, data-stays-on-device notice); export arrives in Phase 6.
7. **Tests** — sort comparators and status cycling.

Note: the PRD's empty state names a "Scan your first bottle" button; the scanner is Phase 4, so the button opens manual entry until then (same copy swap happens in Phase 4).

Row tap opens the edit form in Phase 2; Phase 3 replaces this with the bottle detail push.

# Phase 3 plan: Bottle detail, photos, rating, tasting notes, wheel

Scope (per PRD section 9, Phase 3):

1. **ImageStore** (`Support/ImageStore.swift`) — protocol + `LocalImageStore`: JPEGs downsampled to max 2000px long edge (~0.8 quality) in Application Support/Photos, 300px thumbnail generated alongside, filenames only in SwiftData, delete removes both files. ImageIO downsampling.
2. **Bottle detail** (`Views/BottleDetail/`) — hero photo (user photo → stock photo AsyncImage → monogram placeholder) with Take Photo (camera; device only) and Choose Photo (PhotosPicker); facts grid; tappable status; half-star rating control (tap + VoiceOver adjustable); tasting notes newest-first; Edit/Delete in toolbar menu. Row tap in the list now pushes detail instead of opening the edit sheet.
3. **Tasting notes** — editor sheet with Nose/Palate/Finish/Conclusion + editable date; note cards with relative dates; delete.
4. **Tasting wheel** (`Views/Components/TastingWheelView.swift`) — original two-ring SwiftUI Canvas wheel: 8 categories × 3 descriptors, colors legible in both modes; reference-only sheet from the note editor.
5. **Camera capture** — UIImagePickerController wrapper (camera unavailable in simulator; owner verifies on device).
6. **Tests** — ImageStore round-trip/downsample/thumbnail/delete; rating formatting. UI driver extended: detail push, rating tap, note CRUD, photo via simulator photo library.

Acceptance (PRD): photo persists across relaunch; replacing a photo deletes old files; rating adjustable via tap and VoiceOver; two notes display newest first; wheel renders in light and dark. Camera capture itself needs the owner's device.

# Phases 4–6 (built together; see git history for detail)

- **Phase 4** — VisionKit scanner + manual-entry fallback, OFF→UPCitemdb cascade behind tier protocols with 90-day disk cache (definitive outcomes only), scotch gate via CollectionPolicy, result sheet, miss path, duplicate jump, stock photo persistence, Scan tab. DEBUG lookup stub drives ScanFlowUITests.
- **Phase 5** — List | Map toggle (persisted), MapKit Scotland framing, six centroid badges (dimmed at zero), region sheet → detail. MapFlowUITests.
- **Phase 6** — WikipediaService (30-day cache, title fallbacks) + distillery card + SFSafariViewController; JSON/CSV export via ShareLink (photos excluded, noted in UI); original glencairn app icon (light/dark/tinted); dark-mode and accessibility-XL Dynamic Type audits ran the full UI suite green.

Remaining on-device checks for the owner (camera-dependent): Phase 3 photo capture, Phase 4 live barcode scanning acceptance.
