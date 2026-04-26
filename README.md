# BatteryStats

BatteryStats is a native macOS battery utility for Apple Silicon Mac laptops. It gives you a compact battery dashboard, a menu bar view, a settings window, and a small widget without bringing in non-Apple dependencies, Rosetta, or a backend.

[Download the notarized `BatteryStats-arm64.dmg`](https://github.com/agrim/batterystats/releases/download/v1.0.3/BatteryStats-arm64.dmg)

SHA-256 checksum: [`BatteryStats-arm64.dmg.sha256`](https://github.com/agrim/batterystats/releases/download/v1.0.3/BatteryStats-arm64.dmg.sha256)

The public download is Developer ID signed, Apple-notarized, and stapled. Non-notarized DMG artifacts are not tracked or distributed.

## What Ships In v1.0.3

- Native macOS app built with SwiftUI and Apple frameworks only
- Apple-Silicon-first Developer ID signed and notarized DMG release
- Compact battery window with health, charge, time, status, cycle count, and temperature
- Menu bar extra with multiple display modes, including remaining-time display
- Launch at login support through `SMAppService`
- Optional iCloud preference sync through `NSUbiquitousKeyValueStore`
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

- watt-hour values
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

### Widgets

The widgets are named **Battery Circles**. They show:

- health ring
- charge ring
- time ring
- power-state ring

The small widget keeps the four-ring compact layout. The medium widget adds labels and text values.

## Platform Notes

- Intended for Mac laptops with an internal battery
- Best experience on Apple Silicon
- The DMG published here is arm64 only
- The public DMG is Developer ID signed, notarized by Apple, and stapled
- Desktop Macs and unsupported battery configurations fall back to a clean unsupported state

## Build From Source

Requirements:

- Xcode 17+
- `xcodegen`
- macOS 15+ for the current project and Icon Composer workflow

Generate the project:

```bash
xcodegen generate
```

Debug build and run:

```bash
./script/build_and_run.sh
```

Run tests:

```bash
xcodebuild -project BatteryStats.xcodeproj -scheme BatteryStatsTests test
```

Release build:

```bash
xcodebuild -project BatteryStats.xcodeproj -scheme BatteryStats -configuration Release -derivedDataPath .build/DerivedDataRelease build
```

## Repository Layout

- `Platforms/macOS/App/` — shipping macOS app source
- `Platforms/macOS/Widgets/` — shipping macOS widget extension
- `Platforms/iOS/App/` — staging area for the universal iPhone app target
- `Platforms/iPadOS/` — staging area for iPad-specific presentation and interaction code
- `Platforms/watchOS/App/` — staging area for the watchOS app shell
- `Platforms/watchOS/Extension/` — staging area for watch-specific runtime code
- `Shared/BatteryCore/` — cross-platform battery models, calculations, policies, formatting, and utilities
- `Shared/Support/` — reusable Apple-platform support code that targets opt into deliberately
- `Tests/BatteryStatsTests/` — unit tests
- `docs/multi-device-architecture.md` — multi-device branch and target strategy
- `Platforms/macOS/App/Resources/IconLayers/AppIcon.icon` — saved Icon Composer app icon source
- `dist/BatteryStats-arm64.dmg` — tracked notarized release artifact
- `dist/BatteryStats-arm64.dmg.sha256` — SHA-256 checksum for the tracked release artifact

## Release Notes

See [CHANGELOG.md](CHANGELOG.md) for the release summary for `v1.0.3`.
