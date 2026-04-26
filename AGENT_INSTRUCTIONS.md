# BatteryStats Agent Guide

This file is technical documentation for LLM agents working in the BatteryStats repository. It describes what the app currently does, how the code is organized, and how to safely modify and release it.

## Product Snapshot

BatteryStats is a small native macOS battery utility for Apple Silicon Mac laptops. The repo currently ships:

- a main SwiftUI window
- a menu bar extra
- a settings window
- a `systemSmall` widget extension
- a Developer ID signed and notarized Apple-Silicon DMG release artifact

The app is intentionally compact. It is not a hardware-control tool, fan controller, charging limiter, or general-purpose system monitor.

## Key User-Facing Features

- Health summary: full-charge capacity vs design capacity
- Charge summary: current charge vs full-charge capacity
- Time summary: time left on battery or time to full while charging
- Status summary: charging / plugged in / on battery
- Charge cycle count
- Temperature
- Menu bar display modes
- Launch at login
- Optional iCloud-backed preference sync
- Configurable or dynamic refresh cadence with energy-shift probing
- Optional local alerts for low battery, charge complete, and high temperature
- Optional local battery history with iCloud key-value sync when enabled
- Copy raw and parsed battery snapshots for debugging
- Widget with four circular battery indicators and a labeled medium layout

## Architecture

### App Entry

- `Platforms/macOS/App/App/BatteryStatsApp.swift`

Creates three scenes:

- `WindowGroup("BatteryStats", id: "main")`
- `MenuBarExtra`
- `Settings`

`BatteryMonitor` and `PreferencesStore` are created once at app launch and injected into these surfaces.

### Battery Data Flow

Runtime battery data flows through:

1. `PowerSourceReader`
   - File: `Platforms/macOS/App/Features/Battery/Data/PowerSourceReader.swift`
   - Uses `IOKit.ps`
   - Reads public power-source state and registers change notifications

2. `SmartBatteryReader`
   - File: `Platforms/macOS/App/Features/Battery/Data/SmartBatteryReader.swift`
   - Reads `AppleSmartBattery` properties through IOKit
   - Provides deeper fields like capacities, signed current, cycle count, manufacture date, and temperature

3. `BatteryReadingService`
   - File: `Platforms/macOS/App/Features/Battery/Data/BatteryReadingService.swift`
   - Merges public and smart-battery reads into one `BatterySnapshot`
   - Computes derived values and fallback notes

4. `BatteryMonitor`
   - File: `Platforms/macOS/App/Features/Battery/Data/BatteryMonitor.swift`
   - Owns refresh cadence and app-facing state
   - Refreshes on:
     - app start
     - power-source notification callbacks
     - wake from sleep
     - app activation
     - the selected fixed timer or the dynamic cadence from `BatteryRefreshPolicy`
     - an energy-shift probe when the selected cadence is slower than the probe interval
   - Smooths discharge samples before computing a rate-based remaining time
   - Records history and evaluates alert policy after published refreshes

### Shared Battery Core

- `Shared/BatteryCore/Domain/BatterySnapshot.swift`
- `Shared/BatteryCore/Domain/BatteryCalculations.swift`
- `Shared/BatteryCore/Domain/BatteryFormatting.swift`
- `Shared/BatteryCore/Domain/BatteryPowerState.swift`
- `Shared/BatteryCore/Domain/ManufactureDateDecoder.swift`
- `Shared/BatteryCore/Policies/BatteryAlertPolicy.swift`
- `Shared/BatteryCore/Policies/RefreshCadencePreference.swift`
- `Shared/BatteryCore/Settings/TemperatureUnitPreference.swift`

`BatterySnapshot` is the central view model for both the app UI and the widget. Keep it stable and additive where possible.

Important computed fields:

- `displayedTimeMinutes`
- `statusDisplayTitle`
- `healthTone`
- `chargeTone`
- `batterySymbolName`

### Presentation

- `Platforms/macOS/App/Features/Battery/Presentation/BatteryDashboardView.swift`
- `Platforms/macOS/App/Features/Battery/Presentation/BatterySummaryGridView.swift`
- `Platforms/macOS/App/Features/Battery/Presentation/MenuBarBatteryView.swift`
- `Platforms/macOS/App/Features/Battery/Presentation/UnsupportedBatteryView.swift`

The main window and the menu bar extra deliberately share `BatterySurfaceView` so the compact battery summary stays consistent across surfaces.

### Settings

- `Platforms/macOS/App/Settings/PreferencesStore.swift`
- `Platforms/macOS/App/Settings/SettingsView.swift`
- `Platforms/macOS/App/Settings/LaunchAtLoginManager.swift`
- `Shared/BatteryCore/Policies/RefreshCadencePreference.swift`
- `Shared/BatteryCore/Policies/BatteryAlertPolicy.swift`
- `Shared/BatteryCore/Settings/TemperatureUnitPreference.swift`
- `Shared/Support/Settings/ICloudPreferencesSync.swift`

`PreferencesStore` is the single source of truth for user-configurable settings.

Persisted preferences:

- `launchAtLoginEnabled`
- `menuBarDisplayMode`
- `temperatureUnitPreference`
- `showAdvancedValues`
- `isICloudSyncEnabled`
- `refreshCadencePreference`
- `energyChangeSensitivity`
- alert toggles
- history toggles

### History And Alerts

- `Platforms/macOS/App/Features/Battery/Data/BatteryHistoryStore.swift`
- `Platforms/macOS/App/Features/Battery/Data/BatteryAlertCoordinator.swift`

History is opt-in and keeps a capped local set of lightweight samples. If history iCloud sync is enabled, it mirrors the compact encoded sample set through `NSUbiquitousKeyValueStore`; avoid large or high-frequency payloads.

Alerts are opt-in local notifications. Keep them threshold-based and avoid repeated notifications while the same condition remains active.

### Widget

- `Platforms/macOS/Widgets/BatteryStatusWidget.swift`
- `Platforms/macOS/Widgets/BatteryStatusWidgetView.swift`

Current widget behavior:

- families: `systemSmall`, `systemMedium`
- refresh cadence: roughly every 5 minutes
- metric rings:
  - health
  - charge
  - time
  - power state

The small widget keeps symbol-centered rings. The medium widget can use labels and text values.

The widget reads battery state through `BatteryReadingService` and reuses shared battery domain and data files directly.

## Multi-Device Work

All iOS, iPadOS, and watchOS exploration belongs on the `multi-device` branch. Keep `main` focused on the shipping macOS release line until a multi-device target is ready to merge.

Repository lanes:

- `Platforms/macOS/App/` keeps the current Mac app and Mac-only IOKit readers
- `Platforms/macOS/Widgets/` keeps the current macOS WidgetKit extension
- `Platforms/iOS/App/` is reserved for the future universal iPhone app target
- `Platforms/iPadOS/` is reserved for iPad-specific presentation, navigation, and pointer/keyboard behavior
- `Platforms/watchOS/App/` is reserved for the future watch app shell
- `Platforms/watchOS/Extension/` is reserved for watch runtime code, complications, and WatchConnectivity integration
- `Shared/BatteryCore/` is the cross-platform model/calculation/policy surface
- `Shared/Support/` is reusable Apple-platform support that each target must opt into deliberately

When adding a new platform target, define it in `project.yml`, regenerate with `xcodegen generate`, and keep platform-only APIs outside `Shared/BatteryCore`.

## Design Constraints

Keep these stable unless there is a strong product reason to change them:

- Prefer Apple frameworks only
- No shelling out at runtime to `ioreg`, `pmset`, or `system_profiler`
- No private APIs
- No root privileges or helper tools
- No large dashboard redesign without explicit user direction
- No speculative values when hardware data is unavailable
- Keep the UI compact and Apple-like

## Project Generation

The Xcode project is generated from:

- `project.yml`

After changing targets, resources, or bundle identifiers, regenerate:

```bash
xcodegen generate
```

Do not treat manual edits to `BatteryStats.xcodeproj/project.pbxproj` as the source of truth when the same change belongs in `project.yml`.

## Bundle Identifiers

Current bundle identifiers:

- app: `io.github.agrim.batterystats`
- widget: `io.github.agrim.batterystats.widgets`
- tests: `io.github.agrim.batterystats.tests`

If these change, keep `project.yml`, generated project output, logging fallbacks, and any release docs aligned.

## Build And Test

Debug run:

```bash
./script/build_and_run.sh
```

Release build:

```bash
xcodebuild -project BatteryStats.xcodeproj -scheme BatteryStats -configuration Release -derivedDataPath .build/DerivedDataRelease build
```

Tests:

```bash
xcodebuild -project BatteryStats.xcodeproj -scheme BatteryStatsTests test
```

Current test coverage is focused on battery math and parsing:

- `BatteryCalculationsTests.swift`
- `FormatterTests.swift`
- `ManufactureDateDecoderTests.swift`
- `RefreshPolicyTests.swift`
- `SmartBatteryParsingTests.swift`

## Release Artifacts

- Tracked DMG: `dist/BatteryStats-arm64.dmg`
- Tracked checksum: `dist/BatteryStats-arm64.dmg.sha256`
- Saved app icon source: `Platforms/macOS/App/Resources/IconLayers/AppIcon.icon`

The app icon is authored in Icon Composer and stored as a `.icon` package. The raw editable layer PNGs live in `Platforms/macOS/App/Resources/IconLayers/`, but they are excluded from the app target so they do not ship inside the final app bundle.

## Packaging Notes

Current release packaging approach:

1. Build the release app with Developer ID settings
2. Verify signatures, hardened runtime, and nested widget signing
3. Copy the app plus an `Applications` alias into a staging folder
4. Create `dist/BatteryStats-arm64.dmg` with `hdiutil`
5. Sign the DMG with the Developer ID Application identity
6. Submit the DMG with `xcrun notarytool submit --wait`
7. Staple and validate the ticket with `xcrun stapler`
8. Publish `dist/BatteryStats-arm64.dmg.sha256` beside the DMG

The DMG currently targets Apple Silicon release builds.

## Notarization

Notarization requires:

- a valid `Developer ID Application` signing identity in the local keychain
- Apple notarization credentials for `notarytool`

If the machine only has `Sign to Run Locally` or no valid signing identities, you cannot complete notarization from this repo alone.

Current maintainer-machine status during the `v1.0.3` release pass:

- Developer ID Application identity exists for team `Q293G85PG5`
- `notarytool` profile `BatteryStats` is stored in Keychain
- `dist/BatteryStats-arm64.dmg` is Developer ID signed, notarized, and stapled
- `spctl -a -t open --context context:primary-signature -vv dist/BatteryStats-arm64.dmg` should report `accepted`

## Practical Agent Guidance

- Read the shared battery domain and data files before changing UI behavior
- Keep `BatterySurfaceView` shared between the main window and menu bar unless there is a deliberate divergence
- Preserve widget access to shared battery code
- When changing resources or targets, regenerate the project
- When changing release packaging, validate the built bundle contents and `codesign --verify --deep --strict`
- Prefer small, deliberate edits over broad architectural churn
