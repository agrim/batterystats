# watchOS Extension Lane

Reserved for watch runtime code, complications, WatchConnectivity integration, and watch-specific battery-state adaptation.

Do not put WatchKit-only APIs into `Shared/BatteryCore`; adapt watch data into the shared value models from this lane.
