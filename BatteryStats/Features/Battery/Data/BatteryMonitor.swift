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
    var isRefreshing = false

    @ObservationIgnored private let reader: BatteryReadingClient
    @ObservationIgnored private var refreshPolicy = BatteryRefreshPolicy()
    @ObservationIgnored private var monitoringDemand = BatteryMonitoringDemand()
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
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var energyProbeTask: Task<Void, Never>?
    @ObservationIgnored private var diagnosticsTask: Task<Void, Never>?
    @ObservationIgnored private var pendingRefresh = false
    @ObservationIgnored private var pendingRefreshNeedsDiagnostics = false
    @ObservationIgnored private var latestRawSnapshotText = "No battery snapshot has been captured yet."
    @ObservationIgnored private var latestParsedSnapshotText = "No parsed battery snapshot has been captured yet."
    @ObservationIgnored private var isStarted = false

    init(reader: BatteryReadingClient = .live()) {
        self.reader = reader
    }

    func updateRefreshPolicy(_ policy: BatteryRefreshPolicy) {
        guard refreshPolicy != policy else {
            return
        }

        refreshPolicy = policy
        resetTimers()
    }

    func updateMonitoringDemand(_ demand: BatteryMonitoringDemand) {
        guard monitoringDemand != demand else {
            return
        }

        monitoringDemand = demand
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
            powerSourceNotificationToken = reader.makeNotificationToken { [weak self] in
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
        requestRefresh()
    }

    private func probeEnergyUse() {
        guard refreshTask == nil,
              energyProbeTask == nil else {
            return
        }

        energyProbeTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            let result = await reader.read(.now, .standard)
            handleEnergyProbeResult(result)
            energyProbeTask = nil
        }
    }

    private func handleEnergyProbeResult(_ result: BatteryReadResult) {
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

    private func requestRefresh(options: BatteryReadOptions = .standard) {
        if refreshTask != nil {
            pendingRefresh = true
            pendingRefreshNeedsDiagnostics = pendingRefreshNeedsDiagnostics || options.includesDiagnostics
            return
        }

        refreshTask = Task { @MainActor [weak self] in
            await self?.runRefreshLoop(initialOptions: options)
        }
    }

    private func runRefreshLoop(initialOptions: BatteryReadOptions) async {
        isRefreshing = true
        defer {
            isRefreshing = false
            refreshTask = nil
            pendingRefresh = false
            pendingRefreshNeedsDiagnostics = false
        }

        var options = initialOptions

        while true {
            let result = await reader.read(.now, options)
            apply(result)

            guard pendingRefresh else {
                break
            }

            options = pendingRefreshNeedsDiagnostics ? .diagnostics : .standard
            pendingRefresh = false
            pendingRefreshNeedsDiagnostics = false
        }
    }

    private func apply(_ result: BatteryReadResult) {
        if let rawSnapshotText = result.rawSnapshotText {
            latestRawSnapshotText = rawSnapshotText
        }

        if let parsedSnapshotText = result.parsedSnapshotText {
            latestParsedSnapshotText = parsedSnapshotText
        }

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
        diagnosticsTask?.cancel()
        diagnosticsTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            let result = await reader.read(.now, .diagnostics)
            if let rawSnapshotText = result.rawSnapshotText {
                latestRawSnapshotText = rawSnapshotText
                PasteboardCopying.copy(rawSnapshotText)
            } else {
                PasteboardCopying.copy(latestRawSnapshotText)
            }

            diagnosticsTask = nil
        }
    }

    func copyParsedSnapshot() {
        if let snapshot {
            let parsedSnapshotText = snapshot.debugSummary
            latestParsedSnapshotText = parsedSnapshotText
            PasteboardCopying.copy(parsedSnapshotText)
        } else {
            PasteboardCopying.copy(latestParsedSnapshotText)
        }
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

        if refreshPolicy.usesEnergyChangeProbe(for: monitoringDemand) {
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

    func waitForIdleForTesting() async {
        while refreshTask != nil || energyProbeTask != nil || diagnosticsTask != nil {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
