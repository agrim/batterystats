@preconcurrency import AppKit
@preconcurrency import Foundation
import Observation
import WidgetKit

@MainActor
@Observable
final class BatteryMonitor {
    enum AvailabilityState: Equatable {
        case loading
        case available
        case unsupported
    }

    private static let unavailableRawSnapshotText = "Raw battery diagnostics are unavailable for the latest snapshot."
    private static let unsupportedRawSnapshotText = "No supported internal battery is currently available."
    private static let unsupportedParsedSnapshotText = "Unsupported"
    private static let lightningRefreshLoopDelay: Duration = .milliseconds(200)
    static let timerRunLoopMode: RunLoop.Mode = .common

    var availabilityState: AvailabilityState = .loading
    var snapshot: BatterySnapshot?
    var lastUpdated: Date?
    var isRefreshing = false
    private(set) var isCopyingRawSnapshot = false
    private var parsedSnapshotFallbackText: String?

    var canCopyParsedSnapshot: Bool {
        snapshot != nil || parsedSnapshotFallbackText != nil
    }

    @ObservationIgnored private let reader: BatteryReadingClient
    @ObservationIgnored private var refreshPolicy = BatteryRefreshPolicy()
    @ObservationIgnored private var preferenceMonitoringDemand = BatteryMonitoringDemand()
    @ObservationIgnored private var visibleSurfaceDemandCount = 0
    @ObservationIgnored private var isLightningRefreshActive = false
    @ObservationIgnored private var monitoringDemand = BatteryMonitoringDemand()
    @ObservationIgnored private weak var historyStore: BatteryHistoryStore?
    @ObservationIgnored private var alertPolicy = BatteryAlertPolicy.disabled
    @ObservationIgnored private let alertCoordinator: BatteryAlertCoordinator
    @ObservationIgnored private let pasteboardCopy: @MainActor (String) -> Void
    @ObservationIgnored private var dischargeSamples: [Int] = []
    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var energyProbeTimer: Timer?
    @ObservationIgnored private var currentRefreshInterval: TimeInterval?
    @ObservationIgnored private var currentEnergyProbeInterval: TimeInterval?
    @ObservationIgnored private var lastPublishedEnergyUse: Double?
    @ObservationIgnored private var powerSourceNotificationToken: PowerSourceReader.NotificationToken?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var activeObserver: NSObjectProtocol?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var energyProbeTask: Task<Void, Never>?
    @ObservationIgnored private var diagnosticsTask: Task<Void, Never>?
    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private var energyProbeGeneration = 0
    @ObservationIgnored private var diagnosticsGeneration = 0
    @ObservationIgnored private var readSequence = 0
    @ObservationIgnored private var lastAppliedReadSequence = 0
    @ObservationIgnored private var pendingRefreshOptions: BatteryReadOptions?
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private let widgetSnapshotStore: BatteryWidgetSnapshotStore
    @ObservationIgnored private let widgetTimelineReloader: @MainActor () -> Void
    @ObservationIgnored private let widgetTimelineReloadMinimumInterval: TimeInterval
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var lastWidgetTimelineReloadDate: Date?
    @ObservationIgnored private var lastWidgetTimelineReloadSignature: WidgetTimelineReloadSignature?

    init(
        reader: BatteryReadingClient = .live(),
        alertCoordinator: BatteryAlertCoordinator = BatteryAlertCoordinator(),
        pasteboardCopy: @escaping @MainActor (String) -> Void = PasteboardCopying.copy,
        widgetSnapshotStore: BatteryWidgetSnapshotStore = .shared,
        widgetTimelineReloader: @escaping @MainActor () -> Void = {
            WidgetCenter.shared.reloadTimelines(ofKind: BatteryWidgetSnapshotStore.timelineKind)
        },
        widgetTimelineReloadMinimumInterval: TimeInterval = 60,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.reader = reader
        self.alertCoordinator = alertCoordinator
        self.pasteboardCopy = pasteboardCopy
        self.widgetSnapshotStore = widgetSnapshotStore
        self.widgetTimelineReloader = widgetTimelineReloader
        self.widgetTimelineReloadMinimumInterval = widgetTimelineReloadMinimumInterval
        self.now = now
    }

    isolated deinit {
        tearDownMonitoringResources()
    }

    func updateRefreshPolicy(_ policy: BatteryRefreshPolicy) {
        guard refreshPolicy != policy else {
            return
        }

        refreshPolicy = policy
        resetTimers()
    }

    func updateMonitoringDemand(_ demand: BatteryMonitoringDemand) {
        guard preferenceMonitoringDemand != demand else {
            return
        }

        preferenceMonitoringDemand = demand
        refreshEffectiveMonitoringDemand()
    }

    func beginVisibleSurfaceMonitoring() {
        visibleSurfaceDemandCount += 1
        refreshEffectiveMonitoringDemand()
    }

    func endVisibleSurfaceMonitoring() {
        guard visibleSurfaceDemandCount > 0 else {
            return
        }

        visibleSurfaceDemandCount -= 1
        refreshEffectiveMonitoringDemand()
    }

    func setLightningRefreshActive(_ isActive: Bool) {
        guard isLightningRefreshActive != isActive else {
            return
        }

        isLightningRefreshActive = isActive

        if isActive {
            refreshForVisibleSurface()
        }
    }

    func updateHistory(store: BatteryHistoryStore, policy: BatteryHistoryPolicy) {
        historyStore = store
        let startedRecording = store.updatePolicy(policy)
        if startedRecording,
           let snapshot {
            store.record(snapshot)
        }
    }

    func updateAlerts(_ policy: BatteryAlertPolicy) {
        alertPolicy = policy
        alertCoordinator.updatePolicy(policy, currentSnapshot: snapshot)
    }

    @discardableResult
    func start() -> Bool {
        guard isStarted == false else {
            return false
        }

        isStarted = true

        if powerSourceNotificationToken == nil {
            powerSourceNotificationToken = reader.makeNotificationToken { [weak self] in
                Task { @MainActor in
                    self?.requestRefreshIfStarted()
                }
            }
        }

        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.requestRefreshIfStarted()
                }
            }
        }

        if activeObserver == nil {
            activeObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.requestRefreshIfStarted()
                }
            }
        }

        resetTimers()
        refresh()
        return true
    }

    func stop() {
        tearDownMonitoringResources()
    }

    func refresh() {
        requestRefresh()
    }

    func refreshForVisibleSurface() {
        requestRefreshIfStarted()
    }

    private func requestRefreshIfStarted() {
        guard isStarted else {
            return
        }

        requestRefresh()
    }

    private func probeEnergyUse() {
        guard shouldUseEnergyChangeProbe else {
            return
        }

        guard refreshTask == nil,
              energyProbeTask == nil else {
            return
        }

        let generation = energyProbeGeneration
        energyProbeTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer {
                if energyProbeGeneration == generation {
                    energyProbeTask = nil
                }
            }

            let readSequence = nextReadSequence()
            let readDate = now()
            let result = await reader.read(readDate, .standard)
            guard Task.isCancelled == false,
                  energyProbeGeneration == generation,
                  shouldUseEnergyChangeProbe else {
                return
            }

            handleEnergyProbeResult(result, readSequence: readSequence, publicationDate: readDate)
        }
    }

    private func handleEnergyProbeResult(_ result: BatteryReadResult, readSequence: Int, publicationDate: Date) {
        guard let probedSnapshot = result.snapshot else {
            apply(result, readSequence: readSequence, publicationDate: publicationDate)
            return
        }

        let currentEnergyUse = probedSnapshot.energyUseComparisonValue
        let hasEnergyChange = BatteryRefreshPolicy.isSignificantEnergyChange(
            previous: lastPublishedEnergyUse,
            current: currentEnergyUse,
            thresholdPercent: refreshPolicy.energyChangeThresholdPercent
        )
        let hasPresentationChange = hasPresentationStateChange(for: probedSnapshot, publicationDate: publicationDate)

        if hasAlertStateChange(for: probedSnapshot) || hasEnergyChange || hasPresentationChange {
            apply(result, readSequence: readSequence, publicationDate: publicationDate)
        }
    }

    private func hasPresentationStateChange(for probedSnapshot: BatterySnapshot, publicationDate: Date) -> Bool {
        guard let snapshot else {
            return true
        }

        return EnergyProbePresentationSignature(snapshot: snapshot) != EnergyProbePresentationSignature(
            snapshot: probedSnapshot,
            publicationDate: publicationDate
        )
    }

    private func hasAlertStateChange(for probedSnapshot: BatterySnapshot) -> Bool {
        guard alertPolicy.hasEnabledAlerts else {
            return false
        }

        let currentAlertTypes = snapshot.map {
            BatteryAlertEvaluator.activeAlertTypes(snapshot: $0, policy: alertPolicy)
        } ?? []
        let probedAlertTypes = BatteryAlertEvaluator.activeAlertTypes(snapshot: probedSnapshot, policy: alertPolicy)
        return currentAlertTypes != probedAlertTypes
    }

    private func requestRefresh(options: BatteryReadOptions = .standard) {
        cancelEnergyProbeTask()

        if refreshTask != nil {
            pendingRefreshOptions = pendingRefreshOptions?.merged(with: options) ?? options
            return
        }

        let generation = refreshGeneration
        refreshTask = Task { @MainActor [weak self] in
            await self?.runRefreshLoop(initialOptions: options, generation: generation)
        }
    }

    private func runRefreshLoop(initialOptions: BatteryReadOptions, generation: Int) async {
        isRefreshing = true
        defer {
            if refreshGeneration == generation {
                isRefreshing = false
                refreshTask = nil
                pendingRefreshOptions = nil
            }
        }

        var options = initialOptions

        while true {
            let readSequence = nextReadSequence()
            let readDate = now()
            let result = await reader.read(readDate, options)
            guard Task.isCancelled == false,
                  refreshGeneration == generation else {
                break
            }

            apply(result, readSequence: readSequence, publicationDate: readDate)

            if let pendingOptions = pendingRefreshOptions {
                options = pendingOptions
                pendingRefreshOptions = nil
            } else {
                guard shouldContinueLightningRefreshLoop(for: generation) else {
                    break
                }

                try? await Task.sleep(for: Self.lightningRefreshLoopDelay)
                guard shouldContinueLightningRefreshLoop(for: generation) else {
                    break
                }

                options = .standard
            }
        }
    }

    private func shouldContinueLightningRefreshLoop(for generation: Int) -> Bool {
        Task.isCancelled == false
            && refreshGeneration == generation
            && isLightningRefreshActive
    }

    private func apply(_ result: BatteryReadResult, readSequence: Int, publicationDate: Date) {
        guard readSequence > lastAppliedReadSequence else {
            return
        }

        lastAppliedReadSequence = readSequence

        lastUpdated = publicationDate

        guard var snapshot = result.snapshot else {
            parsedSnapshotFallbackText = result.parsedSnapshotText ?? Self.unsupportedParsedSnapshotText

            availabilityState = .unsupported
            self.snapshot = nil
            lastPublishedEnergyUse = nil
            dischargeSamples.removeAll()
            alertCoordinator.clearActiveAlerts()
            widgetSnapshotStore.clear()
            requestWidgetTimelineReload(for: nil, at: publicationDate)
            resetTimers()
            return
        }

        availabilityState = .available

        if snapshot.powerState.isBatteryDischarging,
           let dischargeRate = snapshot.dischargeRateMilliamps {
            dischargeSamples.append(dischargeRate)
            if dischargeSamples.count > 8 {
                dischargeSamples.removeFirst(dischargeSamples.count - 8)
            }
        } else {
            dischargeSamples.removeAll()
        }

        let smoothedRate = BatteryCalculations.smoothedDischargeRate(
            dischargeSamples,
            fallback: snapshot.dischargeRateMilliamps
        )
        snapshot = snapshot.updating(
            rateBasedTimeRemainingMinutes: snapshot.powerState.isBatteryDischarging
                ? BatteryCalculations.timeRemainingMinutes(
                    currentChargeMilliampHours: snapshot.currentChargeMilliampHours,
                    dischargeRateMilliamps: smoothedRate
                )
                : nil,
            timestamp: publicationDate
        )

        self.snapshot = snapshot
        parsedSnapshotFallbackText = nil
        lastPublishedEnergyUse = snapshot.energyUseComparisonValue
        historyStore?.record(snapshot)
        alertCoordinator.evaluate(snapshot: snapshot, policy: alertPolicy)
        widgetSnapshotStore.save(snapshot)
        requestWidgetTimelineReload(for: snapshot, at: publicationDate)
        resetTimers()
    }

    private func requestWidgetTimelineReload(for snapshot: BatterySnapshot?, at date: Date) {
        let signature = WidgetTimelineReloadSignature(snapshot: snapshot)
        let elapsed = lastWidgetTimelineReloadDate.map { date.timeIntervalSince($0) } ?? .infinity
        guard signature != lastWidgetTimelineReloadSignature
            || elapsed < 0
            || elapsed >= widgetTimelineReloadMinimumInterval else {
            return
        }

        lastWidgetTimelineReloadDate = date
        lastWidgetTimelineReloadSignature = signature
        widgetTimelineReloader()
    }

    func copyRawSnapshot() {
        diagnosticsGeneration &+= 1
        let generation = diagnosticsGeneration

        diagnosticsTask?.cancel()
        isCopyingRawSnapshot = true
        diagnosticsTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer {
                if diagnosticsGeneration == generation {
                    diagnosticsTask = nil
                    isCopyingRawSnapshot = false
                }
            }

            let readSequence = nextReadSequence()
            let readDate = now()
            let result = await reader.read(readDate, .diagnostics)
            guard Task.isCancelled == false,
                  diagnosticsGeneration == generation else {
                return
            }

            let rawSnapshotText = result.rawSnapshotText
                ?? (result.snapshot == nil ? Self.unsupportedRawSnapshotText : Self.unavailableRawSnapshotText)
            if result.snapshot != nil {
                apply(result, readSequence: readSequence, publicationDate: readDate)
            }

            pasteboardCopy(rawSnapshotText)
        }
    }

    func copyParsedSnapshot() {
        if let snapshot {
            pasteboardCopy(snapshot.debugSummary)
        } else if let parsedSnapshotFallbackText {
            pasteboardCopy(parsedSnapshotFallbackText)
        }
    }

    private func resetTimers() {
        guard isStarted else {
            return
        }

        let desiredRefreshInterval = refreshPolicy.refreshInterval(for: snapshot)
        rescheduleTimer(
            &refreshTimer,
            currentInterval: &currentRefreshInterval,
            desiredInterval: desiredRefreshInterval,
            tolerance: Self.refreshTimerTolerance(for: desiredRefreshInterval)
        ) { [weak self] in
            self?.requestRefreshIfStarted()
        }

        if shouldUseEnergyChangeProbe {
            rescheduleTimer(
                &energyProbeTimer,
                currentInterval: &currentEnergyProbeInterval,
                desiredInterval: refreshPolicy.energyProbeInterval,
                tolerance: 3
            ) { [weak self] in
                self?.probeEnergyUse()
            }
        } else {
            cancelEnergyProbe()
        }
    }

    private func rescheduleTimer(
        _ timer: inout Timer?,
        currentInterval: inout TimeInterval?,
        desiredInterval: TimeInterval,
        tolerance: TimeInterval,
        block: @escaping @MainActor @Sendable () -> Void
    ) {
        guard currentInterval != desiredInterval else {
            return
        }

        timer?.invalidate()
        timer = Self.scheduledMonitoringTimer(withTimeInterval: desiredInterval, block: block)
        timer?.tolerance = tolerance
        currentInterval = desiredInterval
    }

    private var shouldUseEnergyChangeProbe: Bool {
        isStarted
            && availabilityState == .available
            && snapshot != nil
            && refreshPolicy.usesEnergyChangeProbe(for: monitoringDemand)
    }

    private func refreshEffectiveMonitoringDemand() {
        let nextDemand = BatteryMonitoringDemand(
            needsEnergyChangeAwareness: preferenceMonitoringDemand.needsEnergyChangeAwareness || visibleSurfaceDemandCount > 0
        )
        guard monitoringDemand != nextDemand else {
            return
        }

        monitoringDemand = nextDemand
        resetTimers()
    }

    private func cancelEnergyProbe() {
        energyProbeTimer?.invalidate()
        energyProbeTimer = nil
        currentEnergyProbeInterval = nil
        cancelEnergyProbeTask()
        lastPublishedEnergyUse = nil
    }

    private func cancelEnergyProbeTask() {
        guard let task = energyProbeTask else {
            return
        }

        energyProbeGeneration &+= 1
        task.cancel()
        energyProbeTask = nil
    }

    private static func refreshTimerTolerance(for interval: TimeInterval) -> TimeInterval {
        if interval <= 1 {
            return interval * 0.1
        }

        return max(1, min(30, interval * 0.2))
    }

    private static func scheduledMonitoringTimer(
        withTimeInterval interval: TimeInterval,
        block: @escaping @MainActor @Sendable () -> Void
    ) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated {
                block()
            }
        }
        RunLoop.main.add(timer, forMode: timerRunLoopMode)
        return timer
    }

    private func tearDownMonitoringResources() {
        isStarted = false
        refreshGeneration &+= 1
        visibleSurfaceDemandCount = 0
        isLightningRefreshActive = false
        monitoringDemand = preferenceMonitoringDemand

        refreshTimer?.invalidate()
        refreshTimer = nil
        currentRefreshInterval = nil

        cancelEnergyProbe()

        powerSourceNotificationToken = nil

        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }

        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
            self.activeObserver = nil
        }

        refreshTask?.cancel()
        diagnosticsTask?.cancel()
        refreshTask = nil
        diagnosticsTask = nil
        diagnosticsGeneration &+= 1
        isRefreshing = false
        isCopyingRawSnapshot = false

        pendingRefreshOptions = nil
    }

    private func nextReadSequence() -> Int {
        readSequence &+= 1
        return readSequence
    }
}

#if DEBUG
extension BatteryMonitor {
    func waitForIdleForTesting() async {
        while refreshTask != nil || energyProbeTask != nil || diagnosticsTask != nil {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func probeEnergyUseForTesting() {
        probeEnergyUse()
    }

    func currentRefreshIntervalForTesting() -> TimeInterval? {
        currentRefreshInterval
    }

    func currentEnergyProbeIntervalForTesting() -> TimeInterval? {
        currentEnergyProbeInterval
    }
}
#endif

private struct WidgetTimelineReloadSignature: Equatable {
    let powerState: BatteryPowerState?
    let statusDisplayTitle: String?
    let batterySymbolName: String
    let updatedMinute: Int?
    let chargePercent: Int?
    let chargeTint: String
    let healthPercent: Int?
    let healthTint: String
    let displayedTimeMinutes: Int?
    let timeTint: String
    let activePowerDeciwatts: Int?
    let usesInputPowerWatts: Bool
    let statusSymbolName: String
    let statusRingTint: String
    let statusContentTint: String

    init(snapshot: BatterySnapshot?, updatedAt: Date? = nil) {
        let statusDescriptor = BatteryPresentationStyle.statusDescriptor(for: snapshot)
        powerState = snapshot?.powerState
        statusDisplayTitle = snapshot?.statusDisplayTitle
        batterySymbolName = BatteryPresentationStyle.batterySymbolName(for: snapshot)
        updatedMinute = Self.minuteIdentifier(updatedAt ?? snapshot?.timestamp)
        chargePercent = Self.roundedInt(snapshot?.presentationStateOfChargePercent)
        chargeTint = BatteryPresentationStyle.chargeTintStyle(for: snapshot).rawValue
        healthPercent = Self.roundedInt(snapshot?.presentationHealthPercent)
        healthTint = BatteryPresentationStyle.healthTintStyle(for: snapshot).rawValue
        displayedTimeMinutes = snapshot?.displayedTimeMinutes
        timeTint = BatteryPresentationStyle.timeTintStyle(for: snapshot).rawValue
        activePowerDeciwatts = Self.roundedInt(snapshot?.activePowerWatts, multiplier: 10)
        usesInputPowerWatts = snapshot?.visibleInputPowerWatts != nil
        statusSymbolName = statusDescriptor.symbolName
        statusRingTint = statusDescriptor.ringTintStyle.rawValue
        statusContentTint = statusDescriptor.contentTintStyle.rawValue
    }

    private static func minuteIdentifier(_ date: Date?) -> Int? {
        guard let date else {
            return nil
        }

        return roundedInt(date.timeIntervalSince1970, multiplier: 1.0 / 60.0, roundingRule: .down)
    }

    static func roundedInt(
        _ value: Double?,
        multiplier: Double = 1,
        roundingRule: FloatingPointRoundingRule = .toNearestOrAwayFromZero
    ) -> Int? {
        guard let value, value.isFinite else {
            return nil
        }

        let scaledValue = value * multiplier
        guard scaledValue.isFinite,
              scaledValue >= Double(Int.min),
              scaledValue <= Double(Int.max) else {
            return nil
        }

        return Int(scaledValue.rounded(roundingRule))
    }
}

private struct EnergyProbePresentationSignature: Equatable {
    let widgetTimelineSignature: WidgetTimelineReloadSignature
    let currentChargeMilliampHours: Int?
    let fullChargeCapacityMilliampHours: Int?
    let designCapacityMilliampHours: Int?
    let visibleCurrentMilliamps: Int?
    let voltageMillivolts: Int?
    let currentChargeDeciwattHours: Int?
    let fullChargeCapacityDeciwattHours: Int?
    let temperatureTenthsCelsius: Int?
    let cycleCount: Int?
    let manufactureDateDay: Int?
    let batteryAgeMonths: Int?

    init(snapshot: BatterySnapshot, publicationDate: Date? = nil) {
        widgetTimelineSignature = WidgetTimelineReloadSignature(snapshot: snapshot, updatedAt: publicationDate)
        currentChargeMilliampHours = BatteryCalculations.plausibleCapacityMilliampHours(snapshot.currentChargeMilliampHours)
        fullChargeCapacityMilliampHours = BatteryCalculations.plausibleCapacityMilliampHours(
            snapshot.fullChargeCapacityMilliampHours,
            allowsZero: false
        )
        designCapacityMilliampHours = BatteryCalculations.plausibleCapacityMilliampHours(
            snapshot.designCapacityMilliampHours,
            allowsZero: false
        )
        visibleCurrentMilliamps = Self.visibleCurrentMilliamps(snapshot)
        voltageMillivolts = BatteryCalculations.plausibleVoltageMillivolts(snapshot.voltageMillivolts)
        currentChargeDeciwattHours = WidgetTimelineReloadSignature.roundedInt(
            BatteryCalculations.plausibleWattHours(snapshot.currentChargeWattHours),
            multiplier: 10
        )
        fullChargeCapacityDeciwattHours = WidgetTimelineReloadSignature.roundedInt(
            BatteryCalculations.plausibleWattHours(snapshot.fullChargeCapacityWattHours),
            multiplier: 10
        )
        temperatureTenthsCelsius = WidgetTimelineReloadSignature.roundedInt(
            snapshot.presentationTemperatureCelsius,
            multiplier: 10
        )
        cycleCount = BatteryCalculations.plausibleCycleCount(snapshot.cycleCount)
        manufactureDateDay = Self.dayIdentifier(snapshot.validatedManufactureDate)
        batteryAgeMonths = BatteryCalculations.displayableBatteryAgeMonthCount(snapshot.validatedBatteryAgeComponents)
    }

    private static func visibleCurrentMilliamps(_ snapshot: BatterySnapshot) -> Int? {
        let shouldDisplayCurrent = snapshot.powerState.isBatteryDischarging
            || (snapshot.powerState == .charging && BatteryCalculations.plausibleWatts(snapshot.activePowerWatts) == nil)
        guard shouldDisplayCurrent else {
            return nil
        }

        return BatteryCalculations.plausibleCurrentMagnitudeMilliamps(snapshot.activeCurrentMilliamps)
    }

    private static func dayIdentifier(_ date: Date?) -> Int? {
        guard let date else {
            return nil
        }

        return WidgetTimelineReloadSignature.roundedInt(
            date.timeIntervalSince1970,
            multiplier: 1.0 / (24 * 60 * 60),
            roundingRule: .down
        )
    }
}
