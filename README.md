# BatteryStats

BatteryStats is a native macOS battery utility for Apple Silicon Mac laptops. It gives you a compact battery dashboard, a menu bar view, a settings window, and a small widget without bringing in non-Apple dependencies, Rosetta, or a backend.

[Download `BatteryStats-arm64.dmg`](https://github.com/agrim/batterystats/releases/download/v1.0/BatteryStats-arm64.dmg)

## What Ships In v1.0

- Native macOS app built with SwiftUI and Apple frameworks only
- Apple-Silicon-first DMG release
- Compact battery window with health, charge, time, status, cycle count, and temperature
- Menu bar extra with multiple display modes
- Launch at login support through `SMAppService`
- Optional iCloud preference sync through `NSUbiquitousKeyValueStore`
- System small widget with four circular battery indicators
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

Opening the menu bar extra shows the same compact battery surface used by the main window.

### Settings

The settings window supports:

- launch at login
- iCloud preference sync
- menu bar display mode
- temperature unit
- advanced value toggle
- copy raw snapshot
- copy parsed snapshot
- reset settings

### Widget

The widget is a `systemSmall` widget named **Battery Circles**. It shows:

- health ring
- charge ring
- time ring
- power-state ring

## Platform Notes

- Intended for Mac laptops with an internal battery
- Best experience on Apple Silicon
- The DMG published here is arm64 only
- The current public DMG is locally signed but not Apple-notarized yet
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

- `BatteryStats/` — main app source
- `BatteryStatsWidgets/` — widget extension
- `Tests/BatteryStatsTests/` — unit tests
- `BatteryStats/Resources/IconLayers/AppIcon.icon` — saved Icon Composer app icon source
- `dist/BatteryStats-arm64.dmg` — tracked release artifact

## Release Notes

See [CHANGELOG.md](CHANGELOG.md) for the release summary for `v1.0`.
