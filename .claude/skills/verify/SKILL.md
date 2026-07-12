---
name: verify
description: Build, test, and drive the Uisge Beatha iOS app in the simulator to verify changes end-to-end.
---

# Verifying Uisge Beatha changes

iPhone-only SwiftUI app, iOS 26, Xcode 26. No third-party deps. Simulator: **iPhone 17 Pro** (iOS 26.5).

## Build (must be warning-free per project rules)

```bash
xcodebuild -project UisgeBeatha.xcodeproj -scheme UisgeBeatha \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -cE "warning:" 
```

Ignore the `appintentsmetadataprocessor` "warning" line — it's tool noise, not a compiler warning.

## Unit tests (Swift Testing, hosted in app)

```bash
xcodebuild -project UisgeBeatha.xcodeproj -scheme UisgeBeatha \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## UI driving (XCUITest is the only tap driver — no idb/cliclick on this machine)

The `UisgeBeathaUITests` target + scheme is the driving harness. It is NOT in the main
scheme's testables (kept out deliberately so unit runs stay fast). Uninstall first for
a fresh-install empty state:

```bash
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null
xcrun simctl uninstall "iPhone 17 Pro" com.ryo.UisgeBeatha
xcodebuild -project UisgeBeatha.xcodeproj -scheme UisgeBeathaUITests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## Evidence capture

```bash
xcrun simctl launch "iPhone 17 Pro" com.ryo.UisgeBeatha
xcrun simctl ui "iPhone 17 Pro" appearance dark   # or light
xcrun simctl io "iPhone 17 Pro" screenshot out.png
```

UI test failures: no PNGs in the xcresult, but there IS a screen recording.
Export attachments then pull frames with AVAssetImageGenerator (Swift script):

```bash
XCR=$(ls -td ~/Library/Developer/Xcode/DerivedData/UisgeBeatha-*/Logs/Test/*.xcresult | head -1)
xcrun xcresulttool export attachments --path "$XCR" --output-path <dir>   # manifest.json lists the .mp4
```

PASSING runs keep no recording. To capture a specific screen from a passing
drive, add inside the test:
`let s = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); s.lifetime = .keepAlways; add(s)`
then export attachments as above (manifest lists it by its `name`).

## Gotchas learned the hard way

- XCUITest queries: the bottle row combines accessibility children; the status pill
  text ("Sealed"/"Open") is reachable as `cell.staticTexts["..."]` but NOT via
  `cell.label`. Form text fields are matched positionally (`textFields.element(boundBy:)`:
  0=name, 1=distillery).
- The UI test target uses `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated` (MainActor
  default breaks XCTestCase overrides). The app + unit test targets use MainActor.
- iOS 26 search: leaving search = tap `Clear text` button then the round X/Cancel.
- Camera and barcode scanning do NOT work in the simulator — those need the owner's
  device (PRD phases 3/4 call this out).
