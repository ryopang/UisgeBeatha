# Uisge Beatha: project instructions

You are working on Uisge Beatha, a scotch whisky collection app for iPhone and iPhone Duo, headed for the App Store. The PRD is `uisge-beatha-prd-build-plan.md` (v2.0) at the repo root. Read it before writing any code. The latest audit is `docs/audit-2026-11.md`. The v1 PRD is archived at `docs/archive/uisge-beatha-prd-v1.md`, for history only.

Hard rules:
- Swift 6, SwiftUI, SwiftData. Xcode 27 / iOS 27 SDK, minimum deployment iOS 26.0. Zero third-party dependencies.
- Follow the PRD build phases in order. Meet a phase's acceptance criteria before starting the next. Ask the owner to run on-device checks for camera, maps, sync and iPhone Duo fold/unfold behavior.
- Layout branches only on size classes (never orientation, screen size or device model). Keep view identity stable across size-class changes so folding or unfolding the Duo never loses a sheet, draft or scan.
- The SwiftData schema stays CloudKit-compatible: no unique constraints, every attribute optional or defaulted, all relationships optional with explicit inverses. Duplicate detection is a fetch, never a constraint. Every model change goes through a new `VersionedSchema` and the migration plan.
- Heavy work (ImageIO, Vision, parsing, Foundation Models) never runs on the main actor. Pass value types or `PersistentIdentifier` across isolation boundaries, never `@Model` instances.
- AI is Apple's on-device Foundation Models only. No cloud model providers, no API keys, no backend. The app must work identically when the model is unavailable.
- Never switch over region cases in UI or logic. All region rendering reads `RegionCatalog`. Region-colored text uses `textColor`, solid fills under white text use `badgeFillColor`. The scotch-only rule lives in `CollectionPolicy` and nowhere else.
- UI text: always "Whisky", never "Whiskey". Avoid plural forms ("Collection" or "Bottles" instead). English only. All user-facing strings live in `Strings.swift`.
- Exactly six Scotland regions: Highland, Lowland, Islay, Speyside, Islands, Campbeltown.
- Barcodes go through `Barcode.normalized` before any lookup, storage or comparison. All network calls use `AppNetwork.session`.
- Never bundle images downloaded from the internet. The tasting wheel is drawn in SwiftUI. The app icon is original.
- No force unwraps outside tests. Strict concurrency clean. The build must compile warning-free before you call a phase done.
- Photos: all photo access goes through the `ImageStore` protocol. JPEGs are downsampled and thumbnails always generated.
- Design system is PRD §8. `DESIGN.md` describes Apple's marketing website, not this app; don't apply it.
- Every screen must work in light and dark mode, at accessibility Dynamic Type sizes, in compact and regular width, with WCAG AA contrast and 44pt touch targets.
- When uncertain about a product decision, check the PRD's locked decisions (§3) first. If still uncertain, ask; don't invent features.
