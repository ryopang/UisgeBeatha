# Uisge Beatha: Scotch Whisky Collection App
## PRD and Build Plan for Claude Code

Version 1.0 | July 2026 | Owner: Ryo

---

## 1. What this is

A personal iOS app to track a scotch whisky collection. Scan a bottle's barcode to look it up and add it to the library, browse the collection as a sortable list or a Scotland region map, and record tasting notes with photos and ratings per bottle.

This is a beta for personal use. Design assumptions: single user per device, under 100 bottles, no server, no accounts, zero recurring cost.

## 2. Locked decisions (do not revisit during build)

| Decision | Choice | Why |
|---|---|---|
| Storage | SwiftData, local only, on device | Free Apple ID, no CloudKit entitlement available |
| Signing | Free Apple ID personal team | Builds expire every 7 days; owner re-runs from Xcode weekly. Data survives re-signing |
| Barcode lookup | Two-tier cascade: Open Food Facts, then UPCitemdb trial endpoint (both free, no key needed) | Best available free coverage. Misses still route to manual entry |
| Lookup miss | Manual entry form, pre-filled with the scanned barcode | Chosen over paid AI lookup |
| Reviews, US pricing, distillery news | Cut from v1 | No free API exists |
| Distillery info | Wikipedia REST API summary + link out to full article | Free, reliable, covers every Scottish distillery |
| Scope | Scotch only. Non-scotch scans are politely rejected | Owner decision |
| Target | iPhone only, iOS 26, Xcode 26, Swift 6, SwiftUI | Latest design language (Liquid Glass) |
| Dependencies | Zero third-party packages | VisionKit, MapKit, SwiftData, SwiftUI cover everything |
| Sync, wishlist, stats dashboard | Out of scope for v1 | Keep it lean |

## 3. Terminology rules (enforce in all UI strings)

- Always "Whisky". Never "Whiskey".
- Avoid plural forms entirely. Use "Collection", "Bottles", or "My Whisky" instead of "Whiskies".
- English only. No localization scaffolding needed.
- Regions, exactly these six: Highland, Lowland, Islay, Speyside, Islands, Campbeltown. (Note the correct spelling of Campbeltown. "Islands" is not an official SWA region but is a widely used sixth category; we use it.)

## 4. Architecture

```
UisgeBeatha/
├── UisgeBeathaApp.swift                 App entry, ModelContainer setup
├── Models/
│   ├── Bottle.swift              @Model
│   ├── TastingNote.swift         @Model
│   ├── RegionCatalog.swift       Data-driven region definitions (see section 10)
│   ├── CollectionPolicy.swift    The scotch-only gate, one injectable object
│   └── Distillery.swift          Codable struct (seed data, not SwiftData)
├── Services/
│   ├── DistilleryStore.swift     Loads bundled distilleries.json, name matching
│   ├── BarcodeLookupService.swift  Lookup cascade: OFF then UPCitemdb, with disk cache
│   ├── WikipediaService.swift    Distillery summary client
│   └── ExportService.swift       JSON + CSV export
├── Views/
│   ├── RootTabView.swift
│   ├── Collection/               List view, Map view, toggle
│   ├── Scan/                     Scanner + lookup result sheet
│   ├── BottleDetail/             Detail, photo, tasting notes, wheel
│   ├── AddEdit/                  Manual entry form
│   └── Components/               TastingWheelView, RatingControl, etc.
├── Resources/
│   └── distilleries.json         Bundled seed data
└── Support/
    └── ImageStore.swift          Photo persistence helpers
```

Pattern: plain SwiftUI with @Observable view models where a view needs async work or non-trivial state. No MVVM ceremony for simple views. SwiftData @Query drives the collection views directly.

Swift 6 strict concurrency on. Services are actors or @MainActor-isolated as appropriate.

## 5. Data model

### Region and RegionCatalog
Bottle.region is stored as a String region ID (e.g. "islay"). Region definitions live in RegionCatalog, bundled data in the same spirit as distilleries.json: id, displayName, country, accent color, map centroid (lat/lon), one-line blurb. v1 ships exactly Scotland's six: highland, lowland, islay, speyside, islands, campbeltown.

Hard rule: every picker, tag, map badge, and sort comparator renders from the catalog. No view, view model, or service switches over hardcoded region cases. This single discipline is what makes the world whisky expansion in section 10 a data change instead of a rewrite.

### Bottle (@Model)
| Field | Type | Notes |
|---|---|---|
| id | UUID | |
| name | String | e.g. "Lagavulin 16" |
| distilleryName | String | Denormalized string; matched against seed data when possible |
| region | String | Region ID from RegionCatalog. Required, auto-filled when distillery matches seed data |
| country | String | Default "Scotland". Not shown anywhere in v1 UI, exists for expansion |
| barcode | String? | EAN-13 / UPC-A digits |
| abv | Double? | Percent, e.g. 43.0 |
| ageStatement | Int? | nil means NAS; display "NAS" when nil and user confirmed no age |
| caskType | String? | Free text, e.g. "Ex-bourbon, PX finish" |
| purchasePrice | Decimal? | |
| currencyCode | String | Default "USD". Not shown in v1 UI |
| purchaseDate | Date? | |
| status | BottleStatus | enum: sealed, open, finished. Default sealed |
| rating | Double? | 0.0 to 5.0 in 0.5 steps |
| stockPhotoURL | String? | From Open Food Facts if the lookup returned one |
| userPhotoFilename | String? | Photo stored as JPEG in Application Support, filename only in DB |
| dateAdded | Date | |
| notes | [TastingNote] | Relationship, cascade delete |

Photo storage: user photos are saved as downsampled JPEGs (max 2000px long edge, ~0.8 quality) to Application Support/Photos/. A 300px thumbnail is generated alongside. The DB stores filenames only. This keeps SwiftData fast and export files small. All photo access goes through an ImageStore protocol with a LocalImageStore implementation in v1, so a synced implementation can replace it later without touching views.

Schema rules, CloudKit-forward (non-negotiable, they cost nothing now and prevent a painful migration when sync arrives):
- No `@Attribute(.unique)` anywhere. CloudKit mirroring does not support unique constraints. Duplicate barcode detection is a fetch, not a constraint.
- Every attribute is optional or has a default value.
- All relationships are optional (`notes: [TastingNote]? `) with inverse relationships declared explicitly.
- No deny-delete rules; deletion logic lives in code.

### TastingNote (@Model)
| Field | Type |
|---|---|
| id | UUID |
| date | Date |
| nose | String |
| palate | String |
| finish | String |
| conclusion | String |

One bottle can have multiple notes over time, newest first.

### Distillery seed data (bundled JSON, not SwiftData)
~140 active Scottish malt distilleries. Each entry:
```json
{
  "name": "Lagavulin",
  "aliases": ["Lagavulin Distillery"],
  "region": "islay",
  "lat": 55.6365,
  "lon": -6.1268,
  "founded": 1816,
  "owner": "Diageo",
  "wikipediaTitle": "Lagavulin_distillery"
}
```
Claude Code: generate this file from your knowledge of Scottish distilleries. Cover at minimum every distillery with bottles in common US retail (all Diageo, Pernod, Edrington, Beam Suntory, Bacardi, Whyte & Mackay, LVMH, Ian Macleod, and major independent distilleries). Accuracy of region assignment matters more than completeness. Mark the Islands distilleries (Talisker, Highland Park, Scapa, Jura, Tobermory, Arran, Raasay, Abhainn Dearg, Torabhaig, Lagg) as `islands`.

DistilleryStore provides: exact match, case-insensitive contains match, and a simple fuzzy match (normalized Levenshtein or token overlap) for matching scanned product names like "LAGAVULIN 16YO ISLAY SINGLE MALT" to "Lagavulin".

## 6. Features

### F1: Barcode scan and lookup
- Scan tab or prominent scan button opens VisionKit `DataScannerViewController` configured for EAN-13 and UPC-A.
- On capture, run the lookup cascade. Stop at the first tier that returns a usable product name.
  - Tier 1, Open Food Facts (free, no key, no meaningful limit):
    `GET https://world.openfoodfacts.org/api/v2/product/{barcode}.json?fields=product_name,brands,image_url,alcohol_by_volume,categories_tags`
    Set a custom User-Agent per OFF etiquette: `UisgeBeatha/1.0 (personal iOS app)`.
  - Tier 2, UPCitemdb trial endpoint (free, no key, 100 lookups/day per IP, burst limit ~6/min):
    `GET https://api.upcitemdb.com/prod/trial/lookup?upc={barcode}`
    Use `items[0]`: title, brand, images array. On HTTP 429, skip silently to the miss path.
  - Normalize whichever tier hits into a single LookupResult struct (name, brand, imageURL, abv?, categoryTags) before any UI sees it. Log which tier answered, visible in a debug setting.
  - Cache every cascade outcome (hit or miss) on disk keyed by barcode, 90-day expiry, so rescans and duplicate checks cost no network calls.
  - Optional Tier 3, disabled by default behind a build flag: web search on the raw EAN via a search API to recover a product name when both databases miss. Not wired to any provider in v1; the protocol should make adding one a single conformance.
- Hit path: show a Lookup Result sheet with product name, brand, stock image, ABV if present, and the matched distillery + region (via DistilleryStore fuzzy match on product_name and brands). Two actions: "Add to Collection" (opens the entry form pre-filled for confirmation) and "Details Only" (read-only view, nothing saved).
- Scotch gate:
  - If categories clearly indicate non-scotch (bourbon, irish, japanese, canadian, rye, tennessee, vodka, gin, rum, wine, beer tags), show a friendly rejection: "This one isn't a Scotch whisky. Uisge Beatha tracks Scotch only for now." No add path.
  - If ambiguous (no category data, no distillery match), do NOT reject. Fall through to the manual form pre-filled with whatever came back. Free databases are too sparse to trust a hard reject on missing data.
- Miss path (404 or no product): go straight to the manual entry form with the barcode field pre-filled and a one-line notice: "Not found in the database. Add it manually and it's saved for good."
- Duplicate handling: if the barcode already exists in the library, jump to that bottle's detail instead of adding a duplicate, with a toast "Already in your collection."

### F2: Manual entry / edit form
Fields: name (required), distillery (required, autocomplete against seed data; picking a match auto-fills region), region (required, auto-filled but editable, segmented or menu picker of the six regions), ABV, age statement (with an NAS toggle), cask type, purchase price, purchase date, status, barcode (read-only if it came from a scan).
Same form is reused for editing. Validation: name and distillery non-empty, region selected.

### F3: Collection, list view
- Default view. Rows show thumbnail (user photo, else stock photo, else a region-colored monogram placeholder), name, distillery, region tag, status pill, rating stars.
- Sortable by: name, distillery, region. Sort control in toolbar. Persist last sort choice.
- Search bar filters on name and distillery.
- Swipe actions: change status, delete (with confirmation).
- Empty state: friendly illustration-free message + "Scan your first bottle" button.

### F4: Collection, map view
- A toggle (top segmented control: List | Map) switches views. Persist last choice.
- MapKit map framed on Scotland (roughly center 57.2N, -4.5W, span covering Campbeltown to Orkney).
- One annotation per region at its centroid: a glass-material badge showing the region name and bottle count. Regions with zero bottles render dimmed.
- Tapping a badge presents a sheet listing that region's bottles; tapping a bottle pushes its detail.
- Do not attempt polygon overlays of region boundaries in v1. Centroid badges only.

### F5: Bottle detail
Layout, top to bottom:
1. Hero photo: user photo if present, else stock photo loaded from stockPhotoURL (AsyncImage with cache), else placeholder. Buttons: "Take Photo" (camera) and "Choose Photo" (PhotosPicker). Retake replaces.
2. Facts grid: distillery, region, ABV, age, cask type, status (tappable to cycle), purchase price and date, date added.
3. Distillery card: Wikipedia summary (see F6).
4. Rating: 0 to 5 stars in half steps, large tappable control.
5. Tasting notes section (see F7).
6. Edit and Delete in toolbar menu.

### F6: Distillery info (Wikipedia)
- `GET https://en.wikipedia.org/api/rest_v1/page/summary/{wikipediaTitle}` using the title from seed data; if the distillery isn't in seed data, try `{distilleryName}_distillery` then `{distilleryName}`.
- Show: thumbnail, extract (first ~4 sentences), founded year and owner from seed data, and a "Read more on Wikipedia" link that opens SFSafariViewController.
- Cache responses on disk keyed by title, 30-day expiry. Offline or failure: show seed-data facts only, no error banner.

### F7: Tasting notes and wheel
- "New Tasting Note" opens an editor with four multiline fields: Nose, Palate, Finish, Conclusion. Date defaults to now, editable.
- A "Flavour Wheel" button in the editor opens a reference sheet with an original tasting wheel rendered natively in SwiftUI (Canvas or SVG-like Path drawing). Do NOT bundle any wheel image from the internet; the well-known scotch wheels are copyrighted.
- Wheel spec: two rings. Inner ring, 8 categories: Smoky, Fruity, Floral, Malty, Woody, Spicy, Sweet, Maritime. Outer ring, 3 descriptors per category (e.g. Smoky: peat, bonfire, medicinal; Fruity: orchard, citrus, dried fruit; etc. Claude Code picks sensible descriptors). Category colors work in both light and dark mode. The wheel is reference-only in v1; segments are not tappable inputs.
- Notes display on the bottle detail as cards, newest first, with relative dates.

### F8: Settings
- Export Collection: JSON (full fidelity) and CSV (flat, one row per bottle, notes concatenated). Share via ShareLink. Photos are not included in exports in v1; note this in the UI.
- About: app version, data stays on device notice.
- (No import in v1.)

## 7. Design direction

- iOS 26 Liquid Glass design language: system materials, glass tab bar and toolbars, concentric corner radii, let content flow under bars. Use system components before custom ones.
- Minimal and stylish: generous whitespace, SF Pro (system fonts only), one accent color (deep amber, roughly #C46A1B, tuned separately for dark mode), plus the six region colors used only for tags, map badges, and placeholder monograms.
- Full light and dark mode support. Verify every screen in both. Photos and the tasting wheel must sit well on both backgrounds.
- Navigation: TabView with two tabs, Collection and Settings, plus a prominent center Scan action (raised circular button or a Scan tab, whichever fits Liquid Glass tab bar conventions in iOS 26 best).
- Reference apps for feel: Apple's own Journal and Fitness apps for card layouts and materials; Vivino/Untappd only for information hierarchy on the detail page, not their visual style.

## 8. Non-functional requirements

Performance
- Cold launch to interactive collection list under 1 second on the owner's device.
- List scrolling at 120 Hz with 100 bottles and photos: use thumbnails in rows, never full-size images; lazy stacks; downsample on import with ImageIO.
- All network calls async, never block UI, everything usable offline except lookup and Wikipedia.

Accessibility
- Full Dynamic Type support including accessibility sizes (rows reflow, no truncation of names).
- VoiceOver labels on all controls; rating control announces "3 and a half stars, adjustable" and supports swipe adjust.
- Minimum 44pt touch targets. Respect Reduce Motion (disable any springy hero transitions). Contrast-check region colors in both modes.

Quality bars
- No third-party dependencies. No force unwraps in non-test code. Errors surface as quiet inline states, never blocking alerts unless destructive.

## 9. Build plan (execute in order, verify each phase before the next)

Phase 0: Project shell (owner does this by hand, 10 minutes)
1. Xcode 26 > New Project > iOS App. Product name: UisgeBeatha (no space, this becomes the module name). Interface: SwiftUI. Language: Swift. Storage: none (SwiftData added in code). Then in the target's General settings set Display Name to "Uisge Beatha", which is what appears under the icon.
2. Signing: Personal Team (free Apple ID). Bundle ID: com.ryo.uisgebeatha. Deployment target: iOS 26.
3. Add camera usage description to Info: NSCameraUsageDescription "Uisge Beatha uses the camera to scan bottle barcodes and photograph your bottles." Add NSPhotoLibraryAddUsageDescription similarly.
4. Run the empty app on the physical iPhone once to confirm signing works. Camera and scanning cannot be tested in the simulator.
5. Hand the project folder to Claude Code.

Phase 1: Models and seed data
- Bottle, TastingNote, BottleStatus, RegionCatalog, CollectionPolicy. ModelContainer in UisgeBeathaApp, schema following the CloudKit-forward rules in section 5.
- Generate Resources/distilleries.json and DistilleryStore with matching functions.
- Acceptance: unit tests pass for seed loading (count > 120, all six regions present, known spot checks: Lagavulin=islay, Glenfarclas=speyside, Springbank=campbeltown, Talisker=islands), and for fuzzy matching ("LAGAVULIN 16 YEARS" resolves to Lagavulin).

Phase 2: Collection list + manual entry
- RootTabView, list view with sort/search/swipe actions, add/edit form with distillery autocomplete and region auto-fill, delete with cascade.
- Acceptance: add 5 bottles manually, sort by all three keys, search works, edit persists, delete removes notes too, empty state shows on fresh install.

Phase 3: Bottle detail, photos, rating, tasting notes, wheel
- Detail layout, camera + photo picker with downsampling and thumbnail generation, ImageStore, half-star rating control, tasting note CRUD, SwiftUI tasting wheel sheet.
- Acceptance: photo capture persists across app relaunch, replacing a photo deletes the old files, rating adjustable via tap and VoiceOver, two notes on one bottle display newest first, wheel renders correctly in light and dark.

Phase 4: Scan and lookup
- VisionKit scanner, BarcodeLookupService cascade (OFF then UPCitemdb) with disk cache, lookup result sheet, scotch gate, miss path into pre-filled manual form, duplicate detection, stock photo URL persistence.
- Acceptance: a known-good barcode (test with a Glenlivet or Glenfiddich bottle) shows the result sheet and adds correctly; a bottle absent from OFF but present in UPCitemdb resolves via tier 2 (verify with the debug tier log); a nonsense barcode routes to the manual form with barcode pre-filled; rescanning the same barcode answers from cache with no network call; scanning an existing bottle's barcode jumps to its detail.

Phase 5: Map view
- Segmented toggle, MapKit Scotland framing, centroid count badges, region sheet with filtered list.
- Acceptance: counts match the library, zero-count regions dimmed, tapping badge > bottle > detail navigation works, toggle choice persists.

Phase 6: Wikipedia, export, polish
- WikipediaService with disk cache, distillery card on detail, SFSafariViewController link out, JSON/CSV export with ShareLink, full dark mode audit, Dynamic Type audit, accessibility pass, app icon (simple glass/amber motif, generated as an asset).
- Acceptance: distillery card shows for a seed-data distillery and degrades gracefully offline; exported JSON re-parses and CSV opens in Numbers; every screen checked in dark mode and at XXL type size.

## 10. Scale path: v1 decisions that protect future versions

The owner intends to release on the App Store if the app proves useful, then add accounts/sync, expand beyond Scotch, and add a stats dashboard. v1 does not build any of that, but v1 must not block any of it.

### 10.1 Architectural commitments in v1 (build these now)
1. CloudKit-compatible SwiftData schema per the rules in section 5. This is the single highest-leverage item on this list.
2. `country` and `currencyCode` fields exist on Bottle with defaults, invisible in v1 UI, present in exports.
3. RegionCatalog is data, not code. Adding Irish, Japanese, Taiwanese, or American regions later means adding catalog entries and per-country distillery/producer seed files, not editing views.
4. CollectionPolicy owns the scotch gate. It is one injectable object holding an allowed-country set (v1: Scotland only) and the rejection copy. World whisky support means changing this object's data and nothing else in the scan flow.
5. ImageStore is a protocol. v1 ships LocalImageStore (files on disk). Sync later means adding a store that keeps photo data in the model with `@Attribute(.externalStorage)` or CKAsset, behind the same interface.
6. Every user-facing string lives in one Strings file. Not localization, just one place. This is also where the Whisky/Whiskey spelling rule gets enforced per country when non-Scotch arrives (bourbon is "whiskey").
7. Network services (lookup cascade, Wikipedia) stay behind protocols, already specified.
8. JSON export includes every field including country and currencyCode, so exports made today import cleanly into future versions.

### 10.2 Before App Store release: acquire and change
- Apple Developer Program, $99/yr. Kills the 7-day re-sign ritual (section 13 becomes obsolete), enables TestFlight and CloudKit.
- Accounts and sync: use CloudKit private database via SwiftData's CloudKit mirroring (`ModelConfiguration` with `cloudKitDatabase: .automatic` plus the iCloud capability and a container). Because the schema followed the section 5 rules, this is a configuration change, not a migration. "Log in" is the user's Apple ID; their collection, notes, and photos follow them across devices with zero auth screens to build. Only build a real account system (Sign in with Apple plus a backend like Supabase) if non-Apple platforms or social features ever land on the roadmap; do not build it just for sync.
- Photo sync: switch the active ImageStore to the synced implementation; write a one-time migrator that moves existing local files into it.
- UPCitemdb: the keyless trial endpoint is rate-limited per client IP and intended for evaluation. Before public release, either move to a keyed plan or confirm current terms permit production use at expected volume. Open Food Facts stays fine with a proper User-Agent.
- App Review package: privacy policy URL, App Privacy labels (with local-only or CloudKit private DB storage, the developer collects nothing), support URL, screenshots, marketing icon. Confirm the name "Uisge Beatha" is available on the App Store before committing to store assets. Expect a 17+ age rating because the app's subject is alcohol; the app must not glamorize consumption in store metadata.
- Run the 50-user beta through TestFlight before the public listing.

### 10.3 Roadmap sketch (not commitments)
- v1.1: stats dashboard. Bottle count by region, total collection spend, average rating, sealed/open/finished breakdown, most-represented distillery. Computed entirely from existing fields; zero schema change, which is why nothing needs protecting for it.
- v2.0: paid dev account, CloudKit sync, TestFlight beta, App Store release.
- v2.5: world whisky. Extend RegionCatalog and seed data (Ireland, Japan, Taiwan, US, Canada), flip CollectionPolicy to the new country set, map view becomes country-scoped (a country picker above the map, Scotland framing preserved per country), spelling rules applied per country from the Strings file.
- Parked further out: wishlist, import from export files, iPad layout, bottle sharing.

## 11. Out of scope for v1
Everything in 10.3, plus reviews and US pricing (needs a paid API or AI lookup) and distillery news. Do not build speculative abstractions for these beyond what 10.1 lists.

## 12. Instructions block for Claude Code (paste as CLAUDE.md in the project root)

```markdown
# Uisge Beatha: project instructions

You are building Uisge Beatha, a scotch whisky collection iPhone app. The full PRD is in uisge-beatha-prd-build-plan.md at the repo root. Read it before writing any code.

Hard rules:
- Swift 6, SwiftUI, SwiftData, iOS 26 minimum. Zero third-party dependencies.
- Follow the build phases in the PRD in order. Complete the acceptance criteria for a phase before starting the next. Ask me to run on-device checks when a phase needs camera or maps verification.
- The SwiftData schema must stay CloudKit-compatible: no unique constraints, every attribute optional or defaulted, all relationships optional with explicit inverses. Duplicate detection is a fetch, never a constraint.
- Never switch over region cases in UI or logic. All region rendering reads RegionCatalog. The scotch-only rule lives in CollectionPolicy and nowhere else.
- UI text: always "Whisky", never "Whiskey", avoid plural forms ("Collection" or "Bottles" instead). English only. All user-facing strings live in one Strings file.
- v1 catalog: exactly six Scotland regions: Highland, Lowland, Islay, Speyside, Islands, Campbeltown.
- Never bundle images downloaded from the internet. The tasting wheel is drawn in SwiftUI. The app icon is original.
- No force unwraps outside tests. Strict concurrency clean. Build must compile warning-free before you declare a phase done.
- Photos: all photo access goes through the ImageStore protocol (LocalImageStore in v1), JPEGs downsampled, thumbnails always generated, filenames in SwiftData.
- Every screen must work in light and dark mode and at accessibility Dynamic Type sizes.
- When uncertain about a product decision, check the PRD's locked decisions table first; if still uncertain, ask, don't invent features. Do not build v2 features (sync, dashboard, world whisky) but do not break the section 10 commitments that keep them cheap.
```

## 13. Owner's weekly ritual (free Apple ID reality, obsolete once section 10.2 happens)
Every 7 days the app stops launching (expired provisioning). Plug in the iPhone, open the project, press Run. Data is untouched. Do not delete the app from the phone; that erases the local database. Export a JSON backup from Settings after any big cataloging session.
