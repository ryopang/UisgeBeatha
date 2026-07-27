# Label scan reliability: diagnosis and execution plan

Status: **proposal, awaiting approval**. Nothing in this document has been built.

Scope: the "photograph a bottle, get the whisky" path (label OCR → prefill), the
stock-photo search that backs it up, and the UX around both. Plus a short list of
performance cleanups found on the way.

---

## 0. How I measured, and what I could not do

**Measured.** I ported `LabelParser`, `WhiskyLabelParser` and `DistilleryStore`
verbatim into a standalone Swift harness and ran the real bundled
`distilleries.json` against 12 realistic scotch-label OCR line sets (Macallan 12
Double Cask, Glenfiddich 12, Ardbeg Uigeadail, Laphroaig 10, Highland Park 18,
Talisker 10 with an OCR typo, Springbank 15, Glenmorangie 18, Bunnahabhain 12,
Balvenie DoubleWood, Lagavulin 16, Oban 14).

| Field | Correct |
|---|---|
| Distillery | 12 / 12 |
| **Age** | **6 / 12** |
| ABV | 11 / 12 |
| **All three correct** | **5 / 12 (42%)** |

That 42% is with *clean* synthetic OCR — no misread characters, no dropped
lines, no glare. Real Vision output on a curved glossy label degrades it further,
which is consistent with the ~25% you see. The gap between 42% and 25% is almost
entirely Vision configuration (§A5), which the harness cannot simulate.

**Build environment — resolved.** `xcode-select` points at
`/Library/Developer/CommandLineTools`, which initially looked like "no Xcode".
Xcode 27.0 beta is installed at `/Applications/Xcode-beta.app`; exporting
`DEVELOPER_DIR` per command reaches it without touching your system config (no
sudo, no `xcode-select -s`). Verified green baseline:

```
Xcode 27.0 beta · iOS 27.0 SDK · deployment target 26.0/26.5 · Swift 6.0
xcodebuild build → BUILD SUCCEEDED (warning-free)
xcodebuild test  → TEST SUCCEEDED (97 tests, 11 suites)
```

Standard invocation for all work below:

```bash
cd "/Users/ryo/Claude Code/UisgeBeatha" && \
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild test -scheme UisgeBeatha \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:UisgeBeathaTests
```

Note the SDK is now iOS 27, one ahead of the PRD's Xcode 26 / iOS 26. Deployment
target stays at 26.0 — I will not raise it.

**Still needs your hands.** Only two things: anything involving the live camera
(L3) and a real-photo accuracy check on actual bottles. See §0.1 — with photos
from you, even that second one moves to me.

### 0.1 The one thing that would help most: real photos

Now that the simulator is available, I can run **real Vision** — not just the
parser — inside a unit test, against images supplied as test fixtures. That means
if you drop 15–20 photos of bottles from your own shelf into a folder, I can
measure the true end-to-end hit rate here, iterate against it, and show you the
number moving — without you rebuilding anything.

- Shoot them the way you actually use the app: hand-held, your normal lighting,
  including the ones you know it currently fails on.
- A `bottle-photos/` folder anywhere, or drop them in `UisgeBeathaTests/Fixtures/Photos/`.
- Tell me the right answer for each (distillery, age, ABV) — filename is fine,
  e.g. `macallan-12-double-cask-40.jpg`.
- They stay local, get git-ignored, and are used only as test input.

Failing that, I can generate synthetic label images (rendering real label text to
a canvas with Core Graphics) and run Vision against those. That is enough to
prove out the `usesLanguageCorrection` and `customWords` changes in §A5 — the
single largest suspected cause — but it cannot simulate curved glass, glare, or
dark bottles. Real photos are meaningfully better.

**I also brute-forced the false-positive risk** on the fuzzy matcher: ~120 common
label words (matured, bottled, oloroso, signatory, importer, …) against all 114
single-token distillery names at edit distance ≤ 2. **Zero false positives.** The
Levenshtein pass is safer than it looks; the distillery-matching problems are
ordering and seed data, not fuzziness (§A4).

---

## 1. Diagnosis

### Track A — label photo → whisky identification

Ranked by how much each costs you, worst first.

---

**A1. Age is parsed line by line, but labels print age across two lines.**

`WhiskyLabelParser.age(in:)` runs `(\d{1,2})\s*[- ]?(?:years?|yrs?|yo)\b` against
each OCR line *independently*. Almost every scotch label sets the age as a large
standalone numeral with "YEARS OLD" as a separate typographic block — Vision
returns those as two separate observations. The number and the word never meet,
so nothing matches.

This alone accounts for the 6/12 age score. Failing fixtures:

```
Macallan       ["THE MACALLAN", "DOUBLE CASK", "12", "YEARS OLD", ...]  → age nil
Highland Park  ["HIGHLAND PARK", "18", "VIKING PRIDE", ...]             → age nil
Talisker       ["TALISKFR", "10", "MADE BY THE SEA", ...]               → age nil
Bunnahabhain   ["BUNNAHABHAIN", "12", "UN-CHILL FILTERED", ...]         → age nil
Oban           ["OBAN", "WEST HIGHLAND", "14", ...]                     → age nil
Glenmorangie   ["GLENMORANGIE", "18 Y.O.", ...]                         → age nil
```

The Glenmorangie case fails differently: `\b` after `yo` does not match before a
period, so `18 Y.O.` — standard on indie and travel-retail bottlings — is missed
even on one line.

`BarcodeLookupService.swift:261-291`, called from `LabelOCRService.swift:76`.

---

**A2. Both numeric regexes take the first match, then throw it away if it fails
the range check.**

`firstMatch()` returns match #1 only. `percentMatch` and `ageMatch` then
range-check that single value and return `nil` if it fails — they never look at
match #2. Any decoy number earlier in the line kills the field outright.

The common real-world trigger is the European comma decimal, printed on every
EU-market bottle:

```
"40,0% vol"  →  regex finds "0" before "%"  →  0 is outside 20...80  →  nil
```

`40` is sitting right there in the string. Same failure shape for `43,5% vol`,
and for age lines where a cask number or volume precedes the age.

`BarcodeLookupService.swift:268-298`.

---

**A3. The product name that comes out is usually junk.**

`LabelParser.nameCandidate` has two modes and both are wrong for real labels:

- *Distillery matched* → returns the first line **containing** the distillery
  name. On the Macallan fixture that is the bare line `"THE MACALLAN"`. The
  expression — "Double Cask", "12 Years Old" — is dropped. Every one of my 12
  fixtures produced a bare distillery name as the "product name".
- *No distillery matched* → returns **the longest line**. On a real label the
  longest line is "DISTILLED AND BOTTLED IN SCOTLAND", "SINGLE MALT SCOTCH
  WHISKY", or the importer's address. The Talisker-typo fixture literally
  produced `name = "SINGLE MALT SCOTCH WHISKY"`.

Nothing de-shouts OCR all-caps either, so saved names read `LAPHROAIG` rather
than `Laphroaig 10`.

`LabelOCRService.swift:85-92`.

---

**A4. Distillery selection is first-line-wins, with no tier awareness and no
global scoring.**

```swift
let matchedDistillery = lines.lazy.compactMap { distilleryStore.bestMatch(for: $0) }.first
```

Whichever line matches *first* wins, regardless of whether it matched by exact
equality, substring, or a fuzzy edit-distance guess. A weak fuzzy hit on line 1
beats an exact hit on line 4. Vision does not guarantee reading order, so line
order is not a signal you can lean on.

Two seed-data aliases are genuine false-positive magnets:

| Alias | Maps to | Fires on |
|---|---|---|
| `"1770"` | Glasgow Distillery | any label printing the year 1770 (founding dates are common) |
| `"Spey"` | Speyside Distillery | fine as a word, risky as a fragment |
| `"Ledaig"`, `"Cardow"` | Tobermory, Cardhu | correct, but sub-brands need tier separation |

`LabelOCRService.swift:70`, `DistilleryStore.swift:104`.

---

**A5. Vision is configured in ways that actively damage distillery names.**

`VisionLabelOCRService` (`LabelOCRService.swift:22-33`):

- **`usesLanguageCorrection = true`.** English language correction applied to
  BUNNAHABHAIN, BRUICHLADDICH, AUCHENTOSHAN, ALLT-A-BHAINNE, AUCHROISK,
  CRAIGELLACHIE. When correction rewrites one of these, A4 has nothing to match
  and A3 falls through to the longest-junk-line path. **This is my primary
  suspect for the gap between the harness's 42% and your observed 25%**, and it
  is a one-line change.
- **`topCandidates(1)` only.** The alternate readings that would rescue a
  misrecognised name are discarded at the source.
- **No `customWords`.** The bundle ships 126 distilleries and 292 total
  names + aliases. That is precisely the vocabulary `customWords` exists to bias
  toward, and it is already loaded in memory.
- **No `recognitionLanguages`, no revision pin.** Recognition behaviour drifts
  between OS updates with nothing pinned.
- **Default `minimumTextHeight` (1/32 of image height).** ABV and volume are the
  *smallest* text on a label; in a full-bottle photo they fall under the
  threshold and are never emitted at all.
- **Single pass, single orientation, whole frame.** No region of interest — on a
  typical arm's-length bottle photo the label occupies maybe a quarter of the
  frame, so most of Vision's effort goes to background.

---

**A6. One still frame from `UIImagePickerController`.**

`CameraPicker` grabs a single hand-held snapshot of a curved, glossy, frequently
dark-glass label. VisionKit's `DataScannerViewController` — already a project
dependency, already driving `BarcodeScannerView` — does *live, multi-frame* text
recognition. Accumulating agreeing reads across frames is far more robust than
one shot, and it stays inside the zero-dependency rule.

---

**A7. The label photo is captured and then thrown away.**

`BottleFormView.applyLabelScan` reads the image, extracts text, discards the
image. Then on save, `StockPhotoBackfill` goes out to the *internet* to find a
photo of the bottle the user just photographed. The best available photo of that
exact bottle already existed and was deleted.

`BottleFormView.swift:280-300` and `:336-338`.

---

**A8. Nothing shows what was read, or lets the user fix a wrong match.**

The banner reads "Read from the label — please check the details", but no field
indicates whether it came from OCR or was left alone, and there is no "wrong
distillery" affordance. With a pipeline that is right some of the time, the
review step is what converts a mediocre read into a correct record. Right now the
user has to notice the error unaided.

---

### Track B — stock photo search

**B1. Wikimedia Commons is structurally the wrong source.** It is an
encyclopedia media repository: distillery buildings, warehouses, stills,
landscapes. It does not hold product photography for specific expressions.
Searching it for "Lagavulin 16 whisky bottle" is expected to miss or to return a
building. It is tier 1.

**B2. Tier 2 is a search endpoint the code's own comments call unreliable** —
Open Food Facts free-text search, documented in-file as returning 503 "for
extended periods".

**B3. No result verification.** Whatever URL comes back first becomes
`stockPhotoURL`. Nothing checks that the image relates to the bottle.

**B4. Three better sources are already paid for:**
- the user's own label photo (A7) — exact, free, offline;
- the **distillery's** Wikipedia/Wikidata lead image — `wikipediaTitle` is
  already in the seed data for all 126 distilleries and `WikipediaService`
  already exists. Guaranteed relevant, if labelled honestly as a distillery photo
  rather than a bottle shot;
- Open Food Facts' *barcode* image (already fetched on the barcode-hit path,
  which is reliable) — currently only used when the barcode hit, never reused.

**B5. `DiskCache` key collision.** `fileURL(forKey:)` collapses every
non-alphanumeric character to `_`, so `"Glen Grant 12"` and `"Glen-Grant-12"`
share a cache file. Minor, real, one line.

---

### Track C — performance and hygiene (found in passing, not the headline)

- `BottleDetailView.heroSection` calls `UIImage(contentsOfFile:)` synchronously
  on the main actor, decoding a full 2000px JPEG during view body evaluation.
  Hitches on push. Should decode off-main or use the thumbnail as a
  progressive placeholder.
- `DistilleryStore` re-normalises and re-tokenises all 126 names + 166 aliases on
  every single match call. `LabelParser` calls `bestMatch` once per OCR line, so
  a 12-line label does that ~12×. Trivial at this size, but precomputing the
  normalised forms once at load is a few lines and makes the richer matching in
  L1 free.
- `LabelOCRService`'s protocol comment claims `nonisolated` keeps the slow
  recognition pass off the main actor. That is correct for the current API, but
  worth re-verifying after the L2 rewrite rather than assuming.

---

## 2. Execution plan

Seven work packages. **L0 first** — without a measurement harness there is no way
to show you the number moving, and no way to catch a regression later.

L1 and L2 together are where the reliability comes from. L3–L5 are where it
becomes *pleasant*. L6 is the stock-photo rework. L7 is cleanup.

---

### L0 — Fixture corpus and a measurement harness *(prerequisite)*

Build a labelled corpus and a repeatable score, so "25% → X%" is a number and not
a feeling.

- `UisgeBeathaTests/Fixtures/LabelFixtures.swift` — ~40 realistic OCR line sets
  with expected `(distillery, region, age, ABV, name)`. Sourced from real label
  typography across all six regions: split-line ages, NAS bottlings, comma
  decimals, cask-strength ABVs, importer boilerplate, indie bottlers, travel
  retail, and deliberate OCR corruptions (dropped chars, `I`↔`1`, `O`↔`0`,
  `S`↔`5`).
- `LabelParserAccuracyTests` — scores the corpus per field and asserts a floor,
  so accuracy can only go up. Prints a scorecard on failure.
- Keep my standalone harness in `scratch/` so parser work can be iterated here
  without Xcode.

**Acceptance:** harness runs, current code scores at the documented baseline
(≈42% all-three on the 12 I have; the 40-fixture baseline will be lower).

---

### L1 — Deterministic parsing correctness *(the biggest single win, zero Vision, zero UI)*

Pure Foundation. Fully testable here before you ever open Xcode.

1. **Line-window parsing.** Run field extraction over three views of the OCR
   output: each line alone; each *adjacent pair* joined; and the whole label
   joined. Fixes `["12"], ["YEARS OLD"]` and every A1 case. Ordered so a
   single-line match still wins over a cross-line one.
2. **Scan all regex matches, not just the first.** Replace `firstMatch` with an
   all-matches walk that returns the first *plausible* value. Fixes A2 outright.
3. **Widen the numeric grammar.**
   - ABV: comma decimals (`40,0%`), `ALC. 43% BY VOL`, `43° `, `43 % vol` with
     spacing, `CASK STRENGTH 58.6%`, and `%` OCR'd as `°/o` or `%o`.
   - Age: `Y.O.`, `YRS.`, `YEAR OLD`, `AGED nn`, `nn ANS`, spelled-out
     TWELVE–TWENTY-FIVE, and — guarded — a **standalone numeral in the plausible
     age set** (10, 12, 14, 15, 16, 18, 21, 25, 30…) when it sits on its own
     short line near the distillery name and is not adjacent to `%`, `cl`, `ml`,
     `PROOF`, or a four-digit year.
   - Explicit **NAS detection**: "NO AGE STATEMENT", "NAS", or a named expression
     with no age token anywhere → set `isNAS = true` rather than leaving age
     blank and ambiguous.
   - Guard against `70cl`/`700ml`/`750ML`, four-digit vintages, batch numbers,
     and cask numbers being read as ages.
4. **Global, tier-aware distillery scoring.** Replace first-line-wins with:
   score *every* line against *every* candidate, record the match tier (exact >
   contains > token-subset > Levenshtein) and the matched name's length, then
   pick the global best. Return a **confidence** alongside the match so the UI
   (L5) can say "not sure" instead of silently guessing.
5. **Seed-data guard.** Require aliases that are pure digits (`"1770"`) or under
   5 characters to match at the *exact* or *contains-with-word-boundary* tier
   only, never fuzzy — and never as the sole evidence for a match. Fixes the
   founding-year false positive.
6. **Real name construction.** Build the product name from the matched distillery
   + the expression line(s) + the age, rather than returning one raw OCR line:
   `THE MACALLAN` + `DOUBLE CASK` + `12` → `"Macallan Double Cask 12"`. Strip
   boilerplate ("SINGLE MALT SCOTCH WHISKY", "PRODUCT OF SCOTLAND", importer
   addresses, volume, ABV) and de-shout all-caps to title case, preserving known
   casing from seed data (`anCnoc`, `Nc'nean`, `InchDairnie`).
7. **Per-field provenance.** Have the parser return, for each field, whether it
   was read confidently, guessed, or absent. L5 consumes this; nothing else
   changes shape.

**Files:** `LabelOCRService.swift` (LabelParser), `BarcodeLookupService.swift`
(WhiskyLabelParser), `DistilleryStore.swift`, new `Support/LabelText.swift` for
the boilerplate/casing helpers.

**Acceptance:** on the L0 corpus, age ≥ 90%, ABV ≥ 95%, distillery ≥ 95%,
all-three ≥ 85%. No regression in `LabelOCRTests` or `BarcodeLookupTests`. Note
these are on *clean* fixture text — L2 is what delivers them on real photos.

---

### L2 — Vision configuration and multi-pass recognition

1. **Migrate to the modern Swift Vision API** (`RecognizeTextRequest` /
   `ImageRequestHandler`, async-native, iOS 18+) rather than the legacy
   `VNRecognizeTextRequest` + `VNImageRequestHandler` pair. The project mandates
   iOS 26 and Swift 6 strict concurrency; the new API is Sendable-clean and drops
   the manual `CGImagePropertyOrientation` conversion entirely. *Exact API
   surface to be confirmed against the SDK at build time.*
2. **`usesLanguageCorrection = false`** for the primary pass. Distillery names
   are not English words.
3. **Seed `customWords`** from `DistilleryStore` — all 126 names plus all 166
   aliases, plus a whisky vocabulary (single malt, cask strength, oloroso, PX,
   Uigeadail, DoubleWood, quarter cask, …). Requires threading the store into the
   OCR service; it is already in the environment.
4. **Keep the top 3 candidates per observation**, not 1, and let the distillery
   matcher (L1.4) consider all of them. A name misread as its second candidate
   becomes recoverable.
5. **Pin `recognitionLanguages = ["en-GB", "en-US"]`** and the request revision.
6. **Lower `minimumTextHeight`** so small print (ABV, volume) is emitted at all.
7. **Two-pass strategy:** run accurate + no-correction first; if the distillery
   confidence from L1 is low, re-run with language correction on and merge — the
   two passes fail differently, and the union recovers cases either alone misses.
8. **Region of interest:** detect the label with a rectangle/document pass and
   crop before recognition, so Vision spends its budget on the label rather than
   the room. Falls back to the full frame when nothing is detected.
9. **Downsample sensibly before recognition** — a 12MP frame is slower without
   being more accurate above roughly 2000px on the long edge.

**Files:** `LabelOCRService.swift`, `UisgeBeathaApp.swift` (inject the store into
the OCR service).

**Acceptance:** builds warning-free under Swift 6 strict concurrency; OCR runs
off the main actor (verify no hitch on capture); **on-device check by you** —
photograph 10 bottles from your own shelf and record the hit rate. This is the
step that needs your hands; the simulator has no camera.

---

### L3 — Live label scanning

Replace the single-snapshot `CameraPicker` on the label path with a
`DataScannerViewController` in text mode, mirroring `BarcodeScannerView`.

- Accumulate recognised text across frames; run L1 parsing continuously.
- Show a live overlay of what has been resolved so far — distillery, then age,
  then ABV lighting up as they lock in.
- Auto-settle when the parse is stable across N frames, or on an explicit tap.
- Keep the still-photo path as the fallback (and for the simulator).
- Reuse the unmount-on-sheet discipline documented in `BarcodeScannerView` —
  that comment block is a hard-won lesson; do not regress it.

**Acceptance:** on-device only. Label scan resolves without a shutter press on a
well-lit bottle; camera releases cleanly when the sheet opens.

---

### L4 — Keep the photo the user just took

- On label capture, save the image through `ImageStore` and set
  `userPhotoFilename` on the new bottle.
- Suppress the `StockPhotoBackfill` network call entirely when a user photo
  exists — it is currently fired for every new bottle without one.
- Offer "retake" in the review step (L5) and on the detail view, which already
  has the camera plumbing.

**Files:** `BottleFormView.swift`, `ProductImageSearchService.swift`
(`StockPhotoBackfill.fetch` guard).

**Acceptance:** a bottle added via label scan shows the user's own photo in the
list row and the detail hero; no image-search network call fires for it.

---

### L5 — A real confirmation step

Currently: OCR silently overwrites form fields and shows a one-line banner. With
a pipeline that is sometimes wrong, that is the wrong shape.

Replace with a **Scan Result sheet** between capture and the form, structurally
parallel to the existing `LookupResultSheet` so the two scan paths feel like one
feature:

- The captured photo at the top.
- Each read field as a row with its provenance from L1.7: confidently read,
  guessed, or not found. Guessed fields visually distinct — not an error state,
  just honest.
- Distillery row is tappable when confidence is low: shows the top 3 candidates
  with region tags, plus a search field falling through to the full 126.
- Fields Vision could not read appear as empty rows to fill, not as absences to
  discover later.
- Primary action "Add to Collection" → the existing pre-filled form. Secondary
  "Retake".
- Never blank a field the user already typed (current behaviour is right here —
  preserve it).

**Acceptance:** every field's origin is visible before saving; a wrong distillery
is correctable in two taps; light + dark mode; accessibility Dynamic Type sizes;
VoiceOver announces provenance.

---

### L6 — Stock photo sources, reordered around what actually works

New cascade, most-likely-correct first:

1. **User photo** (L4) — if present, no search at all.
2. **Open Food Facts barcode image** — when the bottle has a barcode, hit the
   *product* endpoint (reliable) rather than the *search* endpoint (not).
3. **Distillery lead image from Wikipedia**, keyed on the `wikipediaTitle`
   already in seed data. Exact match, no guessing. **Labelled honestly** in the
   UI as a distillery photo, not passed off as a bottle shot — this needs a new
   `Bottle` field or a URL convention, and it is a product decision I would like
   your call on (see §4).
4. **Wikimedia Commons free-text** — demoted to last, kept only because it
   occasionally works.

Also: never cache a `notFound` that came from a query built from an empty or
one-token name; fix the `DiskCache` key collision (B5); bump the cache folder
name so the current bad entries are dropped.

**Acceptance:** `ProductImageSearchTests` extended for the new tiers and
ordering; a bottle with a matched distillery always gets *something* relevant;
nothing is presented as a bottle photo when it is a building.

---

### L7 — Performance and hygiene

- Move the `BottleDetailView` hero decode off the main actor; show the thumbnail
  first.
- Precompute normalised names and tokens once when `DistilleryStore` loads.
- Downsample before Vision (L2.9).
- Re-verify strict-concurrency cleanliness after the L2 API migration.

---

## 3. Suggested order and checkpoints

| # | Package | Verifiable by | Checkpoint |
|---|---|---|---|
| 1 | L0 corpus + harness | **me** — `xcodebuild test` | baseline number agreed |
| 2 | L1 parsing | **me** — `xcodebuild test` | accuracy targets met |
| 3 | L2 Vision config | **me** — real Vision in simulator, against your photos (§0.1) | **measured hit rate** |
| 4 | L4 keep the photo | **me** — simulator + tests | quick |
| 5 | L5 confirmation UI | **me** — simulator screenshots, light + dark | design review with you |
| 6 | L6 stock photos | **me** — tests | |
| 7 | L3 live scanning | **you** — device only, needs a live camera | optional; biggest UX jump |
| 8 | L7 cleanup | **me** — build | |

Everything except L3 is now mine to verify. L3 is device-only because
`DataScannerViewController` needs a live camera; the simulator has none.

L3 is listed late deliberately: L1 + L2 + L5 should get you most of the
reliability, and L3 is a larger change worth doing once the parsing underneath it
is known-good.

I would suggest stopping after step 3 and looking at the measured number before
committing to the rest.

---

## 4. Decisions I need from you

1. **Bundled expression catalog — yes or no?**
   The highest-leverage thing not in this plan. A `Resources/expressions.json`
   of roughly 400–600 known core-range bottlings (distillery, expression name,
   age, ABV, region) at maybe 60 KB, following the exact precedent of
   `distilleries.json`. Then OCR only has to recognise "Macallan" + "12" to
   resolve the *canonical* name, age and ABV — instead of parsing them off a
   curved label. It would push age/ABV accuracy well past what regex tuning can
   reach, works fully offline, and adds zero dependencies.
   It is also **data the PRD does not mention**, and the project rules say to ask
   rather than invent. So: I'd like to build it, but it is your call.

2. **Distillery photo as a fallback bottle image (L6.3) — acceptable?**
   It is always relevant and never a bottle shot. Show it labelled as a
   distillery photo, or leave the region monogram placeholder instead?

3. **L3 live scanning — in or out for this round?**
   Biggest UX improvement, biggest change. Fine to defer.

4. **Accuracy floor.** L1's targets are on clean fixture text. What matters is
   your shelf. What real-world hit rate would you call "fixed" — 70%? 85%?

---

## 5. Design and UX suggestions (separate from the fix)

Offered as suggestions, not folded into the plan above. Nothing here is needed
for reliability.

**5.1 Merge the two scan paths into one.** Right now barcode and label are
separate flows with separate result sheets and a "No barcode? Scan the label
instead" escape hatch. On device they are the same intent: *point the camera at
the bottle*. One scanner that recognises barcodes **and** text simultaneously
(`DataScannerViewController` supports both in one session), taking whichever
resolves first and falling back to the other, would remove a decision the user
should not have to make. This subsumes L3 and is the single biggest UX
improvement available.

**5.2 Make the confirmation step feel like confidence, not like a form.** The
L5 sheet is a chance for the app's best moment — photo, name, region tag, the
distillery's Wikipedia line already loaded. Closer to `LookupResultSheet`'s
"Match Found" than to a spreadsheet of fields.

**5.3 Empty and uncertain states deserve the same care as the happy path.**
At a 25% hit rate the failure path *is* the main path today. "Couldn't read the
label. Try a closer, well-lit photo" is decent copy but arrives after the user
has already lost the moment. Better: keep the camera live (L3), show what *is*
being read as it is read, and let them stop when it is right.

**5.4 The collection list is doing a lot of work per row.** Thumbnail, name,
distillery, region tag, status pill, rating stars. With Dynamic Type at
accessibility sizes that will be a tall, busy row. Worth a look at what earns its
place — the region tag and rating may be better as a second line or on the detail
only. (Not verified on device; I could not run the simulator.)

**5.5 The map is currently decoration.** Six centroid badges on a Scotland map
is per the PRD and correct for v1, but tapping through region → list → bottle is
three taps to reach something the Collection tab reaches in one. If you want the
map to earn its tab, letting a region badge filter the list in place — rather
than pushing a sheet — would make it a lens rather than a detour.

**5.6 Cask type is a free-text field.** "Ex-bourbon, PX finish" typed by hand
each time. A token/suggestion field seeded from the values already in the
collection would cost little and make the data actually filterable later.

**5.7 One consistent word for the photograph-the-label action.** Currently
"Scan the Label", "No barcode? Scan the label instead", "Take Photo", "Choose
Photo", "Look Up Photo" — five phrasings across three screens for what a user
experiences as two things: *identify this bottle* and *photograph my bottle*.
Worth a pass through `Strings.swift`.

---

## 6. Risks

- ~~L2 cannot be verified without you.~~ **Resolved** — Xcode 27 found, build and
  tests green. Vision runs in the simulator against image fixtures. The remaining
  gap is fixture *realism*, which §0.1 addresses.
- **The modern Vision API surface needs confirming at build time.** I have
  written L2 to migrate to it; the SDK here is iOS 27, so I will confirm the
  exact surface with a compile rather than assume it. Fallback is the legacy API
  with the same configuration changes, which deliver most of the benefit anyway.
- **Xcode 27 beta / iOS 27 SDK is ahead of the PRD's Xcode 26.** Deployment
  target stays 26.0. Worth knowing that a beta toolchain is what the green
  baseline was measured on.
- **Widening the age grammar risks false positives.** The standalone-numeral rule
  is the dangerous one. It is why L1.3 gates it on the plausible-age set,
  proximity, and negative lookarounds — and why L0's corpus includes
  deliberate traps (70cl, vintages, batch numbers).
- **L1's targets are on synthetic text.** They are a necessary condition for
  fixing this, not a sufficient one. The number that matters is your shelf.
- **Nothing here changes the SwiftData schema** except possibly L6.3's
  distillery-photo flag, which would be a new optional attribute — CloudKit-safe,
  no migration concerns.
