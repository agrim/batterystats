# Multi-Device Architecture

This branch prepares BatteryStats for iOS, iPadOS, and watchOS work without weakening the current macOS app.

## Branching

- `main` remains the shipping macOS release line.
- `multi-device` is the integration branch for all iOS, iPadOS, and watchOS exploration.
- Short-lived implementation branches, if needed, should branch from `multi-device` and target `multi-device` for review.
- Do not merge unfinished mobile or watch experiments directly into `main`.

## Repository Lanes

- `Platforms/macOS/App/`: the current macOS app, including Mac-only UI, settings surfaces, and IOKit battery readers.
- `Platforms/macOS/Widgets/`: the current macOS WidgetKit extension.
- `Platforms/iOS/App/`: the future universal iPhone app target.
- `Platforms/iPadOS/`: iPad-specific presentation, navigation, keyboard, and pointer behavior for the universal iOS target.
- `Platforms/watchOS/App/`: the future watchOS app shell.
- `Platforms/watchOS/Extension/`: watch runtime code, complications, and WatchConnectivity integration.
- `Shared/BatteryCore/`: battery snapshots, calculations, formatting, policies, and utilities that should stay platform-neutral.
- `Shared/Support/`: reusable Apple-platform support code that each target must opt into deliberately.

## Target Strategy

The first mobile target should be a universal iOS app target named `BatteryStatsMobile`. iPadOS should usually be an idiom-specific experience inside that target rather than a separate Xcode platform target. Put iPad-only views and interaction affordances in `Platforms/iPadOS/` when the universal app needs them.

The watch target should be added as a paired watchOS app once the phone app has a stable battery-state transport story. Keep watch-specific state transfer and complications out of `Shared/BatteryCore`; share only value models and formatting.

## Shared-Code Boundary

`Shared/BatteryCore` should compile without AppKit, UIKit, WatchKit, WidgetKit, IOKit, ServiceManagement, or UserNotifications. If a type needs one of those frameworks, keep it in a platform lane or in `Shared/Support` with explicit target opt-in.

The current macOS battery readers stay in `Platforms/macOS/App/Features/Battery/Data/` because iOS and watchOS do not expose the same IOKit battery properties. Future platform readers should adapt their native APIs into `BatterySnapshot` rather than changing the shared model for one platform's quirks.

## First Implementation Checklist

- Add `BatteryStatsMobile` in `project.yml` with `Platforms/iOS/App` plus `Shared/BatteryCore`.
- Add iPhone and iPad app icons/assets separately from the Mac Icon Composer source if required by Xcode.
- Add a mobile battery reader that maps `UIDevice` battery state into `BatterySnapshot`.
- Add an iPad presentation layer only after the iPhone shell has the core state flow working.
- Add `BatteryStatsWatch` and its extension after deciding whether the watch displays local watch battery state, phone battery state, or both.
- Regenerate `BatteryStats.xcodeproj` with `xcodegen generate` after each target change.
- Verify macOS still builds after every structural change.
