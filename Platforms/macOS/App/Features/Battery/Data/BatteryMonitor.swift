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
    @ObservationIgnored private var refreshPolicy = BatteryRefreshPolicy()
    @ObservationIgnored private weak var historyStore: BatteryHistoryStore?
    @ObservationIgnored private var alertPolicy = BatteryAlertPolicy.disabled
    @ObservationIgnored private let alertCoordinator = BatteryAlertCoordinator()
    @ObservationIgnored private var dischargeSamples: [Int] = []
    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var energyProbeTimer: Timer?
    @ObservationIgnored private var currentRefreshInterval: TimeInterval?
    @ObservationIgnored private var lastPublishedEnergyUse: Double?
    @ObservationIgnored private var powerSourceNotificationToken: PowerSourceReader.NotificationToken?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var activeObserver: NSObjectProtocol?
    @ObservationIgnored private var isStarted = false

    init(service: BatteryReadingService = BatteryReadingService()) {
        self.service = service
    }

    func updateRefreshPolicy(_ policy: BatteryRefreshPolicy) {
        guard refreshPolicy != policy else {
            return
        }

        refreshPolicy = policy
        resetTimers()
    }

    func updateHistory(store: BatteryHistoryStore, policy: BatteryHistoryPolicy) {
        historyStore = store
        store.updatePolicy(policy)
    }

    func updateAlerts(_ policy: BatteryAlertPolicy) {
        alertPolicy = policy
    }

    func start() {
        isStarted = true

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

        resetTimers()
        refresh()
    }

    func refresh() {
        apply(service.read())
    }

    private func probeEnergyUse() {
        guard isRefreshing == false else {
            return
        }

        let result = service.read()
        guard let probedSnapshot = result.snapshot else {
            if availabilityState != .unsupported {
                apply(result)
            }
            return
        }

        let currentEnergyUse = probedSnapshot.energyUseComparisonValue
        if BatteryRefreshPolicy.isSignificantEnergyChange(
            previous: lastPublishedEnergyUse,
            current: currentEnergyUse,
            thresholdPercent: refreshPolicy.energyChangeThresholdPercent
        ) {
            apply(result)
        }
    }

    private func apply(_ result: BatteryReadResult) {
        isRefreshing = true
        defer {
            isRefreshing = false
        }

        rawSnapshotText = result.rawSnapshotText
        parsedSnapshotText = result.parsedSnapshotText
        lastUpdated = .now

        guard var snapshot = result.snapshot else {
            availabilityState = .unsupported
            self.snapshot = nil
            lastPublishedEnergyUse = nil
            dischargeSamples.removeAll()
            resetTimers()
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
        lastPublishedEnergyUse = snapshot.energyUseComparisonValue
        historyStore?.record(snapshot)
        alertCoordinator.evaluate(snapshot: snapshot, policy: alertPolicy)
        resetTimers()
    }

    func copyRawSnapshot() {
        PasteboardCopying.copy(rawSnapshotText)
    }

    func copyParsedSnapshot() {
        PasteboardCopying.copy(parsedSnapshotText)
    }

    private func resetTimers() {
        guard isStarted else {
            return
        }

        let desiredRefreshInterval = refreshPolicy.refreshInterval(for: snapshot)
        if currentRefreshInterval != desiredRefreshInterval {
            refreshTimer?.invalidate()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: desiredRefreshInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                }
            }
            refreshTimer?.tolerance = max(1, min(30, desiredRefreshInterval * 0.2))
            currentRefreshInterval = desiredRefreshInterval
        }

        if refreshPolicy.usesEnergyChangeProbe {
            if energyProbeTimer == nil {
                energyProbeTimer = Timer.scheduledTimer(withTimeInterval: refreshPolicy.energyProbeInterval, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        self?.probeEnergyUse()
                    }
                }
                energyProbeTimer?.tolerance = 3
            }
        } else {
            energyProbeTimer?.invalidate()
            energyProbeTimer = nil
        }
    }
}
