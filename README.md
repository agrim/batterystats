# BatteryStats

BatteryStats is a native macOS battery utility for Apple Silicon Mac laptops. It gives you a compact battery dashboard, a menu bar view, a settings window, and a small widget without bringing in non-Apple dependencies, Rosetta, or a backend.

[Download the notarized `BatteryStats-arm64.dmg`](https://github.com/agrim/batterystats/releases/download/v1.0.3/BatteryStats-arm64.dmg)

SHA-256 checksum: [`BatteryStats-arm64.dmg.sha256`](https://github.com/agrim/batterystats/releases/download/v1.0.3/BatteryStats-arm64.dmg.sha256)

The public download is Developer ID signed, Apple-notarized, and stapled. Non-notarized DMG artifacts are not tracked or distributed.

The repository currently targets the corrective `1.0.4 (5)` build. The public download remains `v1.0.3` until a new Developer ID build has been exported, verified, notarized, and published. The `v1.0.3` signature does not contain the iCloud KVS entitlement, so iCloud sync is unavailable in that binary; the current source and release verifier correct that signing drift.

## Current Source Corrections

- The app and widget share snapshots through the notarization-safe Team-ID App Group `Q293G85PG5.io.github.agrim.batterystats`
- Widget timelines project remaining-time decay and an explicit stale transition with entries at least five minutes apart
- Valid macOS remaining-time estimates take precedence; custom discharge estimates require recent, stable samples
- Wake, power transitions, large sampling gaps, and monitor restarts reset discharge-rate confidence
- Brief IOKit read gaps retain the last snapshot while retrying instead of immediately blanking every surface
- Charging top-off preserves a valid system time instead of forcing `0m`
- Current-charge energy is labeled as an estimate; full/design Wh are not derived from instantaneous terminal voltage
- History separates battery drain, battery charge, and adapter input and uses time-weighted averages
- Signed-product validation checks effective entitlements, the iCloud profile, nested signatures, version coherence, and the active installed widget

## What Ships In v1.0.3

- Native macOS app built with SwiftUI and Apple frameworks only
- Apple-Silicon-first Developer ID signed and notarized DMG release
- Compact battery window with health, charge, time, status, cycle count, and temperature
- Menu bar extra with multiple display modes, including remaining-time display
- Launch at login support through `SMAppService`
- Configurable or dynamic refresh cadence with out-of-cycle refreshes for large energy-use shifts
- Optional local battery history with a history summary in Settings
- Optional local alerts for low battery, charge complete, and high temperature
- System small and medium widgets with circular battery indicators
- Debug actions to copy raw and parsed battery snapshots

## What The App Shows

BatteryStats currently focuses on:

- battery health as full-charge capacity vs design capacity
- current charge as current charge vs full-charge capacity
- time left or time to full
- charging or on-battery state
- charge cycle count
- temperature

When the underlying system exposes more data, BatteryStats also calculates:

- an estimated current-charge watt-hour value
- signed current and discharge rate
- charge wattage
- manufacture date
- battery age
- adapter wattage

If a value is unavailable on the current Mac or battery, BatteryStats leaves it unavailable rather than inventing it.

## Surfaces

### Main Window

The main window is a compact summary surface, not a giant dashboard. It emphasizes:

- battery health
- current charge
- time left or time to full
- battery status

### Menu Bar Extra

The menu bar label can be configured to show:

- icon only
- icon plus current percentage
- icon plus health
- icon plus full-charge capacity
- icon plus remaining time

Opening the menu bar extra shows the same compact battery surface used by the main window.

### Settings

The settings window supports:

- launch at login
- iCloud preference sync
- menu bar display mode
- refresh cadence
- energy-change sensitivity
- temperature unit
- local alert policy
- local battery history
- advanced value toggle
- copy raw snapshot
- copy parsed snapshot
- reset settings

### Widget

The `systemSmall` widget is named **Battery Circles**. It shows:

- health ring
- charge ring
- time ring
- power-state ring

The widget keeps the four-ring compact layout. If the host app quits, it continues showing the last valid snapshot for up to six hours instead of replacing retained values with an unavailable state.

## Platform Notes

- Intended for Mac laptops with an internal battery
- Best experience on Apple Silicon
- The DMG published here is arm64 only
- The public DMG is Developer ID signed, notarized by Apple, and stapled
- Desktop Macs and unsupported battery configurations fall back to a clean unsupported state

## Build From Source

Requirements:

- Xcode 26 or newer (the current validation environment is Xcode 27)
- XcodeGen 2.39 or newer
- macOS 26 or newer
- an Apple Development identity for signed local App Group/widget validation
- a provisioning profile authorizing iCloud KVS for the app target

Generate the project:

```bash
xcodegen generate
```

Signed debug build and run:

```bash
BATTERYSTATS_ALLOW_PROVISIONING_UPDATES=1 ./script/build_and_run.sh
```

The provisioning-update flag is normally only needed for the first build or after capabilities change. It also lets Xcode register the current Mac when a development profile needs the device. Runtime modes reject unsigned products because an unsigned launch cannot validate WidgetKit, App Groups, iCloud KVS, or launch at login.

Install the signed build in `/Applications`, register the embedded widget, and verify the shared snapshot:

```bash
BATTERYSTATS_ALLOW_PROVISIONING_UPDATES=1 ./script/build_and_run.sh install
```

Run tests:

```bash
./script/build_and_run.sh test
```

An explicit unsigned compile/test fallback remains available when signing is intentionally out of scope:

```bash
BATTERYSTATS_SIGNING_MODE=unsigned ./script/build_and_run.sh test
```

Create a versioned Developer ID, notarized, stapled release candidate without overwriting the currently published DMG:

```bash
BATTERYSTATS_ALLOW_PROVISIONING_UPDATES=1 ./script/package_release.sh
```

## Repository Layout

- `BatteryStats/` — main app source
- `BatteryStatsWidgets/` — widget extension
- `Tests/BatteryStatsTests/` — unit tests
- `BatteryStats/Resources/IconLayers/AppIcon.icon` — saved Icon Composer app icon source
- `dist/BatteryStats-arm64.dmg` — tracked notarized release artifact
- `dist/BatteryStats-arm64.dmg.sha256` — SHA-256 checksum for the tracked release artifact

## Release Notes

See [CHANGELOG.md](CHANGELOG.md) for the unreleased `v1.0.4` corrective notes and the published `v1.0.3` summary.
