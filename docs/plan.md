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
