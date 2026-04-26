# Changelog

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
