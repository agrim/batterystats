# BatteryStats Agent Guide

BatteryStats is a compact, Apple-framework-only macOS battery utility. Preserve its current behavior, signed app/widget security model, and low-overhead monitoring path when changing it.

## Authority

- `project.yml` is the XcodeGen source of truth.
- Regenerate `BatteryStats.xcodeproj` after changing targets, membership, resources, bundle identifiers, or build settings.
- Do not hand-edit generated project decisions.
- Current products are the app, widget extension, and unit-test bundle.

## Product Boundaries

- Native SwiftUI/AppKit/IOKit implementation; no third-party runtime dependencies.
- No private APIs, root privileges, helper tools, or runtime shell commands.
- Unsupported hardware and unavailable telemetry must remain explicit rather than speculative.
- Keep the main window, menu bar, settings, and `systemSmall` widget compact and Apple-like.
- Preserve the shared main/menu battery surface unless a deliberate product change requires divergence.

## Code Map

- `BatteryStats/App/` — scenes, commands, runtime ownership, settings-window bridge.
- `BatteryStats/Features/Battery/Data/` — public and smart-battery readers, merge service, monitoring, history, alerts.
- `BatteryStats/Features/Battery/Domain/` — snapshot, calculations, formatting, sanitization, power state, manufacture date.
- `BatteryStats/Features/Battery/Presentation/` — dashboard, menu bar, summary, freshness, unsupported state.
- `BatteryStats/Settings/` — preferences, iCloud sync, refresh policy, alerts, history, launch at login, units.
- `BatteryStats/Shared/` — cross-surface utilities and the app/widget snapshot store.
- `BatteryStatsWidgets/` — WidgetKit provider and four-ring presentation.
- `Tests/BatteryStatsTests/` — behavior, persistence, project, entitlement, source-contract, and release regressions.
- `script/` — build, install, signed-product verification, widget verification, and release packaging.

## Runtime Data Flow

1. `PowerSourceReader` reads public IOKit power-source state and notifications.
2. `SmartBatteryReader` reads `AppleSmartBattery` telemetry.
3. `BatteryReadingService` reconciles both sources into one `BatterySnapshot`.
4. `BatteryMonitor` publishes app state, refreshes surfaces, records optional history, evaluates optional alerts, and writes the widget snapshot.

Keep these behaviors stable:

- Prefer a valid system remaining-time estimate.
- Use a custom discharge estimate only after recent, timestamped samples satisfy confidence checks.
- Reset confidence across wake, stop/restart, large gaps, and power-state discontinuities.
- Retain the last valid snapshot through brief read failures, then retry before declaring unsupported hardware.
- Keep adapter capability, live input power, battery charge rate, and battery discharge rate semantically separate.
- Keep monitoring work bounded; avoid extra IOKit reads, timers, allocations, logging, or widget reloads on hot paths.

## Widget Contract

- The widget reads only app-published snapshots; it does not access live IOKit readers.
- The app and widget share `Q293G85PG5.io.github.agrim.batterystats`.
- Keep timeline entries at least five minutes apart.
- Retain a valid last-known snapshot for up to six hours and show stale state honestly.
- Preserve the four rings: health, charge, time, and power state.
- Ordinary reloads are coalesced; critical availability, power-state, and battery-band changes may reload immediately.

## Identity And Entitlements

- App: `io.github.agrim.batterystats`
- Widget: `io.github.agrim.batterystats.widgets`
- Tests: `io.github.agrim.batterystats.tests`
- App Group: `Q293G85PG5.io.github.agrim.batterystats`

Both signed products require sandboxing and the same App Group. The entitlement files are intentionally not identical: the app alone carries the iCloud key-value-store entitlement.

## Persistence And Settings

- `PreferencesStore` owns persisted app preferences.
- iCloud preference/history sync remains optional and availability-gated.
- History is opt-in, capped, compact, and separated into battery-drain, battery-charge, and adapter-input roles.
- History averages are time-weighted and must not bridge sleep or app-off gaps.
- Alerts are opt-in, threshold-based, and suppress repeated delivery while a condition remains active.
- Launch-at-login state comes from `SMAppService`; do not create a second persisted truth for it.

## Build And Test

Generate the project:

```bash
xcodegen generate
```

Run the full suite:

```bash
./script/build_and_run.sh test
```

Signed debug run or install:

```bash
BATTERYSTATS_ALLOW_PROVISIONING_UPDATES=1 ./script/build_and_run.sh
BATTERYSTATS_ALLOW_PROVISIONING_UPDATES=1 ./script/build_and_run.sh install
```

Unsigned mode is compile/test fallback only:

```bash
BATTERYSTATS_SIGNING_MODE=unsigned ./script/build_and_run.sh test
```

Do not use unsigned output as proof of WidgetKit, App Groups, iCloud KVS, launch at login, signing, or installation behavior.

## Release Contract

- Read `RELEASE_STATUS.md` for dated version, artifact, and public-download state; verify every external fact live before use.
- `BatteryStats/Resources/IconLayers/AppIcon.icon` is the complete editable Icon Composer source, including its layer assets.
- `dist/BatteryStats-arm64.dmg` and its checksum are the tracked notarized reference artifact.
- `script/package_release.sh` creates a versioned candidate; publishing or replacing the tracked artifact is separate.

Release validation must keep these as separate facts:

- app and nested-widget signatures;
- effective signed entitlements;
- embedded profile authorization for iCloud KVS;
- arm64 architecture and coherent app/widget versions;
- hardened runtime and absence of embedded `.xctest` bundles;
- Developer ID authority and trusted timestamp when required;
- notarization, stapling, Gatekeeper, packaging, installation, launch, and active-widget registration.

Never claim an unverified gate. Do not sign, notarize, install, publish, or replace artifacts unless the task authorizes that external action.

## Change Discipline

- Read the relevant implementation and regression tests before editing.
- Prefer small equivalent reductions over rewrites.
- Preserve explicit conflicting/malformed telemetry cases in tests; fixture defaults must not hide them.
- Keep Codable migration fixtures literal when missing versus `null` fields matter.
- After project/resource changes, regenerate and inspect the project diff before debugging source.
- Finish with focused tests, the full suite, signed-product verification where applicable, and `git diff --check`.
