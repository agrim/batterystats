# Changelog

## v1.0.4 (unreleased)

Correctness, WidgetKit, and macOS 27 productization pass.

- Prefer the valid system remaining-time estimate and confidence-gate the custom discharge fallback
- Reset timestamped discharge smoothing across wake, lifecycle, large-gap, and power-state discontinuities
- Support confidence accumulation at the slowest five-minute cadence without resetting on routine power-source notifications
- Retain the latest good snapshot across transient battery-read gaps and retry before declaring the battery unsupported
- Preserve reported charging top-off time instead of forcing a false zero-minute result
- Stop deriving full-charge and design Wh from instantaneous voltage; keep only current charge as an estimate
- Project countdown entries at a WidgetKit-friendly cadence, with precise hour/minute text
- Keep retained last-known widget data visible for up to six hours and reserve the unavailable state for missing, invalid, cleared, or expired snapshots
- Hard-coalesce ordinary widget reloads while immediately publishing critical availability and power-state changes
- Remove the redundant `systemMedium` widget family and keep the focused four-ring `systemSmall` layout
- Split history power by measurement role and use time-weighted averages for irregular samples
- Exclude sleep and app-off gaps from time-weighted history power calculations
- Move app/widget sharing to a Team-ID-prefixed macOS App Group
- Add automatic signing, effective-entitlement/profile checks, active-widget verification, and a reproducible Developer ID/notarization script
- Remove live IOKit reader code from the widget target so the extension has one snapshot-only data path
- Isolate test DerivedData and PluginKit registrations from runtime products, and reject signed app bundles that accidentally contain an `.xctest` plug-in
- Clean up isolated test preference suites after every test to prevent plist accumulation

## v1.0.3

Repository presentation and release metadata cleanup.

- Cleaned the GitHub file-list commit descriptions through the v1.0.3 release commit
- Added an app version readout in Settings
- Added a widget bundle info string for release metadata consistency
- Added explicit help handling to the build/run script
- Rebuilt, Developer ID signed, notarized, stapled, and validated the Apple-Silicon DMG

## v1.0.2

Distribution metadata correction.

- Rebuilt the notarized DMG with the app bundle version set to `1.0.2`
- Kept the same v1.0.1 app functionality and release checks
- Supersedes v1.0.1, whose release artifact was notarized but still reported app version `1.0`

## v1.0.1

Distribution and usability update.

- Developer ID signed, Apple-notarized, and stapled Apple-Silicon DMG
- Published SHA-256 checksum for the release DMG
- Configurable refresh cadence with a dynamic mode
- Out-of-cycle refreshes when energy consumption changes by a large amount
- Menu bar remaining-time display
- Optional local battery history with Settings summary
- Optional low-battery, charge-complete, and high-temperature alerts
- `systemMedium` Battery Circles widget with labels
- Small widget polish for compact remaining-time display

## v1.0

Initial public release of BatteryStats.

- Native macOS battery utility built with SwiftUI and Apple frameworks
- Main battery window with health, charge, time, status, cycle count, and temperature
- Menu bar extra with configurable display modes
- Launch at login support
- Optional iCloud preference sync
- System small widget extension
- Icon Composer app icon integrated into the release build
- Apple-Silicon DMG packaging
