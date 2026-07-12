

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

