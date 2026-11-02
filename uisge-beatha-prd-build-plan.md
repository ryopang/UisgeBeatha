# Uisge Beatha: Scotch Whisky Collection App
## PRD v2.0 and Build Plan

Version 2.0 · November 2026 · Owner: Ryo
Supersedes v1.0 (July 2026, archived at `docs/archive/uisge-beatha-prd-v1.md`). Audit that drove this revision: `docs/audit-2026-11.md`.

---

## 1. What this is

A personal scotch whisky collection app for iPhone, built to ship on the App Store. Scan a bottle's barcode or label to add it, browse the collection as a list or a Scotland region map, and record ratings, photos and tasting notes. Everything stays on device, with private iCloud sync across the owner's devices.

v1.0 proved the core loop. v2.0 makes it a product:

1. **Great on every iPhone, including the iPhone Duo.** Adaptive layouts that use the Duo's 7.6" inner display properly, and still work on its 5.4" outer display, regular iPhones and 50/50 Split View.
2. **Private sync.** SwiftData + CloudKit private database. "Login" is the person's Apple ID, so there are no accounts to build.
3. **Smarter, still private, identification.** Apple's on-device Foundation Models improve label and lookup parsing. No server, no API keys, no recurring cost.
4. **App Store ready.** Privacy, review, accessibility and performance bars met.

Design assumptions: single user per Apple ID, up to about 500 bottles, no server, no developer-side data collection, zero recurring cost beyond the developer program.

## 2. What changed from v1 (decision log)

| Topic | v1 decision | v2 decision | Why |
|---|---|---|---|
| Signing / distribution | Free Apple ID, 7-day re-sign | **Paid developer program (already held). TestFlight, then App Store.** | Owner already has a paid account and a published app. |
| Storage | SwiftData, local only | **SwiftData + CloudKit private database** | The schema was built CloudKit-compatible in v1 for exactly this. |
| Photos | Files on disk via `LocalImageStore` | **Synced `BottlePhoto` model with external storage, behind the same `ImageStore` protocol** | Files on disk don't sync. |
| Stock photos | Remote URL hotlinked on every view | **Downloaded once, stored like a user photo, source URL kept for attribution** | Offline, link rot, privacy, sync. |
| Devices | iPhone only, single column | **iPhone + iPhone Duo, size-class adaptive. iPad comes nearly free but isn't a launch target.** | Duo launched October 2026. |
| Identification | Heuristic parser + free APIs | **Same, plus on-device Foundation Models as an enhancer, gated by measured accuracy** | Owner chose on-device AI only, no paid cloud. |
| UPCitemdb trial tier | Kept | **Keep only if its terms allow production use. Otherwise remove.** | It's an evaluation endpoint. |
| Toolchain | Xcode 26, iOS 26 SDK | **Xcode 27, iOS 27 SDK. Minimum iOS stays 26.0.** | The iOS 27 SDK is required for full-screen Duo. Everything v2 needs exists on iOS 26. |
| Design doc | `DESIGN.md` (Apple marketing web spec) | **§8 of this PRD is the design system.** `DESIGN.md` gets replaced or deleted. | The web spec contradicts the app (blue vs amber, px vs Dynamic Type). |
| Stats dashboard | v1.1 roadmap | Still roadmap (§13), after release | Keep v2 focused. |

## 3. Locked decisions (do not revisit during the v2 build)

| Decision | Choice |
|---|---|
| Platform | Swift 6 language mode, SwiftUI, SwiftData, Xcode 27 / iOS 27 SDK, **minimum iOS 26.0** |
| Default isolation | `MainActor` stays the project default. Heavy work is explicitly `nonisolated` or in an actor. |
| Dependencies | Zero third-party packages |
| Backend | None. CloudKit private DB is the only remote store and is Apple-operated. |
| Sync | `ModelConfiguration(cloudKitDatabase: .private("iCloud.com.ryo.UisgeBeatha"))` |
| AI | Apple Foundation Models, **on-device system model only**. iOS 27 lets the framework call cloud providers too; that's explicitly out of scope. |
| Scope | Scotch only (the `CollectionPolicy` gate stays) |
| Language | English only. Every string stays in `Strings.swift`. Always "Whisky", never "Whiskey". |
| Regions | The six: Highland, Lowland, Islay, Speyside, Islands, Campbeltown, data-driven via `RegionCatalog` |
| Accessibility | WCAG AA contrast, 44pt targets, full Dynamic Type including accessibility sizes, VoiceOver, Reduce Motion |

## 4. Target devices and layout contract

| Context | Size class (w × h) | Layout |
|---|---|---|
| iPhone portrait (all sizes), Duo outer 5.4" | compact × regular | Single column, tab bar, push navigation. Today's design, tightened. |
| iPhone landscape | compact × compact (regular width on Pro Max/Plus) | Single column; Pro Max landscape may show the split. Don't special-case device models. |
| **Duo inner 7.6"** | **regular × regular** | **Two-column split** (§7) |
| Duo inner, 50/50 Split View | likely compact width (Apple hasn't published this; test it) | Must fall back to single column cleanly |
| iPad (bonus) | regular × regular | Same as the Duo inner display |

Rules:

1. Branch only on `horizontalSizeClass`, never on orientation, screen size or device model. Apple's Duo guidance says the inner display doesn't honor orientation like a normal iPhone.
2. **Keep view identity stable across size-class changes.** Folding or unfolding mid-task must not discard a sheet, a half-filled form or a scan. Prefer `NavigationSplitView`, which collapses itself, over `if sizeClass == .regular { A } else { B }` around stateful views.
3. Persist selection and view mode in `@SceneStorage`, so fold and unfold (and app relaunch) restore where the person was.
4. No fixed widths or breakpoints. Size to content and let `ViewThatFits`, `Grid` and the split view do the work.

## 5. Architecture

```
UisgeBeatha/
├── App/            UisgeBeathaApp, AppContainer (ModelContainer + recovery), scene storage keys
├── Models/
│   ├── Schema/     SchemaV1, SchemaV2 (VersionedSchema), MigrationPlan
│   ├── Bottle, TastingNote, BottlePhoto (v2)
│   ├── RegionCatalog, CollectionPolicy, Distillery, Expression
├── Flows/          @Observable flow models: ScanFlow, BottleDraft, CollectionSelection
├── Services/
│   ├── Lookup/     BarcodeLookup cascade + tiers
│   ├── Recognition/ VisionLabelOCRService, LabelParser (nonisolated), BottleExtractor (Foundation Models)
│   ├── Media/      ImageStore protocol, SyncedImageStore (v2), LocalImageStore (migration source), StockPhotoImporter
│   ├── Knowledge/  DistilleryStore, ExpressionStore, WikipediaService
│   ├── Sync/       CloudSyncMonitor (account status, dedupe on remote change)
│   └── Export/     ExportService (+ JSON import, v2.x)
├── Support/        AppNetwork, Barcode, DiskCache, Strings, Theme
└── Views/          Collection, Map, Detail, Scan, Form, Settings, Components
```

Patterns:

- **Views stay thin.** Anything with branching flow or async work lives in an `@Observable` flow model that's unit-testable without UI. `ScanView` and `BottleFormView` are the first two to split.
- **Protocol-first services**, injected through `@Entry` environment values, with DEBUG stubs selected by launch argument (as in v1).
- **Concurrency:** UI and SwiftData on `MainActor`. ImageIO, Vision, parsing and Foundation Models calls are `nonisolated async` or actor-isolated. Pass value types (or `PersistentIdentifier`) across boundaries, never `@Model` instances.
- **Networking:** everything goes through `AppNetwork.session` (12s/30s timeouts, one User-Agent). Every tier distinguishes "definitive miss" from "transport error" and only caches the former.
- **Error surfaces:** quiet inline states, and an alert only for destructive or unrecoverable situations (unchanged from v1).

## 6. Data model v2

### 6.1 Versioning (must ship before any model change)

- `SchemaV1`: today's `Bottle` + `TastingNote`, unchanged. Shipped first as a no-op, so existing stores get a version stamp.
- `SchemaV2`: adds `BottlePhoto` and the new optional fields below. A lightweight migration (new optional attributes and a new entity) plus a custom post-migration step that moves files from `LocalImageStore` into `BottlePhoto` rows and then deletes the files.
- Container creation failure shows a recovery screen (export what's readable, then reset), never `fatalError`.

### 6.2 CloudKit rules (carried from v1, still non-negotiable)

No `@Attribute(.unique)`. Every attribute optional or defaulted. All relationships optional with explicit inverses. No deny delete rules. Duplicate detection is a fetch, plus a post-sync dedupe (§10).

### 6.3 Changes

**Bottle** (existing fields unchanged unless noted)

| Field | Type | Change |
|---|---|---|
| barcode | String? | Stored canonical via `Barcode.normalized` (EAN-13 for UPC-A). Already done in this pass. |
| purchasePrice | Decimal? | Verify CloudKit mirroring. If it's lossy, migrate to `priceMinorUnits: Int?`. |
| stockPhotoURL | String? | Now attribution only (source page/URL), not loaded for display |
| stockPhotoAttribution | String? | **New.** Author/license line for Commons images |
| userPhotoFilename | String? | **Deprecated in V2.** Kept for migration, then unused. |
| photos | [BottlePhoto]? | **New.** Relationship, cascade delete |
| lastTastedDate | Date? | **New, optional.** Denormalized from notes for sort and search |

**BottlePhoto** (new)

| Field | Type | Notes |
|---|---|---|
| id | UUID | |
| kind | String | `user` or `stock` (string for CloudKit friendliness) |
| imageData | Data? | `@Attribute(.externalStorage)`, downsampled JPEG/HEIC, long edge 2000px |
| thumbnailData | Data? | `@Attribute(.externalStorage)`, 300px |
| dateAdded | Date | |
| bottle | Bottle? | Inverse of `Bottle.photos` |

The primary photo is the newest `user` photo, else the newest `stock` photo. One photo per kind in v2; the model allows a gallery later.

**TastingNote:** unchanged. **Distillery / Expression seed data:** unchanged, bundled JSON.

## 7. Features

v1 features F1 to F8 stay as specified in the v1 PRD unless changed here.

### F1 (revised): Scan and identify

- Barcode lookup cascade unchanged: cache, then Open Food Facts, then UPCitemdb (subject to the terms check in §11), then the miss path. Input is always `Barcode.normalized`.
- Live label scanning: the parse is throttled to about 4 Hz and runs off the main actor. The accepted frame is re-read with the tuned Vision recognizer (as in v1).
- **New: Foundation Models enhancer** (§9). It runs after the heuristic parser, on both label OCR lines and barcode-lookup text (title + description). It may fill or correct fields only within the confidence rules in §9.
- **New: cancel during lookup.** "Looking up…" gets a Cancel button. With 12s timeouts the worst case is about 25 seconds, which still deserves an exit.
- **Duo inner display:** the scanner fills the leading area, and the result (lookup or label confirmation) appears in a trailing panel instead of a sheet, so the camera stays live for the next bottle. The compact layout keeps sheets.

### F3/F4 (revised): Collection, list and map

- **Compact:** today's behavior (List | Map toggle, push to detail).
- **Regular (Duo inner):** `NavigationSplitView` with selection bound to `PersistentIdentifier`.
  - **List mode:** sidebar = searchable, sortable list; detail = selected bottle, or a "Select a bottle" empty state with a scan shortcut.
  - **Map mode:** sidebar = bottles in the selected region (all regions when none is selected, with a region filter chip); detail = the map. Choosing a bottle pushes its detail inside the detail column, with Back returning to the map.
  - Deleting the selected bottle clears the selection instead of calling `dismiss()`.
- Search gains tokens for region, status and cask type.
- The map's zero-count badges use a contrast-safe token. Badges are already AA in this pass.

### F5 (revised): Bottle detail

- **Compact:** today's vertical layout.
- **Regular:** two columns inside the detail pane. Hero photo plus facts on the leading side; rating, distillery card and tasting notes on the trailing side. Collapses to one column below about 600pt of available width (via `ViewThatFits`, not a breakpoint constant).
- The hero photo uses `scaledToFit` on a neutral backdrop. Bottles are tall, and `scaledToFill` in a wide pane crops them.
- Photo actions (Take, Choose, Find stock photo, Remove) move into a single menu on the hero in both layouts. This frees vertical space and fixes the crowded button row.
- **Matched-geometry transition** from the list thumbnail to the hero (disabled under Reduce Motion).

### F7 (revised): Tasting notes and wheel

- Wheel descriptors become tappable. A tap inserts the descriptor into the focused note field. Label text scales with Dynamic Type, and an accessible list alternative sits behind a toggle.
- **New: "Suggest words" (Foundation Models).** Takes what the person has typed and suggests descriptors from the wheel vocabulary (constrained output). Suggestions only, never auto-inserted.

### F8 (revised): Settings

- iCloud sync status (on, off, account unavailable) with a plain-language explanation.
- Export (JSON / CSV). **New in v2.x: JSON import**, which matches the exports v1 already writes.
- Privacy section: what leaves the device (barcodes and search terms to Open Food Facts, UPCitemdb and Wikimedia), and that iCloud data is private to the person.
- The debug section is DEBUG-only (done).

### F9 (new): System integration (v2.1)

- **App Intents:** "Add a bottle", "Log a tasting", "Show my Islay bottles". These surface in Siri, Spotlight and Shortcuts.
- **Spotlight:** index bottles as `IndexedEntity` so a search for "Lagavulin" finds the bottle.
- Skipped: widgets and Live Activities (no recurring-glance use case yet).

## 8. Design system (replaces DESIGN.md)

**Direction:** "warm, quiet, tactile". Liquid Glass system chrome, content-first, one warm accent. It should feel like a well-made leather notebook, not a dashboard. Reference feel: Apple's Journal and Books apps.

### 8.1 Color tokens

| Token | Light | Dark | Use |
|---|---|---|---|
| `accent` | `#A75A17` (5.1:1 on white) | `#DE8230` | Tint, stars, status text, prominent buttons |
| `onAccent` (prominent button text) | white | **near-black `#1A1206`** (white on `#DE8230` is only 2.9:1) | Text on accent fills |
| Region `textColor` | base × 0.6 | base + 25% toward white | Region-colored text/glyphs. AA verified in the audit. |
| Region tint | base at 16 to 18% | same | Tag/monogram backgrounds |
| Region `badgeFillColor` | base × 0.6 | base × 0.6 | Solid fills behind white text |
| Surfaces | system `.background`, `.secondary` | system | No custom grays |

Rules: never put gray text on a colored fill. Region colors are for tags, badges and monograms only, never for large surfaces. No gradients.

### 8.2 Typography

System font only, text styles only (`.largeTitle` through `.caption2`), no fixed point sizes outside the tasting wheel and monograms (which scale with `@ScaledMetric`). Weight ladder: regular, semibold, bold (`.medium` unused, as in v1). Bottle names may use `.serif` design in the detail title only, if it tests well. Decide in Phase 5 with screenshots, not by default.

### 8.3 Shape, spacing, elevation

- Radii: inline 12, card 16, hero 24 (v1 `Theme.Radius`). Use `ConcentricRectangle` / container-relative shapes where iOS 26 provides them.
- Spacing scale: 4, 8, 12, 16, 24, 32. Section spacing 24.
- **No cards inside cards.** One shadow in the whole app (the hero photo).
- 44pt minimum hit target everywhere, including icon-only menus.

### 8.4 Motion

Principles (Emil Kowalski's design-engineering guidance, applied to SwiftUI):

- Motion explains a change; it doesn't decorate. If it doesn't help the person understand what happened, cut it.
- Fast: 150 to 250ms for most transitions, springs with no visible overshoot (`.snappy`, `.smooth`). Never block input during an animation. Everything is interruptible.
- No animation for keyboard-driven or very frequent actions.
- Under Reduce Motion, replace movement with cross-fades. Never just remove the feedback.

Concrete motion spec:

| Moment | Treatment |
|---|---|
| List thumbnail to detail hero | `matchedTransitionSource` / `.navigationTransition(.zoom)` |
| Status cycle | `contentTransition(.numericText)`-style text swap plus a `symbolEffect(.bounce)` on the status glyph, selection haptic |
| Rating change | Selection haptic (done), star `symbolEffect` on set |
| Bottle added | Success haptic, toast slides from the top (existing pattern) |
| Scan hit | Success haptic. The result panel/sheet appears with the default spring. |
| Map badge tap | Scale 0.96 press state, sheet/panel presents |

### 8.5 Anti-patterns (from pbakaus/impeccable, adapted)

No purple or blue gradients, no icon tile above every heading, no nested cards, no gray-on-color text, no cramped padding, no skipped heading levels (use proper `accessibilityHeading` on section titles), no generic "AI app" copy. Write copy the way a whisky shop owner would talk.

### 8.6 App icon

Rebuild the icon in **Icon Composer** as a layered `.icon` so it renders correctly in Liquid Glass light, dark, tinted and clear modes. The current flat PNG trio is a fallback only.

## 9. On-device intelligence (Foundation Models)

**Goal:** better field extraction from messy label OCR and terse barcode listings, at zero cost and with nothing leaving the device.

**Availability:** `SystemLanguageModel.default.availability`. Only Apple Intelligence-capable iPhones, which includes every Duo. When it isn't available, the app behaves exactly like today. Never require it.

**BottleExtractor:**

```swift
@Generable struct BottleFields {
    @Guide(description: "Distillery name exactly as printed, or nil") var distillery: String?
    @Guide(description: "Expression name without distillery or age, e.g. 'Double Cask'") var expression: String?
    @Guide(description: "Age statement in years if printed", .range(3...60)) var ageYears: Int?
    @Guide(description: "ABV percent if printed", .range(35...75)) var abvPercent: Double?
    @Guide(description: "Cask or finish if printed") var cask: String?
    @Guide(description: "true only if the text says Scotch or Scotland") var saysScotch: Bool?
}
```

- Instructions: extract only what is printed, never infer from general knowledge, return nil when unsure.
- Input: OCR lines (or lookup title + description). Output goes through **deterministic validation**: distillery must resolve via `DistilleryStore` (else ignored or offered as an alternate), and age/ABV must pass the existing `WhiskyLabelParser` range checks.
- **Merge rule:** heuristic `confident` fields win. The model may fill `none` fields and break ties between `guessed` alternates. A model-filled field shows as `guessed` in the confirmation UI.
- **Release gate:** run the existing real-photo accuracy corpus (`RealPhotoAccuracyTests`, about 96% today) with and without the extractor. Ship it only if accuracy improves and nothing regresses. Add 20+ new fixtures from real bottles, including tricky independents.
- Latency budget: under 1.5s after the person taps "Use This Label". Prewarm the session when label mode opens.

Other uses, in priority order: tasting-word suggestions (F7), the scotch gate when category tags are empty (classification, never a hard reject on its own), and natural-language collection search ("peated under $100", v2.x).

## 10. Sync (CloudKit)

- Capabilities: iCloud (CloudKit) with container `iCloud.com.ryo.UisgeBeatha`, plus Background Modes, remote notifications.
- Development: run once with `initializeCloudKitSchema` (or let SwiftData create the schema). **Deploy the schema to Production in the CloudKit Console before every TestFlight/App Store build that changes models.** This is the most common shipped-sync failure.
- Account states: signed out, restricted, temporarily unavailable. The app keeps working locally and Settings explains the state.
- **Dedupe:** on `NSPersistentStoreRemoteChange`, find bottles sharing a canonical barcode and merge them (keep the oldest, move notes and photos, delete the rest). Unit-test the merge function as pure logic.
- Photos sync through `BottlePhoto` external storage. Test the first sync of a large library over cellular.
- Export/import remains the escape hatch, independent of iCloud.

## 11. Non-functional requirements

**Performance (measured with Instruments on the owner's device)**
- Cold launch to interactive list in under 1.0s with 300 bottles.
- 120Hz list scrolling with 300 bottles and thumbnails. No main-thread disk or ImageIO work in `body`.
- Applying a 12MP photo causes no main-thread hitch over 50ms (ImageStore off main).
- Live label mode holds 60fps camera preview while parsing (throttled, off main).

**Accessibility**
- WCAG AA contrast for all text, 3:1 for non-text UI. Verified with the Accessibility Inspector in both appearances.
- Full Dynamic Type, including AX5, on every screen in both size classes.
- VoiceOver labels, rotor-friendly headings, adjustable rating. Reduce Motion and Reduce Transparency respected.
- 44pt targets.

**Privacy and security**
- No tracking, no analytics SDKs, no developer-side collection. Privacy manifest present (done).
- Only canonical barcodes and search strings go to third parties. No identifiers.
- No secrets in the binary (none needed).

**Quality**
- Strict concurrency, warning-free, no force unwraps outside tests.
- Unit tests for every flow model and pure function. UI tests for the key flows in both compact and regular width (iPhone 17 Pro simulator plus an iPhone Duo or iPad simulator).
- CI: an Xcode Cloud workflow on every PR (build + unit tests) and nightly UI tests.

## 12. App Store readiness checklist

- [ ] Name check: "Uisge Beatha" availability in App Store Connect
- [ ] Privacy policy URL (a GitHub Pages page is fine): what goes to OFF/UPCitemdb/Wikimedia, iCloud private storage, no collection
- [ ] App Privacy label: Data Not Collected
- [ ] Age rating questionnaire: alcohol references. Expect a high rating under Apple's current age-rating tiers. Metadata must not encourage consumption.
- [ ] UPCitemdb: confirm the trial endpoint's terms permit production use. Otherwise remove the tier before release.
- [ ] Wikimedia Commons attribution displayed for Commons-sourced photos
- [ ] Screenshots: 6.9" iPhone plus the iPhone Duo sizes App Store Connect requires (and iPad if `TARGETED_DEVICE_FAMILY` keeps iPad)
- [ ] Icon Composer icon
- [ ] Support URL
- [ ] TestFlight beta with 10 to 50 testers, including at least 2 Duo owners
- [ ] CloudKit schema deployed to Production

## 13. Build plan

Execute in order. Each phase ends with its acceptance criteria met, a green CI run, and an on-device check where noted.

### Phase 0: Toolchain and verification of the audit fixes (half a day)

- Open in Xcode 27, set the iOS 27 SDK (deployment target stays 26.0), bump to 2.0 (build 1).
- Build warning-free. **The audit fixes were written without a compiler**, so fix anything that doesn't compile first.
- Run unit and UI tests.
- Add an Xcode Cloud workflow.
- Decide on `DESIGN.md` (replace with §8 or delete).
- **Acceptance:** green build and tests. The on-device checklist in the audit (§"Must verify on a physical device") passes.

### Phase 1: Foundations (2 to 3 days)

- `SchemaV1` + `MigrationPlan` (no shape change) and the container recovery screen.
- `ImageStore` becomes `nonisolated async`. Thumbnail `NSCache` with async row loading.
- Live label parse: throttle plus off-main. `LabelParser`, `DistilleryStore` and `ExpressionStore` become `nonisolated`.
- Extract the `ScanFlow` and `BottleDraft` flow models, with tests.
- Cancel during lookup.
- **Acceptance:** an existing v1 store opens. The Instruments main-thread trace shows no ImageIO or parse work during photo apply and live label mode. Flow model tests pass.

### Phase 2: Adaptive layout for iPhone + Duo (3 to 4 days)

- `NavigationSplitView` collection (list mode and map mode) with `@SceneStorage` selection.
- Two-column detail in regular width. Hero `scaledToFit`. Photo actions menu.
- Scan with a trailing result panel in regular width.
- Fold/unfold continuity: no lost sheets, forms or scans.
- **Acceptance:** every screen verified on an iPhone 17 Pro sim, an iPhone Duo sim (both displays), 50/50 Split View, and the iPad sim; in both appearances; at default and AX5 type sizes. Fold mid-form keeps the draft. Fold mid-scan returns to scanning. On-device Duo check if available.

### Phase 3: Sync and photos (3 to 4 days)

- iCloud capability, CloudKit container, `SchemaV2` with `BottlePhoto`, file-to-model migrator.
- `StockPhotoImporter` (download once, attribution) replacing hotlinks. Migrate existing `stockPhotoURL` bottles on first launch, best effort.
- Sync status in Settings, dedupe on remote change, updated privacy copy.
- **Acceptance:** two devices on one Apple ID converge (add, edit, delete, photos, notes) within a minute online. Offline edits merge. A duplicate barcode added on both devices merges to one bottle. Migration from a v1 store with photos is lossless.

### Phase 4: On-device intelligence (2 to 3 days)

- `BottleExtractor` with validation and the merge rule. Prewarm.
- Accuracy harness comparing heuristic vs heuristic + model on the corpus. Add 20+ fixtures.
- Tasting "Suggest words" and the tappable wheel.
- **Acceptance:** corpus accuracy improves with zero regressions on existing fixtures. p95 extraction latency under 1.5s on the owner's iPhone. With the model unavailable, behavior is identical to Phase 3.

### Phase 5: Design polish and motion (2 days)

- Apply §8 tokens (`onAccent` in dark mode, map zero-count token, heading traits).
- Motion spec, haptics, Reduce Motion variants.
- Icon Composer icon.
- Copy pass, empty states. Search tokens.
- **Acceptance:** design review against §8 with screenshots of every screen in both size classes and appearances. Accessibility Inspector audit clean.

### Phase 6: Release (1 to 2 days plus review time)

- Everything in §12. TestFlight beta for 2 weeks, fix findings, submit.
- **Acceptance:** approved build live on the App Store.

### Roadmap after 2.0 (not commitments)

- 2.1: App Intents + Spotlight (F9), JSON import, collection insights (count by region, spend, average rating, open/sealed). Computed from existing fields, zero schema change.
- 2.5: world whisky (extend `RegionCatalog` and seed data, country-scoped map, flip `CollectionPolicy`). v1's data-driven design keeps this a data change.
- Parked: wishlist, bottle sharing (CloudKit shared zones), Apple Watch.

## 14. Risks and open questions

| Risk | Mitigation |
|---|---|
| Audit fixes don't compile (written without Xcode) | Phase 0 exists for this. The changes are small and isolated. |
| Duo 50/50 Split View size class undocumented | Size-class-driven layout handles either answer. Test it explicitly. |
| CloudKit schema not deployed to Production | Checklist item. Add it to the release runbook. |
| UPCitemdb terms disallow production use | Remove the tier. OFF + label OCR + Foundation Models cover most bottles. |
| RESTBase `page/summary` deprecation | Wrapped behind `WikipediaServicing`. Swap to the Action API if it changes. |
| Foundation Models adds latency or hallucinated fields | Validation layer, merge rule, accuracy gate, never required. |
| Owner time | Phases are independent after Phase 1. Phase 2 (Duo) can ship before sync if needed. |

**Open questions for the owner**

1. Keep iPad in the build (nearly free after Phase 2, but needs iPad screenshots and review), or set the device family to iPhone only for 2.0?
2. Is the App Store name "Uisge Beatha" available? If not, what's the fallback name?
3. Price: free, paid up front, or free with a one-time unlock? This affects nothing in the architecture. Decide before Phase 6.

## 15. Instructions block for Claude Code

See `claude.md` at the repo root (updated for v2).
