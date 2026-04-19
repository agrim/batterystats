# AGENT_INSTRUCTIONS.md

This file is the implementation source of truth for Codex when building **BatteryStats**.

The mission is to build a small native macOS battery utility that feels like a clean built-in Mac app, runs natively on Apple Silicon, uses only Apple technologies, and exposes the battery metrics that matter most.

If there is ever a tradeoff between:
- doing something fancy, and
- shipping a smaller, safer, more native, more reliable utility

choose the smaller / safer / more native option.

---

## 1. Product mission

Build a native macOS app called **BatteryStats** with functionality similar to Battery Health 2, focused on these metrics:

- current charge in mAh and Wh
- current charge-holding capacity (full charge capacity) in mAh and Wh
- design capacity in mAh and Wh
- discharge / consumption rate in mA
- charge rate in W
- estimated time remaining at the current discharge rate
- cycle count
- manufacture date
- battery age
- temperature

The UI must be simple, minimal, and feel Apple-native.

The app must:
- run natively on Apple Silicon without Rosetta
- use Apple frameworks only
- require no custom backend
- require no separate account creation
- optionally integrate with the user's iCloud account only through Apple-provided infrastructure
- never pretend a value exists when the system did not provide it

---

## 2. Non-negotiable rules

### 2.1 Technology rules
Use only Apple technologies:
- Swift
- SwiftUI
- IOKit / IOKit.ps
- Foundation
- Observation
- ServiceManagement
- OSLog
- UserDefaults
- NSUbiquitousKeyValueStore
- Swift Testing / XCTest
- Swift Charts only if a future local-history feature is added

Do **not** use:
- CocoaPods
- Carthage
- third-party SPM packages
- Electron
- React Native
- web views for core UI
- Python
- Node
- external daemons
- external databases
- external telemetry or analytics SDKs
- Sparkle or other external updaters for the shipping product

### 2.2 Runtime rules
Do **not** shell out at runtime to:
- `ioreg`
- `pmset`
- `system_profiler`
- any other command line tool

Use public Apple APIs directly.

Manual shell commands are acceptable for development-time inspection only, never as part of the shipping app path.

### 2.3 Security / policy rules
Do **not**:
- request root privileges
- use private frameworks
- use private selectors
- use undocumented entitlements
- install helper tools outside standard Apple mechanisms
- run at login without explicit user consent
- add background behavior unrelated to the app's purpose
- create a custom auth system

### 2.4 UX rules
Do:
- keep the UI spare and quiet
- use system typography and SF Symbols
- prefer grouped native sections over dashboard clutter
- show “Unavailable” when needed
- emphasize the full charge capacity metric because it is the key value for this project

Do **not**:
- create a giant monitoring dashboard
- fill the UI with flashy cards or graphs in MVP
- invent a vague “score”
- use loud colors to signal normal states
- overload the menu bar with too much text

---

## 3. Product definition

### 3.1 What BatteryStats is
BatteryStats is a read-only battery telemetry utility for Mac laptops.

### 3.2 What BatteryStats is not
BatteryStats is **not**:
- a fan controller
- a charge limiter
- a battery optimizer
- a battery repair tool
- a system-wide hardware monitor
- a power-tuning tool
- an admin utility
- a diagnostics suite
- an account-based SaaS product

### 3.3 Target user
The target user is someone who wants a native Mac app that gives clear battery numbers without Rosetta, clutter, or external infrastructure.

### 3.4 Primary success metric
The app successfully and clearly surfaces the user's **current full charge capacity / current charge-holding capacity**, since that is the core value the product exists to expose.

---

## 4. Recommended platform target

For v1:

- deployment target: **macOS 14 or later**
- language: Swift
- UI: SwiftUI
- observation model: `@Observable` / Observation framework
- distribution goal: App Store-friendly native macOS app

Notes:
- Apple Silicon is the primary validation target.
- It is fine if the build is universal, as long as Apple Silicon includes a native arm64 slice and does not require Rosetta.
- Do not spend time on Intel-specific polishing unless it is trivial.

---

## 5. Shipping surfaces

BatteryStats should ship with these surfaces:

### 5.1 Main details window
A simple, compact detailed view of all key metrics.

### 5.2 Menu bar extra
A glanceable menu bar entry that exposes:
- battery state
- battery percentage
- a short summary
- quick access to the main window
- refresh / settings / quit

### 5.3 Settings window
A small settings screen for:
- launch at login
- menu bar display mode
- temperature unit
- optional iCloud settings sync
- developer debug actions if useful

### 5.4 Unsupported state
If the Mac does not expose an internal notebook battery, show a clean unsupported state instead of empty values.

---

## 6. MVP scope

The MVP includes:

1. reliable battery reading
2. metric calculation and formatting
3. main details window
4. menu bar extra
5. settings window
6. launch-at-login toggle
7. optional iCloud-backed preference sync
8. unit tests for parsing and formulas
9. graceful fallback behavior

The MVP does **not** include:
- history graphs
- export
- notifications
- widgets
- hardware control
- battery charging control
- desktop support beyond an unsupported-state message

---

## 7. Architecture overview

Keep the architecture simple and modular.

Recommended layers:

### 7.1 Domain
Pure types and calculations:
- `BatterySnapshot`
- `BatteryPowerState`
- `BatteryMetricAvailability`
- calculation helpers
- formatters
- manufacture-date decoder

### 7.2 Data access
Concrete readers:
- power-source reader using `IOKit.ps`
- detailed battery reader using `IORegistry` and `AppleSmartBattery`
- settings store
- iCloud settings sync wrapper

### 7.3 App state / orchestration
A small observable store or monitor object that:
- listens for battery changes
- merges public and detailed battery data
- computes derived metrics
- exposes state for the UI
- owns refresh cadence

### 7.4 Presentation
SwiftUI views only:
- menu bar view
- main dashboard view
- settings view
- unsupported / unavailable views

### 7.5 Testing
Unit tests around:
- parsing
- signed current conversion
- manufacture date decoding
- health and time formulas
- formatting

Do not over-abstract. No protocol explosion. No 40 tiny files for trivial wrappers.

---

## 8. Recommended file / folder layout

Keep the project understandable.

Suggested structure:

```text
BatteryStats/
  App/
    BatteryStatsApp.swift
    AppCommands.swift

  Features/
    Battery/
      Domain/
        BatterySnapshot.swift
        BatteryPowerState.swift
        BatteryCalculations.swift
        BatteryFormatting.swift
        ManufactureDateDecoder.swift
      Data/
        PowerSourceReader.swift
        SmartBatteryReader.swift
        BatteryReadingService.swift
      Presentation/
        BatteryDashboardView.swift
        BatterySectionView.swift
        MetricRowView.swift
        UnsupportedBatteryView.swift
        MenuBarBatteryView.swift

    Settings/
      PreferencesStore.swift
      ICloudPreferencesSync.swift
      SettingsView.swift

  Shared/
    Logging/
      Logger+BatteryStats.swift
    Utilities/
      NSNumber+SignedConversions.swift
      DateComponentsFormatter+BatteryStats.swift

  Tests/
    BatteryStatsTests/
      ManufactureDateDecoderTests.swift
      BatteryCalculationsTests.swift
      SmartBatteryParsingTests.swift
      FormatterTests.swift
```

This is a suggestion, not a prison. Keep the source tree compact.

---

## 9. Battery data acquisition strategy

Use **two Apple-provided paths**.

### 9.1 Public power-source path: `IOKit.ps`
Use this path for:
- power-source presence
- charging state
- battery vs AC state
- public time-to-empty / time-to-full values
- change notifications
- high-level current percentage if needed
- system-provided time remaining estimate

Primary APIs:
- `IOPSCopyPowerSourcesInfo`
- `IOPSCopyPowerSourcesList`
- `IOPSGetPowerSourceDescription`
- `IOPSNotificationCreateRunLoopSource`
- `IOPSGetTimeRemainingEstimate`

Reason:
- stable
- public
- event-friendly
- appropriate for change notifications

Important limitation:
- Apple-defined power sources often expose the public current/max capacity keys in percentage-oriented units.
- Therefore: do **not** rely on the public path for absolute mAh design/full/current capacity values.

### 9.2 Detailed battery path: `IORegistry` / `AppleSmartBattery`
Use this path for detailed notebook battery properties.

Primary APIs:
- `IOServiceMatching("AppleSmartBattery")`
- `IOServiceGetMatchingService`
- `IORegistryEntryCreateCFProperties`
- `IORegistryEntryCreateCFProperty`
- `IOObjectRelease`

Reason:
- detailed metrics like design capacity, full charge capacity, voltage, amperage, temperature, and manufacture date typically live here

Important honesty rule:
- the **API surface** used to read the registry is public IOKit
- some **property names** are not guaranteed to be formally documented for every hardware generation
- therefore the implementation must be robust, fallback-friendly, and isolated in one reader

Never spread raw registry-key parsing all over the codebase.

---

## 10. Battery fields to read

Treat registry keys as best-effort and always allow missing values.

### 10.1 Primary registry fields

Use the following preferred read order.

| Product field | Preferred source order | Notes |
|---|---|---|
| current charge (mAh) | `AppleRawCurrentCapacity` → `CurrentCapacity` | if missing, derive from percent × full charge capacity if possible |
| current charge-holding capacity / full charge capacity (mAh) | `AppleRawMaxCapacity` → `NominalChargeCapacity` → `MaxCapacity` | this is the key metric |
| design capacity (mAh) | `DesignCapacity` | factory design capacity |
| cycle count | `CycleCount` → `LegacyBatteryInfo["Cycle Count"]` | integer |
| voltage (mV) | `Voltage` → `BatteryData["Voltage"]` → `LegacyBatteryInfo["Voltage"]` | used for power / Wh derivation |
| current / amperage (mA, signed) | `InstantAmperage` → `LegacyBatteryInfo["Amperage"]` → `Amperage` | must normalize signed values carefully |
| temperature (raw) | `Temperature` | convert to °C using validated logic |
| manufacture date (raw) | `ManufactureDate` | decode packed date |
| adapter max watts | `AdapterDetails["Watts"]` → first entry of `AppleRawAdapterDetails` if present | metadata only, not actual battery charge power |
| adapter current / voltage | `AdapterDetails["Current"]`, `AdapterDetails["Voltage"]` | optional advanced data, not required for MVP UI |

### 10.2 Public power-source fields

Use public description dictionary values for:
- charging boolean
- whether current source is battery or AC
- public time-to-empty / time-to-full
- public percentage if needed
- user-facing power source state

Expected keys include:
- `kIOPSCurrentCapacityKey`
- `kIOPSMaxCapacityKey`
- `kIOPSIsChargingKey`
- `kIOPSTimeToEmptyKey`
- `kIOPSTimeToFullChargeKey`
- `kIOPSPowerSourceStateKey`

Do not confuse these public percentage-style values with the detailed mAh capacities from the registry path.

---

## 11. Core domain model

Create a single unified snapshot type that the UI consumes.

Suggested shape:

```swift
struct BatterySnapshot: Equatable, Sendable {
    let timestamp: Date

    // state
    let powerState: BatteryPowerState
    let isCharging: Bool
    let isExternalPowerConnected: Bool

    // capacities
    let currentChargeMilliampHours: Int?
    let currentChargeWattHours: Double?
    let fullChargeCapacityMilliampHours: Int?
    let fullChargeCapacityWattHours: Double?
    let designCapacityMilliampHours: Int?
    let designCapacityWattHours: Double?
    let healthPercent: Double?
    let stateOfChargePercent: Double?

    // electrical
    let voltageMillivolts: Int?
    let currentMilliampsSigned: Int?
    let dischargeRateMilliamps: Int?
    let chargeRateWatts: Double?
    let dischargeRateWatts: Double?

    // time
    let rateBasedTimeRemainingMinutes: Int?
    let systemTimeRemainingMinutes: Int?
    let timeToFullMinutes: Int?

    // lifecycle
    let cycleCount: Int?
    let manufactureDate: Date?
    let batteryAgeComponents: DateComponents?
    let temperatureCelsius: Double?

    // diagnostics
    let adapterMaxWatts: Int?
    let notes: [String]
}
```

You do not need this exact code, but the UI should receive one clean merged snapshot, not a mix of raw dictionaries.

---

## 12. Derived metric rules

### 12.1 State of charge %
Preferred formula:

```text
stateOfChargePercent = currentChargeMilliampHours / fullChargeCapacityMilliampHours * 100
```

Fallback:
- if absolute current/full capacities are unavailable, derive from public power-source percentage keys
- clamp to `0...100` only for display, not for internal debugging

### 12.2 Health %
Use:

```text
healthPercent = fullChargeCapacityMilliampHours / designCapacityMilliampHours * 100
```

Display with one decimal place or whole number depending on final formatting style.
Do not call this Apple's official “battery condition.” It is a derived ratio.

### 12.3 Current charge (Wh)
If current charge in mAh and pack voltage in mV are available:

```text
currentChargeWh = currentChargeMilliampHours * voltageMillivolts / 1_000_000
```

### 12.4 Full charge capacity (Wh)
Preferred:
- if a pack design / nominal voltage is exposed, use it
- otherwise fall back to current pack voltage and mark the value as derived / approximate in code comments and, if needed, advanced UI help

Formula:

```text
fullChargeCapacityWh = fullChargeCapacityMilliampHours * voltageBasisMillivolts / 1_000_000
```

### 12.5 Design capacity (Wh)
Same rule as above:

```text
designCapacityWh = designCapacityMilliampHours * voltageBasisMillivolts / 1_000_000
```

Important:
- if nominal / design voltage is not reliably available, Wh values are derived estimates
- do not fake certainty
- keep the UI calm; do not add alarming warnings simply because Wh is approximate

### 12.6 Discharge rate (mA)
If signed current is negative:

```text
dischargeRateMilliamps = abs(currentMilliampsSigned)
```

Otherwise `nil` or `0` depending on display choice. Prefer `nil` and show em dash when not discharging.

### 12.7 Charge rate (W)
If signed current is positive:

```text
chargeRateWatts = voltageMillivolts * currentMilliampsSigned / 1_000_000
```

Important:
- this is actual battery charge power
- do **not** substitute adapter max-watt metadata for actual charge rate

### 12.8 Optional discharge power (W)
Useful internally and maybe for future UI:

```text
dischargeRateWatts = voltageMillivolts * abs(currentMilliampsSigned) / 1_000_000
```

### 12.9 Estimated time remaining at current discharge rate
User explicitly wants a rate-based estimate.

Preferred formula:

```text
timeRemainingHours = currentChargeMilliampHours / abs(smoothedDischargeMilliamps)
timeRemainingMinutes = timeRemainingHours * 60
```

Rules:
- only compute when currently discharging
- if current is `0`, near `0`, or positive, return `nil`
- use a smoothed current value if possible to reduce jitter
- if not enough samples exist yet, use instantaneous discharge current
- if the resulting value is absurd because current is tiny, return `nil`

Recommended smoothing:
- keep a short in-memory ring buffer of the most recent 5 to 8 discharge-current samples
- smooth only for the time estimate, not for the raw displayed current

### 12.10 Battery age
If manufacture date exists:

```text
age = Calendar.current.dateComponents([.year, .month, .day], from: manufactureDate, to: now)
```

Display:
- preferred: `2y 3m`
- fallback: `—`

---

## 13. Signed current conversion rules

This is important.

Battery current can sometimes show up as a giant positive unsigned value even though it semantically represents a negative signed current.

Examples exist where `InstantAmperage` behaves like a two's-complement signed integer encoded in an unsigned container.

Implementation rule:
- when reading a current-like field, normalize it to a signed integer intentionally
- do not assume the raw numeric bridge always gives you a correct `Int`

Recommended helper logic:
1. if the value bridges cleanly as `NSNumber`, use its signed integer value
2. if it appears as `UInt64`, reinterpret with `Int64(bitPattern:)`
3. if it appears as a decimal string from a fixture, parse then reinterpret if needed

Write unit tests for this.

Example intent:
- `18446744073709549095` should become `-2521`

---

## 14. Manufacture date decoding rules

Use the smart-battery packed-date format.

Decode as:

```text
day   = raw & 0x1F
month = (raw >> 5) & 0x0F
year  = 1980 + ((raw >> 9) & 0x7F)
```

Validation rules:
- month must be `1...12`
- day must be `1...31`
- resulting date must successfully build with `Calendar`
- otherwise return `nil`

Do not infer manufacture date from battery serial-number heuristics in MVP.
If `ManufactureDate` is unavailable, show `Unavailable`.

Write tests with real captured examples.

---

## 15. Temperature conversion rules

This is a known ambiguity area, so code defensively.

Many existing Mac battery tools and examples divide the raw `Temperature` value by `100` to get °C.
However, older smart-battery specs describe battery temperature in tenths of Kelvin.

Implementation rule:
- start with the conversion that validates best against real Mac output on the target hardware
- default to `raw / 100.0` °C for AppleSmartBattery unless real-world validation proves otherwise on the test machine
- add a sanity-check fallback if needed

Recommended helper:
1. compute `candidateC1 = raw / 100.0`
2. if `candidateC1` is in a plausible laptop-battery range (for example `-20...120`), accept it
3. otherwise try `candidateC2 = raw / 10.0 - 273.15`
4. if that is plausible, accept it
5. otherwise still return `candidateC1` but log a debug note

Important:
- keep this uncertainty isolated in one function
- add a comment explaining why
- verify manually on the Apple Silicon test machine

---

## 16. Power state model

Create a simple explicit state enum.

Suggested shape:

```swift
enum BatteryPowerState {
    case onBattery
    case charging
    case connectedNotCharging
    case fullOnAC
    case unknown
}
```

Derive from:
- public charging boolean
- public power-source state
- signed current
- full / current capacity relationship if helpful

Do not over-complicate this. The UI only needs enough state to label the situation clearly.

Recommended user-facing labels:
- `On Battery`
- `Charging`
- `Connected, Not Charging`
- `Fully Charged`
- `Unknown`

---

## 17. Refresh strategy

The app must stay lightweight.

### 17.1 Primary update path
Use `IOPSNotificationCreateRunLoopSource` to receive power-source change notifications.

### 17.2 Secondary fallback path
Also keep a low-frequency timer because:
- some detailed registry values may change without a visible UI refresh otherwise
- sleep / wake edges can be awkward
- you need a fallback if a notification is missed

Recommended default:
- refresh every 30 seconds while the app is running
- if you find that notifications are enough in practice, you may lengthen fallback to 60 seconds

Do **not** poll every second.

### 17.3 Wake / sleep integration
Refresh on:
- app launch
- app foreground / activation
- system wake
- power-source notifications
- fallback timer

Use `NSWorkspace` notifications for wake if helpful.

### 17.4 Time-estimate smoothing
Keep the smoothing buffer in memory only.
Do not persist it.
Do not store second-by-second telemetry.

---

## 18. Persistence and iCloud strategy

Keep this minimal.

### 18.1 Local source of truth
Use `UserDefaults` (wrapped in a small preferences store).

### 18.2 Optional iCloud sync
If settings sync is enabled, mirror a small set of user preferences to `NSUbiquitousKeyValueStore`.

Why this is the right choice for v1:
- simple
- Apple ecosystem only
- no custom backend
- no user account flow
- perfect for small settings
- far less complex than a CloudKit model for a read-only utility

### 18.3 What to sync
Sync only lightweight settings, for example:
- menu bar display mode
- temperature unit preference
- launch-at-login preference choice
- whether advanced values are shown

### 18.4 What not to sync in MVP
Do **not** sync:
- second-by-second battery snapshots
- raw registry dumps
- heavy history logs

If a future version needs multi-device battery history, that can be a later CloudKit or SwiftData evaluation. Not in v1.

### 18.5 iCloud availability rule
The app must still work fully without iCloud.
When iCloud is unavailable:
- continue using local settings
- show a small informational note in Settings if appropriate
- do not block app usage

---

## 19. Launch at login

Implement launch at login only through Apple's supported API.

Use:
- `SMAppService`

Rules:
- this is optional
- default is off
- only enable after explicit user action
- handle status / approval states cleanly
- if the system requires approval, explain that calmly in Settings

Do not add custom launch agents or unsupported login-item hacks.

---

## 20. UI specification

### 20.1 Visual tone
The visual tone should be:
- restrained
- native
- readable
- lightly technical
- not loud
- not playful
- not skeuomorphic

### 20.2 Main window layout
No sidebar.
No tab bar.
No dense dashboard grid.

Recommended layout:
- a simple top header
- 3 to 4 grouped sections below
- metric rows using `LabeledContent`, `Grid`, or very light custom rows
- monospaced digits for changing numbers

Recommended section grouping:

1. **Battery Overview**
   - power state
   - battery percentage
   - full charge capacity (hero metric)
   - health percent

2. **Charge**
   - current charge mAh
   - current charge Wh
   - estimated time remaining

3. **Capacity**
   - full charge capacity mAh
   - full charge capacity Wh
   - design capacity mAh
   - design capacity Wh

4. **Electrical & Lifecycle**
   - discharge rate mA
   - charge rate W
   - cycle count
   - temperature
   - manufacture date
   - battery age

### 20.3 Hero metric
The top emphasized metric should be:

**Current charge-holding capacity**

Suggested presentation:
- large numeric value in mAh
- smaller companion value in Wh
- subtle secondary text showing health % of design

Reason:
- this is the user's key metric
- the rest of the UI supports this value

### 20.4 Main window wireframe
A rough wireframe is below. Do not copy it literally; use it as a structural guide.

```text
┌──────────────── BatteryStats ────────────────┐
│ Battery                                      │
│ Charging • 92% • Updated just now            │
│                                              │
│ Full charge capacity                         │
│ 5,338 mAh                                    │
│ 68.3 Wh • 81.4% of design                    │
│                                              │
│ Charge                                       │
│ Current charge                 4,912 mAh     │
│ Current energy                  62.8 Wh      │
│ Time remaining                  2h 48m       │
│                                              │
│ Capacity                                     │
│ Full charge capacity         5,338 mAh       │
│ Full charge energy             68.3 Wh       │
│ Design capacity              6,559 mAh       │
│ Design energy                  83.8 Wh       │
│                                              │
│ Electrical & Lifecycle                       │
│ Discharge rate               1,086 mA        │
│ Charge rate                     —            │
│ Cycle count                     247          │
│ Temperature                  34.2 °C         │
│ Manufacture date             Sep 2023        │
│ Battery age                  2y 7m           │
└──────────────────────────────────────────────┘
```

### 20.5 Menu bar extra
The menu bar extra should stay compact.

Default menu bar label:
- icon + battery percentage

Allow settings options later:
- icon only
- icon + percentage
- icon + health percent
- icon + full charge capacity abbreviated

Popover content:
- power state
- full charge capacity
- current charge
- time remaining
- temperature
- cycle count
- buttons: `Open BatteryStats`, `Refresh`, `Settings`, `Quit`

Use the window-style menu bar extra if it looks better and stays native.

### 20.6 Settings
Settings should be very small.

Suggested sections:

**General**
- Launch at Login
- Sync Preferences with iCloud

**Display**
- Menu Bar Display Mode
- Temperature Unit: System / Celsius / Fahrenheit

**Advanced**
- Show Advanced Values
- Copy Raw Battery Snapshot (debug-friendly action)
- Reset Settings

Do not build a giant preferences panel.

### 20.7 Unsupported state
If there is no internal battery:
- show a simple icon
- show a clear message
- optionally note that BatteryStats is intended for Mac laptops with internal batteries
- still allow opening Settings

### 20.8 Unavailable metric display
If an individual metric is unavailable:
- show em dash or `Unavailable`
- avoid error-red styling
- avoid making the whole screen feel broken

---

## 21. UX wording rules

Use calm, literal wording.

Recommended labels:
- `Current charge`
- `Current energy`
- `Current charge-holding capacity`
- `Design capacity`
- `Discharge rate`
- `Charge rate`
- `Estimated time remaining`
- `Cycle count`
- `Manufacture date`
- `Battery age`
- `Temperature`
- `Battery health`

Avoid marketing phrasing like:
- `Power score`
- `Battery vitality`
- `Battery fitness`
- `Peak status`

---

## 22. App behavior rules

### 22.1 On charging
Show:
- state: `Charging`
- charge rate in W
- discharge rate as em dash
- time remaining at current discharge rate as em dash

Optional:
- show system time to full in a smaller secondary location if easy

### 22.2 On battery
Show:
- state: `On Battery`
- discharge rate in mA
- rate-based time remaining
- charge rate as em dash

### 22.3 On AC but not charging
Possible states:
- `Connected, Not Charging`
- `Fully Charged`

In these states:
- charge rate often becomes zero or nil
- rate-based discharge time should be hidden / em dash
- keep UI calm; this is a normal state

### 22.4 When optimized charging / charge limit is active
Do not treat a less-than-100% top-off as an error.

Implementation note:
- macOS battery-health management and charge-limit features can intentionally hold a battery below a traditional “100% full charge” point
- values may also recalibrate over time
- avoid scary warnings

If you include any explanatory text, keep it small and optional.

---

## 23. Error handling and fallback behavior

### 23.1 Missing registry service
If `AppleSmartBattery` is unavailable:
- try public power-source APIs for high-level state
- show unsupported or limited-data UI
- do not crash

### 23.2 Missing individual keys
If some keys are missing:
- compute what you can
- mark what you cannot
- keep snapshot valid

### 23.3 iCloud unavailable
If iCloud is unavailable:
- use local preferences only
- settings sync toggle can show disabled or explanatory text
- app still fully usable

### 23.4 Invalid manufacture date
If decoded date is invalid:
- return `nil`
- log debug message
- show `Unavailable`

### 23.5 Implausible electrical values
If current / voltage / temperature are implausible:
- prefer not showing a value over showing nonsense
- log debug information
- add a note in code if a future hardware-specific fix is needed

---

## 24. Logging and diagnostics

Use `Logger` / `OSLog`.
Do not spam the console in release builds.

Recommended log categories:
- batteryReader
- powerSource
- settingsSync
- launchAtLogin

Add a debug-friendly action such as:
- `Copy Raw Battery Snapshot`
- `Copy Parsed Battery Snapshot`

This is very useful for support and future fixes without adding external telemetry.

Do not upload logs anywhere.

---

## 25. Testing requirements

Testing is required because battery parsing has edge cases.

### 25.1 Unit tests to implement
Write tests for:
- manufacture date decode
- health percent calculation
- time remaining calculation
- Wh derivation math
- signed current normalization
- temperature conversion helper
- formatting helpers

### 25.2 Fixture tests
Create mocked battery dictionaries that simulate:
- normal charging
- normal discharging
- fully charged on AC
- missing temperature
- missing manufacture date
- unsigned-encoded negative current
- no internal battery

### 25.3 Manual validation scenarios
Manually test on an Apple Silicon Mac laptop in at least these scenarios:

1. **On battery**
   - unplug charger
   - verify state changes to `On Battery`
   - verify current becomes negative or discharge rate is shown
   - verify time remaining appears

2. **Charging**
   - plug in charger
   - verify state changes to `Charging`
   - verify positive charge power is shown
   - verify discharge time hides

3. **Connected, not charging / full**
   - leave charger connected when already full or charge-limited
   - verify app does not show nonsense charge power

4. **Sleep / wake**
   - sleep Mac
   - wake it
   - verify values refresh cleanly

5. **iCloud unavailable**
   - simulate or test on a machine without iCloud
   - verify app still behaves normally

6. **No internal battery**
   - use a desktop Mac or simulate reader failure
   - verify unsupported-state view

### 25.4 Performance validation
Confirm that the app:
- does not poll every second
- has low idle CPU
- is not obviously power-hungry in Activity Monitor
- does not write constantly to disk

---

## 26. Performance requirements

BatteryStats must not become the thing that drains the battery.

Rules:
- no second-by-second polling
- no constant disk writes
- no heavy background work
- no expensive charts in MVP
- no large retained raw-data history in memory

Performance target:
- effectively idle when values are stable
- visually responsive on updates
- negligible CPU usage when sitting in the menu bar

---

## 27. Accessibility requirements

Even though the UI is small, accessibility matters.

Do:
- provide accessibility labels for icons
- do not rely on color alone for state
- use clear text labels
- keep contrast strong
- allow standard keyboard navigation where reasonable

Use SF Symbols with meaningful accessibility text.

---

## 28. Code style guidance

### 28.1 General
- prefer clarity over cleverness
- keep comments for non-obvious battery quirks
- keep functions small where helpful
- use value types for data models
- use a small number of long-lived store / service objects

### 28.2 Naming
Be literal. Good names:
- `fullChargeCapacityMilliampHours`
- `manufactureDate`
- `signedCurrentMilliamps`
- `batteryAgeComponents`

Avoid vague names like:
- `metricA`
- `healthNumber`
- `batteryPowerMagic`

### 28.3 Comments
Add comments where there is genuine ambiguity, especially for:
- public vs registry capacity values
- signed current conversion
- temperature conversion
- manufacture date decode
- charge-limit / optimized-charging caveats

Do not over-comment obvious SwiftUI layout code.

### 28.4 Concurrency
Keep concurrency simple.
Use `@MainActor` for the UI-facing monitor/store.
Use background work only where it materially helps and does not complicate the model.

### 28.5 Overengineering warning
Do not build:
- a generic plugin system
- a dependency injection framework
- a reactive event bus
- a large persistence abstraction
- a remote sync layer
- a custom theme engine

This is a small Mac utility.

---

## 29. Recommended implementation sequence

Follow this order.

### Phase 1 — Project scaffold
- create app target
- create main window placeholder
- create settings window placeholder
- create menu bar extra placeholder
- add linked frameworks
- create empty domain model and reader shells

Definition of done:
- app launches
- menu bar extra appears
- settings window opens
- project builds cleanly

### Phase 2 — Battery readers
- implement `PowerSourceReader`
- implement `SmartBatteryReader`
- parse one unified `BatterySnapshot`
- add debug logging
- add battery snapshot preview / mock data

Definition of done:
- on a real Mac laptop, a snapshot can be read and printed / shown

### Phase 3 — Derived calculations
- add health calculation
- add time remaining calculation
- add Wh derivation
- add manufacture date decoder
- add temperature conversion helper
- add signed current normalization

Definition of done:
- snapshot contains all core derived metrics where data exists

### Phase 4 — Main dashboard
- build the detailed window UI
- add grouped sections
- add hero metric
- format values cleanly
- handle unavailable metrics gracefully

Definition of done:
- a user can read every required metric clearly

### Phase 5 — Menu bar extra
- display battery state / percent
- show quick summary in popover
- add `Open BatteryStats`, `Refresh`, `Settings`, `Quit`
- make the menu bar view compact and stable

Definition of done:
- menu bar extra is useful even without opening main window

### Phase 6 — Settings and preferences
- implement preferences store
- add temperature unit
- add menu bar display mode
- add launch-at-login toggle
- add iCloud settings sync wrapper

Definition of done:
- preferences persist
- iCloud sync is optional and non-blocking
- launch-at-login uses Apple's supported path only

### Phase 7 — Testing and polish
- add unit tests
- add fixtures
- test sleep / wake
- refine wording
- refine unsupported state
- reduce UI clutter
- verify low overhead

Definition of done:
- app feels stable, calm, and native

---

## 30. Known risk areas and mitigations

### Risk 1 — Public vs absolute capacity confusion
Problem:
- public power-source keys may be percentage-oriented

Mitigation:
- get absolute capacities from `AppleSmartBattery`
- isolate this logic in one reader
- write tests and comments

### Risk 2 — Signed current weirdness
Problem:
- negative current may appear as giant unsigned values

Mitigation:
- normalize intentionally
- test with fixture examples

### Risk 3 — Temperature unit ambiguity
Problem:
- raw temperature interpretation is not perfectly obvious across examples

Mitigation:
- isolate conversion helper
- use sanity checks
- validate on real hardware
- avoid spreading conversion assumptions through the UI

### Risk 4 — Charge-limit / optimized charging confusion
Problem:
- users may think the app is wrong when macOS intentionally limits charging

Mitigation:
- use neutral labels
- avoid alarmist messaging
- optionally show a subtle note in advanced help if needed

### Risk 5 — Future hardware / OS key changes
Problem:
- some registry keys may vary

Mitigation:
- centralize key parsing
- make metrics optional
- ship graceful fallback behavior
- keep debug snapshot export available

---

## 31. Release / distribution checklist

Before calling v1 done:

- build succeeds in Debug and Release
- Apple Silicon build runs natively
- menu bar extra works
- main window works
- settings work
- launch-at-login works through supported Apple API
- app behaves correctly without iCloud
- unsupported state exists for no-battery hardware
- no runtime shell commands
- no third-party dependencies
- no custom network calls
- no private APIs
- no elevated privileges
- low overhead confirmed
- tests added for parsing and formulas

If distributing via the Mac App Store:
- keep App Sandbox enabled
- ensure login behavior is explicit and user-controlled
- do not add an external updater
- keep privacy disclosures honest and minimal
- do not auto-run anything without consent

---

## 32. Future features (not MVP)

Only consider these after v1 is stable:

- local battery history snapshots
- Swift Charts history view
- export to CSV / JSON
- optional advanced diagnostics panel
- optional battery condition label if a reliable public source is available
- multi-Mac history sync via CloudKit if there is a real product need
- more menu bar display options

Do not start here.

---

## 33. Final agent instruction

When implementing BatteryStats, optimize for:

1. correctness
2. low overhead
3. native feel
4. clarity of battery metrics
5. minimal scope

The app should feel trustworthy.

That means:
- real data
- calm UI
- small feature set
- honest fallbacks
- no unnecessary infrastructure

If you must choose between a partially available but clearly labeled metric and a fake-perfect metric, choose the clearly labeled real one.

---

## 34. Reference links for implementation

Official and relevant references to keep handy while coding:

- Battery Health 2 App Store listing:
  - https://apps.apple.com/us/app/battery-health-2-stats-info/id1120214373?mt=12

- Apple power-source APIs:
  - https://developer.apple.com/documentation/iokit/iopowersources_h
  - https://developer.apple.com/documentation/iokit/1523868-iopsnotificationcreaterunloopsou
  - https://developer.apple.com/documentation/iokit/1523867-iopsgetpowersourcedescription
  - https://developer.apple.com/documentation/iokit/1523835-iopsgettimeremainingestimate
  - https://developer.apple.com/documentation/iokit/kiopscurrentcapacitykey
  - https://developer.apple.com/documentation/iokit/kiopsmaxcapacitykey
  - https://developer.apple.com/documentation/iokit/iopskeys_h/defines

- SwiftUI menu bar extra / macOS UI guidance:
  - https://developer.apple.com/documentation/swiftui/menubarextra
  - https://developer.apple.com/design/human-interface-guidelines/the-menu-bar

- Launch at login:
  - https://developer.apple.com/documentation/servicemanagement/smappservice
  - https://developer.apple.com/documentation/servicemanagement/smappservice/register%28%29

- App review rules relevant to macOS utilities:
  - https://developer.apple.com/app-store/review/guidelines/

- Apple battery behavior / charge management:
  - https://support.apple.com/102588
  - https://support.apple.com/102338

- Smart Battery packed manufacture-date reference:
  - https://sbs-forum.org/specs/sbdata10.pdf
