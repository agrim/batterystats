# BatteryStats

BatteryStats is a native macOS battery utility for Mac laptops.

It exists for one practical reason: provide the useful battery telemetry people want from apps like Battery Health 2, but with a clean modern Swift/SwiftUI implementation that runs natively on Apple Silicon, does not require Rosetta, and stays inside the Apple ecosystem.

## Why this project exists

Older Mac battery utilities can still be useful, but on Apple Silicon they may feel dated, require Rosetta, or expose far more UI than necessary. BatteryStats is meant to be the opposite:

- native macOS
- native Apple Silicon support
- simple, readable, Apple-like UI
- no custom backend
- no separate account system
- no analytics or tracking
- no dependency on non-Apple frameworks

The goal is not to build a giant system monitor. The goal is to build the smallest useful battery app that still surfaces the battery numbers that actually matter.

## What BatteryStats should show

BatteryStats is focused on the metrics that matter most for laptop battery health and day-to-day use:

- current charge in **mAh** and **Wh**
- current charge-holding capacity / full charge capacity in **mAh** and **Wh**
- design capacity in **mAh** and **Wh**
- discharge / consumption rate in **mA**
- charge rate in **W**
- estimated time remaining at the current discharge rate
- cycle count
- manufacture date
- battery age
- temperature

A derived battery-health percentage should also be shown because it makes the “current charge-holding capacity vs design capacity” relationship easier to understand.

## Product principles

BatteryStats should feel like a small first-party Mac utility.

### 1. Native first
Use Swift, SwiftUI, IOKit, ServiceManagement, UserDefaults, and optional iCloud-backed Apple sync primitives only.

### 2. Minimal UI
No flashy dashboards. No neon colors. No fake gauges. No web views. No Electron-style chrome. No dense card wall.

### 3. Read-only utility
BatteryStats is for reading battery information, not modifying charge behavior, controlling fans, installing helpers, or asking for elevated privileges.

### 4. Honest data
If a metric cannot be read reliably on a given Mac or OS version, show **Unavailable** instead of guessing or inventing values.

### 5. Lightweight
The app should have very low idle CPU usage, very low memory usage, and should not materially impact battery life itself.

### 6. No backend
No custom auth. No account signup. No telemetry pipeline. No server. If settings sync is needed, use Apple's existing iCloud infrastructure only.

## High-level architecture

BatteryStats should stay small and use a narrow set of Apple frameworks:

- **SwiftUI** for the app UI
- **MenuBarExtra** for the menu bar surface
- **IOKit / IOKit.ps** for battery and power-source data
- **IORegistry access through public IOKit APIs** for detailed battery properties
- **UserDefaults** for local preferences
- **NSUbiquitousKeyValueStore** for optional iCloud settings sync
- **ServiceManagement / SMAppService** for optional launch-at-login
- **OSLog** for logging
- **Swift Testing / XCTest** for unit tests

## How the app should work

BatteryStats should be a small utility with three main surfaces:

### Menu bar extra
Fast glanceable summary:
- current battery percentage
- charging / on-battery state
- full charge capacity (key metric)
- quick action to open the detailed window
- refresh / settings / quit actions

### Main details window
A calm, compact battery dashboard showing the full set of core metrics.

The **current charge-holding capacity** should be visually emphasized because that is the key metric for this project.

### Settings window
A very small settings screen for:
- launch at login
- menu bar display mode
- temperature unit
- optional iCloud settings sync
- developer / debug actions if needed

## iCloud strategy

BatteryStats should not create or manage a user account.

If sync is needed, the app should use the system's iCloud account infrastructure that already exists on the Mac. For v1, that should be limited to lightweight settings sync through Apple-provided APIs rather than a custom backend or a complex CloudKit data model.

The app must still work perfectly if iCloud is unavailable or disabled.

## Privacy stance

BatteryStats should be aggressively private by design:

- no analytics
- no ad SDKs
- no third-party crash reporter
- no custom networking
- no battery data uploaded to developer-owned servers
- no contact list / calendar / photos / file-system reach
- no root privileges
- no helper daemons

If a future version adds optional sync, that sync should remain inside Apple's own iCloud infrastructure.

## Supported hardware and OS

Recommended target for v1:

- **macOS 14 or later**
- **Apple Silicon first**
- Intel support is acceptable if it comes “for free,” but Apple Silicon is the primary validation target
- Mac laptops with an internal battery are the intended hardware target

On desktop Macs or Macs where no internal notebook battery is exposed, the app should show a clean unsupported state instead of a broken UI.

## Important implementation note

The public power-source API is good for:
- charging state
- change notifications
- public time remaining info
- general battery presence / power source state

But detailed metrics like design capacity, full charge capacity, voltage, amperage, temperature, and manufacture date typically come from deeper battery properties exposed through the system power-management stack.

That means BatteryStats needs to be:
- careful about fallbacks
- honest about missing values
- resilient to OS / hardware differences
- modular in how battery properties are read and parsed

## Project scope

### MVP
- native app shell
- battery data acquisition
- menu bar extra
- main details window
- settings window
- launch-at-login toggle
- optional iCloud settings sync
- unit tests for parsing / calculations / formatting

### Explicitly not part of MVP
- fan control
- charge limiting
- battery charging overrides
- battery notifications spam
- battery history graphs
- export / CSV
- widgets
- helper tools
- privileged installs
- Sparkle or other external updater mechanisms
- non-Apple dependencies

## Current repository docs

- `README.md` — project overview
- `AGENT_INSTRUCTIONS.md` — the implementation source of truth for agentic coding

If there is a conflict between a clever idea and a smaller, safer, more native implementation, the smaller implementation should win.

## Roadmap

### Phase 1
Ship the read-only native utility:
- live metrics
- menu bar experience
- detailed window
- settings
- low overhead

### Phase 2
Improve polish:
- better unsupported / unavailable messaging
- richer formatting
- improved testing coverage
- more robust battery-state smoothing

### Phase 3
Optional additions only if still lightweight:
- local history snapshots
- Swift Charts-based history view
- optional export
- deeper iCloud sync for history if there is a real product need

## Design language

BatteryStats should feel at home next to built-in macOS apps.

Use:
- system typography
- SF Symbols
- standard materials
- subtle section grouping
- monospaced digits for changing numeric values
- clear labels and calm spacing

Avoid:
- glossy gauges
- pseudo-scientific “health scores”
- skeuomorphic battery graphics
- crowded dashboards
- custom icon packs
- custom color systems
- animation-heavy UI

## Development philosophy

Build the smallest working version first.

That means:
1. get real battery data reliably
2. make the numbers understandable
3. keep the UI clean
4. keep the app lightweight
5. only then add polish

Do not start by designing a huge preference system or a data-sync architecture. Start with the battery reader, the state model, and the UI required to display the core metrics cleanly.

## Caveats and honesty notes

Battery metrics on macOS are not always conceptually simple:

- some APIs expose percentage-oriented values rather than absolute capacity
- some metrics are derived
- current and charge-rate values can fluctuate rapidly
- optimized charging / battery-health management can affect how “full” looks at a given moment
- some keys may vary by hardware generation or OS version

BatteryStats should explain this with calm, minimal wording where useful, but never overwhelm the interface.

## Non-affiliation

BatteryStats is an independent project inspired by the usefulness of apps like Battery Health 2, but it is not affiliated with Battery Health 2, FIPLAB, or Apple.

## Repository intent

This repository is for building a serious, native, battery-focused Mac utility that feels small, clear, and trustworthy.

If you are contributing or implementing agentically, read **AGENT_INSTRUCTIONS.md** before writing code.
