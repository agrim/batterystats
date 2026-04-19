@preconcurrency import AppKit
@preconcurrency import Foundation
import Observation

@MainActor
@Observable
final class BatteryMonitor {
    enum AvailabilityState: Equatable {
        case loading
        case available
        case unsupported
    }

    var availabilityState: AvailabilityState = .loading
    var snapshot: BatterySnapshot?
    var lastUpdated: Date?
    var rawSnapshotText = ""
    var parsedSnapshotText = ""
    var isRefreshing = false

    @ObservationIgnored private let service: BatteryReadingService
    @ObservationIgnored private var dischargeSamples: [Int] = []
    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var powerSourceNotificationToken: PowerSourceReader.NotificationToken?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var activeObserver: NSObjectProtocol?

    init(service: BatteryReadingService = BatteryReadingService()) {
        self.service = service
    }

    func start() {
        if powerSourceNotificationToken == nil {
            powerSourceNotificationToken = service.makeNotificationToken { [weak self] in
                Task { @MainActor in
                    self?.refresh()
                }
            }
        }

        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                }
            }
        }

        if activeObserver == nil {
            activeObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                }
            }
        }

        if refreshTimer == nil {
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                }
            }
            refreshTimer?.tolerance = 0
        }

        refresh()
    }

    func refresh() {
        isRefreshing = true
        defer {
            isRefreshing = false
        }

        let result = service.read()
        rawSnapshotText = result.rawSnapshotText
        parsedSnapshotText = result.parsedSnapshotText
        lastUpdated = .now

        guard var snapshot = result.snapshot else {
            availabilityState = .unsupported
            self.snapshot = nil
            dischargeSamples.removeAll()
            return
        }

        availabilityState = .available

        if let dischargeRate = snapshot.dischargeRateMilliamps {
            dischargeSamples.append(dischargeRate)
            dischargeSamples = Array(dischargeSamples.suffix(8))
        } else {
            dischargeSamples.removeAll()
        }

        let smoothedRate = BatteryCalculations.smoothedDischargeRate(
            dischargeSamples,
            fallback: snapshot.dischargeRateMilliamps
        )
        snapshot = snapshot.updating(
            rateBasedTimeRemainingMinutes: BatteryCalculations.timeRemainingMinutes(
                currentChargeMilliampHours: snapshot.currentChargeMilliampHours,
                dischargeRateMilliamps: smoothedRate
            )
        )

        self.snapshot = snapshot
    }

    func copyRawSnapshot() {
        PasteboardCopying.copy(rawSnapshotText)
    }

    func copyParsedSnapshot() {
        PasteboardCopying.copy(parsedSnapshotText)
    }
}
