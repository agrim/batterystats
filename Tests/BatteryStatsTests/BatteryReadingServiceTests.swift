import XCTest
@testable import BatteryStats

final class BatteryReadingServiceTests: XCTestCase {
    func testExternalPublicSourceDoesNotMaskSmartBatteryDetails() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: false,
            isCharged: false,
            isExternalPowerConnected: true,
            isInternalBattery: false,
            stateOfChargePercent: nil,
            powerSourceState: "AC Power",
            rawDescription: ["Type": "UPS"]
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 4_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: -500
        )

        let resolvedSnapshot = try XCTUnwrap(BatteryReadingService.resolvedPublicSnapshot(
            publicSnapshot: publicSnapshot,
            smartBattery: smartBattery
        ))

        XCTAssertTrue(resolvedSnapshot.isInternalBattery)
        XCTAssertTrue(resolvedSnapshot.isPresent)
        XCTAssertEqual(resolvedSnapshot.stateOfChargePercent, 80)
    }

    func testExternalPublicSourceWithoutSmartBatteryIsUnsupported() {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: false,
            isCharged: false,
            isExternalPowerConnected: true,
            isInternalBattery: false,
            stateOfChargePercent: 80,
            powerSourceState: "AC Power",
            rawDescription: ["Type": "UPS"]
        )

        XCTAssertNil(BatteryReadingService.resolvedPublicSnapshot(
            publicSnapshot: publicSnapshot,
            smartBattery: nil
        ))
    }

    func testSmartBatteryFallbackInfersChargingFromPositiveCurrent() throws {
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 4_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: 1_200,
            adapterMaxWatts: 70,
            reportedTimeToFullMinutes: 42
        )

        let fallbackSnapshot = try XCTUnwrap(BatteryReadingService.fallbackPublicSnapshot(from: smartBattery))

        XCTAssertTrue(fallbackSnapshot.isInternalBattery)
        XCTAssertTrue(fallbackSnapshot.isCharging)
        XCTAssertTrue(fallbackSnapshot.isExternalPowerConnected)
        XCTAssertEqual(fallbackSnapshot.stateOfChargePercent, 80)
        XCTAssertEqual(fallbackSnapshot.timeToFullMinutes, 42)
        XCTAssertEqual(fallbackSnapshot.powerSourceState, "AC Power")
    }

    func testSmartBatteryFallbackMarksBatteryPowerWhenDischarging() throws {
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 3_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: -900
        )

        let fallbackSnapshot = try XCTUnwrap(BatteryReadingService.fallbackPublicSnapshot(from: smartBattery))

        XCTAssertFalse(fallbackSnapshot.isCharging)
        XCTAssertFalse(fallbackSnapshot.isExternalPowerConnected)
        XCTAssertEqual(fallbackSnapshot.stateOfChargePercent, 60)
        XCTAssertEqual(fallbackSnapshot.powerSourceState, "Battery Power")
    }

    func testSmartBatteryFallbackLetsDischargeCurrentOverrideStaleAdapterWatts() throws {
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 3_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: -900,
            adapterMaxWatts: 70
        )

        let fallbackSnapshot = try XCTUnwrap(BatteryReadingService.fallbackPublicSnapshot(from: smartBattery))

        XCTAssertFalse(fallbackSnapshot.isCharging)
        XCTAssertFalse(fallbackSnapshot.isExternalPowerConnected)
        XCTAssertEqual(fallbackSnapshot.powerSourceState, "Battery Power")
    }

    func testSmartBatteryFallbackIgnoresInputPowerAboveAdapterCapability() throws {
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 3_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: nil,
            inputPowerWatts: 100,
            adapterMaxWatts: 70
        )

        let fallbackSnapshot = try XCTUnwrap(BatteryReadingService.fallbackPublicSnapshot(from: smartBattery))

        XCTAssertFalse(fallbackSnapshot.isCharging)
        XCTAssertFalse(fallbackSnapshot.isExternalPowerConnected)
        XCTAssertEqual(fallbackSnapshot.powerSourceState, "Battery Power")
    }

    func testSmartBatteryFallbackPreservesConnectedDischargingWhenExternalFlagAndCurrentDisagree() throws {
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 3_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: -900,
            isExternalPowerConnected: true,
            isCharging: true,
            isFullyCharged: false
        )

        let fallbackSnapshot = try XCTUnwrap(BatteryReadingService.fallbackPublicSnapshot(from: smartBattery))

        XCTAssertFalse(fallbackSnapshot.isCharging)
        XCTAssertTrue(fallbackSnapshot.isExternalPowerConnected)
        XCTAssertEqual(fallbackSnapshot.stateOfChargePercent, 60)
        XCTAssertEqual(fallbackSnapshot.powerSourceState, "AC Power")
    }

    func testSmartBatteryFallbackLetsReportedDisconnectOverrideStaleAdapterWatts() throws {
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 3_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: nil,
            adapterMaxWatts: 70,
            isExternalPowerConnected: false,
            isCharging: false,
            isFullyCharged: false
        )

        let fallbackSnapshot = try XCTUnwrap(BatteryReadingService.fallbackPublicSnapshot(from: smartBattery))

        XCTAssertFalse(fallbackSnapshot.isCharging)
        XCTAssertFalse(fallbackSnapshot.isCharged)
        XCTAssertFalse(fallbackSnapshot.isExternalPowerConnected)
        XCTAssertEqual(fallbackSnapshot.powerSourceState, "Battery Power")
    }

    func testSmartBatteryFallbackSuppressesStalePositiveCurrentWhenReportedDisconnected() throws {
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 3_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: 1_200,
            isExternalPowerConnected: false,
            isCharging: false,
            isFullyCharged: false
        )

        let fallbackSnapshot = try XCTUnwrap(BatteryReadingService.fallbackPublicSnapshot(from: smartBattery))

        XCTAssertFalse(fallbackSnapshot.isCharging)
        XCTAssertFalse(fallbackSnapshot.isExternalPowerConnected)
        XCTAssertEqual(fallbackSnapshot.powerSourceState, "Battery Power")
    }

    func testSmartBatteryFallbackUsesReportedConnectedStateWithoutCurrent() throws {
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 3_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: nil,
            isExternalPowerConnected: true,
            isCharging: false,
            isFullyCharged: false
        )

        let fallbackSnapshot = try XCTUnwrap(BatteryReadingService.fallbackPublicSnapshot(from: smartBattery))

        XCTAssertFalse(fallbackSnapshot.isCharging)
        XCTAssertFalse(fallbackSnapshot.isCharged)
        XCTAssertTrue(fallbackSnapshot.isExternalPowerConnected)
        XCTAssertEqual(fallbackSnapshot.powerSourceState, "AC Power")
    }

    func testSmartBatteryFallbackUsesLiveInputPowerAsExternalEvidence() throws {
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 3_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: nil,
            inputPowerWatts: 31.2,
            isExternalPowerConnected: nil,
            isCharging: false,
            isFullyCharged: false
        )

        let fallbackSnapshot = try XCTUnwrap(BatteryReadingService.fallbackPublicSnapshot(from: smartBattery))

        XCTAssertFalse(fallbackSnapshot.isCharging)
        XCTAssertFalse(fallbackSnapshot.isCharged)
        XCTAssertTrue(fallbackSnapshot.isExternalPowerConnected)
        XCTAssertEqual(fallbackSnapshot.powerSourceState, "AC Power")
    }

    func testSmartBatteryFallbackPreservesLiveInputPowerEvidenceWhileBatteryIsDischarging() throws {
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 3_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: -900,
            inputPowerWatts: 31.2,
            isExternalPowerConnected: true,
            isCharging: false,
            isFullyCharged: false
        )

        let fallbackSnapshot = try XCTUnwrap(BatteryReadingService.fallbackPublicSnapshot(from: smartBattery))

        XCTAssertFalse(fallbackSnapshot.isCharging)
        XCTAssertTrue(fallbackSnapshot.isExternalPowerConnected)
        XCTAssertEqual(fallbackSnapshot.powerSourceState, "AC Power")
    }

    func testSmartBatteryFallbackUsesReportedFullyChargedStateWithoutCurrent() throws {
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 5_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: nil,
            isExternalPowerConnected: true,
            isCharging: false,
            isFullyCharged: true
        )

        let fallbackSnapshot = try XCTUnwrap(BatteryReadingService.fallbackPublicSnapshot(from: smartBattery))

        XCTAssertFalse(fallbackSnapshot.isCharging)
        XCTAssertTrue(fallbackSnapshot.isCharged)
        XCTAssertTrue(fallbackSnapshot.isExternalPowerConnected)
        XCTAssertEqual(fallbackSnapshot.powerSourceState, "AC Power")
    }

    func testSmartBatteryFallbackSuppressesFullyChargedFlagWhenReportedDisconnected() throws {
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 5_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: nil,
            isExternalPowerConnected: false,
            isCharging: false,
            isFullyCharged: true
        )

        let fallbackSnapshot = try XCTUnwrap(BatteryReadingService.fallbackPublicSnapshot(from: smartBattery))

        XCTAssertFalse(fallbackSnapshot.isCharging)
        XCTAssertFalse(fallbackSnapshot.isCharged)
        XCTAssertFalse(fallbackSnapshot.isExternalPowerConnected)
        XCTAssertEqual(fallbackSnapshot.powerSourceState, "Battery Power")
    }

    func testSmartBatteryFallbackDoesNotForceFullPercentWhenDisconnectedChargedFlagContradictsEmptyCurrent() throws {
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 0,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: nil,
            isExternalPowerConnected: false,
            isCharging: false,
            isFullyCharged: true
        )

        let fallbackSnapshot = try XCTUnwrap(BatteryReadingService.fallbackPublicSnapshot(from: smartBattery))

        XCTAssertFalse(fallbackSnapshot.isCharged)
        XCTAssertFalse(fallbackSnapshot.isExternalPowerConnected)
        XCTAssertEqual(fallbackSnapshot.stateOfChargePercent, 0)
    }

    func testSmartBatteryFallbackDoesNotForceFullPercentWhenChargedFlagContradictsPartialCapacity() throws {
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 3_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: nil,
            isExternalPowerConnected: true,
            isCharging: false,
            isFullyCharged: true
        )

        let fallbackSnapshot = try XCTUnwrap(BatteryReadingService.fallbackPublicSnapshot(from: smartBattery))

        XCTAssertFalse(fallbackSnapshot.isCharged)
        XCTAssertTrue(fallbackSnapshot.isExternalPowerConnected)
        XCTAssertEqual(fallbackSnapshot.stateOfChargePercent, 60)
    }

    func testValidInternalPublicSourceIsPreferredOverFallback() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: false,
            isCharged: false,
            isExternalPowerConnected: false,
            isInternalBattery: true,
            stateOfChargePercent: 42,
            powerSourceState: "Battery Power",
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 4_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: -500
        )

        let resolvedSnapshot = try XCTUnwrap(BatteryReadingService.resolvedPublicSnapshot(
            publicSnapshot: publicSnapshot,
            smartBattery: smartBattery
        ))

        XCTAssertEqual(resolvedSnapshot.stateOfChargePercent, 42)
    }

    func testPublicBatterySourceIgnoresSmartInputPowerAboveAdapterCapability() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: false,
            isCharged: false,
            isExternalPowerConnected: false,
            isInternalBattery: true,
            stateOfChargePercent: 42,
            powerSourceState: "Battery Power",
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 3_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: 1_200,
            inputPowerWatts: 100,
            adapterMaxWatts: 70,
            isExternalPowerConnected: nil,
            isCharging: false,
            isFullyCharged: false
        )

        let resolvedSnapshot = try XCTUnwrap(BatteryReadingService.resolvedPublicSnapshot(
            publicSnapshot: publicSnapshot,
            smartBattery: smartBattery
        ))

        XCTAssertFalse(resolvedSnapshot.isCharging)
        XCTAssertFalse(resolvedSnapshot.isExternalPowerConnected)
        XCTAssertEqual(resolvedSnapshot.powerSourceState, "Battery Power")
    }

    func testSmartBatteryReportedTimeFillsMissingPublicEstimates() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: true,
            isCharged: false,
            isExternalPowerConnected: true,
            isInternalBattery: true,
            stateOfChargePercent: 16,
            powerSourceState: "AC Power",
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 725,
            fullChargeCapacityMilliampHours: 4_525,
            signedCurrentMilliamps: 4_387,
            reportedTimeToFullMinutes: 112
        )

        XCTAssertEqual(
            BatteryReadingService.reportedTimeToFullMinutes(
                publicSnapshot: publicSnapshot,
                smartBattery: smartBattery
            ),
            112
        )
    }

    func testPublicReportedTimeWinsOverSmartBatteryEstimate() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: true,
            isCharged: false,
            isExternalPowerConnected: true,
            isInternalBattery: true,
            stateOfChargePercent: 16,
            timeToFullMinutes: 25,
            powerSourceState: "AC Power",
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 725,
            fullChargeCapacityMilliampHours: 4_525,
            signedCurrentMilliamps: 4_387,
            reportedTimeToFullMinutes: 112
        )

        XCTAssertEqual(
            BatteryReadingService.reportedTimeToFullMinutes(
                publicSnapshot: publicSnapshot,
                smartBattery: smartBattery
            ),
            25
        )
    }

    func testPlaceholderPublicTimeToFullFallsBackToSmartBatteryEstimate() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: true,
            isCharged: false,
            isExternalPowerConnected: true,
            isInternalBattery: true,
            stateOfChargePercent: 16,
            timeToFullMinutes: 0,
            powerSourceState: "AC Power",
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 725,
            fullChargeCapacityMilliampHours: 4_525,
            signedCurrentMilliamps: 4_387,
            reportedTimeToFullMinutes: 112
        )

        XCTAssertEqual(
            BatteryReadingService.reportedTimeToFullMinutes(
                publicSnapshot: publicSnapshot,
                smartBattery: smartBattery
            ),
            112
        )
    }

    func testZeroReportedTimeToFullIsIgnoredWhenChargingBelowFull() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: true,
            isCharged: false,
            isExternalPowerConnected: true,
            isInternalBattery: true,
            stateOfChargePercent: 16,
            timeToFullMinutes: 0,
            powerSourceState: "AC Power",
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 725,
            fullChargeCapacityMilliampHours: 4_525,
            signedCurrentMilliamps: 4_387,
            reportedTimeToFullMinutes: 0
        )

        let reportedTimeToFullMinutes = BatteryReadingService.reportedTimeToFullMinutes(
            publicSnapshot: publicSnapshot,
            smartBattery: smartBattery
        )
        let computedTimeToFullMinutes = BatteryCalculations.estimatedTimeToFullMinutes(
            currentChargeMilliampHours: smartBattery.currentChargeMilliampHours,
            fullChargeCapacityMilliampHours: smartBattery.fullChargeCapacityMilliampHours,
            chargeCurrentMilliamps: BatteryCalculations.chargeRateMilliamps(from: smartBattery.signedCurrentMilliamps),
            reportedTimeToFullMinutes: reportedTimeToFullMinutes
        )

        XCTAssertNil(reportedTimeToFullMinutes)
        XCTAssertNotNil(computedTimeToFullMinutes)
    }

    func testZeroReportedTimeToFullIsKeptWhenBatteryIsFull() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: false,
            isCharged: true,
            isExternalPowerConnected: true,
            isInternalBattery: true,
            stateOfChargePercent: 100,
            timeToFullMinutes: 0,
            powerSourceState: "AC Power",
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 4_525,
            fullChargeCapacityMilliampHours: 4_525,
            signedCurrentMilliamps: 0,
            reportedTimeToFullMinutes: 0,
            isFullyCharged: true
        )

        XCTAssertEqual(
            BatteryReadingService.reportedTimeToFullMinutes(
                publicSnapshot: publicSnapshot,
                smartBattery: smartBattery
            ),
            0
        )
    }

    func testInvalidSmartReportedTimeToFullDoesNotBlockComputedFallback() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: true,
            isCharged: false,
            isExternalPowerConnected: true,
            isInternalBattery: true,
            stateOfChargePercent: 16,
            powerSourceState: "AC Power",
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 725,
            fullChargeCapacityMilliampHours: 4_525,
            signedCurrentMilliamps: 4_387,
            reportedTimeToFullMinutes: Int.max
        )

        let reportedTimeToFullMinutes = BatteryReadingService.reportedTimeToFullMinutes(
            publicSnapshot: publicSnapshot,
            smartBattery: smartBattery
        )
        let computedTimeToFullMinutes = BatteryCalculations.estimatedTimeToFullMinutes(
            currentChargeMilliampHours: smartBattery.currentChargeMilliampHours,
            fullChargeCapacityMilliampHours: smartBattery.fullChargeCapacityMilliampHours,
            chargeCurrentMilliamps: BatteryCalculations.chargeRateMilliamps(from: smartBattery.signedCurrentMilliamps),
            reportedTimeToFullMinutes: reportedTimeToFullMinutes
        )

        XCTAssertNil(reportedTimeToFullMinutes)
        XCTAssertNotNil(computedTimeToFullMinutes)
    }

    func testInvalidSmartReportedTimeToEmptyIsIgnored() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: false,
            isCharged: false,
            isExternalPowerConnected: false,
            isInternalBattery: true,
            stateOfChargePercent: 60,
            powerSourceState: nil,
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 3_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: -900,
            reportedTimeToEmptyMinutes: Int.max
        )

        XCTAssertNil(BatteryReadingService.reportedSystemTimeRemainingMinutes(
            publicSnapshot: publicSnapshot,
            smartBattery: smartBattery
        ))
    }

    func testPlaceholderPublicTimeToEmptyFallsBackToSmartBatteryEstimate() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: false,
            isCharged: false,
            isExternalPowerConnected: false,
            isInternalBattery: true,
            stateOfChargePercent: 60,
            systemTimeRemainingMinutes: 0,
            powerSourceState: "Battery Power",
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 3_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: -900,
            reportedTimeToEmptyMinutes: 200
        )

        XCTAssertEqual(
            BatteryReadingService.reportedSystemTimeRemainingMinutes(
                publicSnapshot: publicSnapshot,
                smartBattery: smartBattery
            ),
            200
        )
    }

    func testZeroReportedTimeToEmptyIsIgnoredWhenBatteryHasCharge() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: false,
            isCharged: false,
            isExternalPowerConnected: false,
            isInternalBattery: true,
            stateOfChargePercent: 60,
            systemTimeRemainingMinutes: 0,
            powerSourceState: "Battery Power",
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 3_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: -900,
            reportedTimeToEmptyMinutes: 0
        )

        let reportedTimeToEmptyMinutes = BatteryReadingService.reportedSystemTimeRemainingMinutes(
            publicSnapshot: publicSnapshot,
            smartBattery: smartBattery
        )
        let computedTimeToEmptyMinutes = BatteryCalculations.timeRemainingMinutes(
            currentChargeMilliampHours: smartBattery.currentChargeMilliampHours,
            dischargeRateMilliamps: BatteryCalculations.dischargeRateMilliamps(from: smartBattery.signedCurrentMilliamps)
        )

        XCTAssertNil(reportedTimeToEmptyMinutes)
        XCTAssertNotNil(computedTimeToEmptyMinutes)
    }

    func testZeroReportedTimeToEmptyIsKeptWhenBatteryIsEmpty() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: false,
            isCharged: false,
            isExternalPowerConnected: false,
            isInternalBattery: true,
            stateOfChargePercent: 0,
            systemTimeRemainingMinutes: 0,
            powerSourceState: "Battery Power",
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 0,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: -900,
            reportedTimeToEmptyMinutes: 0
        )

        XCTAssertEqual(
            BatteryReadingService.reportedSystemTimeRemainingMinutes(
                publicSnapshot: publicSnapshot,
                smartBattery: smartBattery
            ),
            0
        )
    }

    func testChargedFlagSuppliesFullPercentWhenSmartCurrentIsTransientlyEmpty() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: false,
            isCharged: true,
            isExternalPowerConnected: true,
            isInternalBattery: true,
            stateOfChargePercent: nil,
            powerSourceState: "AC Power",
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 0,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: nil,
            isExternalPowerConnected: true,
            isCharging: false,
            isFullyCharged: true
        )

        let isCharged = reconciledChargedState(publicSnapshot: publicSnapshot, smartBattery: smartBattery)
        let trustedPercent = BatteryReadingService.trustedPublicStateOfChargePercent(
            publicSnapshot: publicSnapshot,
            isCharged: isCharged
        )
        let currentCharge = BatteryCalculations.reconciledCurrentChargeMilliampHours(
            smartCurrentChargeMilliampHours: smartBattery.currentChargeMilliampHours,
            fullChargeCapacityMilliampHours: smartBattery.fullChargeCapacityMilliampHours,
            publicPercentage: trustedPercent
        )
        let stateOfChargePercent = BatteryCalculations.stateOfChargePercent(
            currentChargeMilliampHours: currentCharge,
            fullChargeCapacityMilliampHours: smartBattery.fullChargeCapacityMilliampHours,
            publicPercentage: trustedPercent
        )

        XCTAssertEqual(trustedPercent, 100)
        XCTAssertEqual(currentCharge, 5_000)
        XCTAssertEqual(stateOfChargePercent, 100)
    }

    func testPublicPercentVetoesStaleChargedFlagWhenSmartCurrentIsTransientlyEmpty() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: false,
            isCharged: true,
            isExternalPowerConnected: true,
            isInternalBattery: true,
            stateOfChargePercent: 80,
            powerSourceState: "AC Power",
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 0,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: nil,
            isExternalPowerConnected: true,
            isCharging: false,
            isFullyCharged: true
        )

        let isCharged = reconciledChargedState(publicSnapshot: publicSnapshot, smartBattery: smartBattery)
        let trustedPercent = BatteryReadingService.trustedPublicStateOfChargePercent(
            publicSnapshot: publicSnapshot,
            isCharged: isCharged
        )

        XCTAssertFalse(isCharged)
        XCTAssertEqual(trustedPercent, 80)
    }

    func testDischargeCurrentPreventsStaleChargedFlagFromForcingFullPercent() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: false,
            isCharged: true,
            isExternalPowerConnected: false,
            isInternalBattery: true,
            stateOfChargePercent: 80,
            powerSourceState: "Battery Power",
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 4_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: -900,
            isExternalPowerConnected: false,
            isCharging: false,
            isFullyCharged: true
        )

        let isCharged = reconciledChargedState(publicSnapshot: publicSnapshot, smartBattery: smartBattery)
        let trustedPercent = BatteryReadingService.trustedPublicStateOfChargePercent(
            publicSnapshot: publicSnapshot,
            isCharged: isCharged
        )

        XCTAssertFalse(isCharged)
        XCTAssertEqual(trustedPercent, 80)
    }

    func testPartialCapacityPreventsStaleChargedFlagFromForcingFullPercent() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: false,
            isCharged: true,
            isExternalPowerConnected: true,
            isInternalBattery: true,
            stateOfChargePercent: nil,
            powerSourceState: "AC Power",
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 3_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: nil,
            isExternalPowerConnected: true,
            isCharging: false,
            isFullyCharged: true
        )

        let isCharged = reconciledChargedState(publicSnapshot: publicSnapshot, smartBattery: smartBattery)
        let trustedPercent = BatteryReadingService.trustedPublicStateOfChargePercent(
            publicSnapshot: publicSnapshot,
            isCharged: isCharged
        )
        let currentCharge = BatteryCalculations.reconciledCurrentChargeMilliampHours(
            smartCurrentChargeMilliampHours: smartBattery.currentChargeMilliampHours,
            fullChargeCapacityMilliampHours: smartBattery.fullChargeCapacityMilliampHours,
            publicPercentage: trustedPercent
        )
        let stateOfChargePercent = BatteryCalculations.stateOfChargePercent(
            currentChargeMilliampHours: currentCharge,
            fullChargeCapacityMilliampHours: smartBattery.fullChargeCapacityMilliampHours,
            publicPercentage: trustedPercent
        )

        XCTAssertFalse(isCharged)
        XCTAssertNil(trustedPercent)
        XCTAssertEqual(currentCharge, 3_000)
        XCTAssertEqual(stateOfChargePercent, 60)
    }

    func testTransientPublicEmptyPercentDoesNotOverridePlausibleSmartCapacity() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: false,
            isCharged: false,
            isExternalPowerConnected: false,
            isInternalBattery: true,
            stateOfChargePercent: 0,
            powerSourceState: "Battery Power",
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 4_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: -900,
            isExternalPowerConnected: false,
            isCharging: false,
            isFullyCharged: false
        )

        let isCharged = reconciledChargedState(publicSnapshot: publicSnapshot, smartBattery: smartBattery)
        let trustedPercent = BatteryReadingService.trustedPublicStateOfChargePercent(
            publicSnapshot: publicSnapshot,
            isCharged: isCharged
        )
        let currentCharge = BatteryCalculations.reconciledCurrentChargeMilliampHours(
            smartCurrentChargeMilliampHours: smartBattery.currentChargeMilliampHours,
            fullChargeCapacityMilliampHours: smartBattery.fullChargeCapacityMilliampHours,
            publicPercentage: trustedPercent
        )
        let stateOfChargePercent = BatteryCalculations.stateOfChargePercent(
            currentChargeMilliampHours: currentCharge,
            fullChargeCapacityMilliampHours: smartBattery.fullChargeCapacityMilliampHours,
            publicPercentage: trustedPercent
        )

        XCTAssertFalse(isCharged)
        XCTAssertEqual(trustedPercent, 0)
        XCTAssertEqual(currentCharge, 4_000)
        XCTAssertEqual(stateOfChargePercent, 80)
    }

    func testTransientPublicLowPercentDoesNotOverridePlausibleSmartCapacity() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: false,
            isCharged: false,
            isExternalPowerConnected: false,
            isInternalBattery: true,
            stateOfChargePercent: 6,
            powerSourceState: "Battery Power",
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 4_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: -900,
            isExternalPowerConnected: false,
            isCharging: false,
            isFullyCharged: false
        )

        let isCharged = reconciledChargedState(publicSnapshot: publicSnapshot, smartBattery: smartBattery)
        let trustedPercent = BatteryReadingService.trustedPublicStateOfChargePercent(
            publicSnapshot: publicSnapshot,
            isCharged: isCharged
        )
        let currentCharge = BatteryCalculations.reconciledCurrentChargeMilliampHours(
            smartCurrentChargeMilliampHours: smartBattery.currentChargeMilliampHours,
            fullChargeCapacityMilliampHours: smartBattery.fullChargeCapacityMilliampHours,
            publicPercentage: trustedPercent
        )
        let stateOfChargePercent = BatteryCalculations.stateOfChargePercent(
            currentChargeMilliampHours: currentCharge,
            fullChargeCapacityMilliampHours: smartBattery.fullChargeCapacityMilliampHours,
            publicPercentage: trustedPercent
        )

        XCTAssertFalse(isCharged)
        XCTAssertEqual(trustedPercent, 6)
        XCTAssertEqual(currentCharge, 4_000)
        XCTAssertEqual(stateOfChargePercent, 80)
    }

    func testSmartPowerFlagsFillStalePublicPowerState() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: false,
            isCharged: false,
            isExternalPowerConnected: false,
            isInternalBattery: true,
            stateOfChargePercent: 60,
            powerSourceState: nil,
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 3_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: nil,
            isExternalPowerConnected: true,
            isCharging: false,
            isFullyCharged: false
        )

        let powerState = reconciledPowerState(publicSnapshot: publicSnapshot, smartBattery: smartBattery)

        XCTAssertEqual(powerState, .connectedNotCharging)
    }

    func testSmartDisconnectWinsOverPublicACPowerWhenCurrentIsUnavailable() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: false,
            isCharged: false,
            isExternalPowerConnected: true,
            isInternalBattery: true,
            stateOfChargePercent: 60,
            powerSourceState: "AC Power",
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 3_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: nil,
            isExternalPowerConnected: false,
            isCharging: false,
            isFullyCharged: false
        )

        let powerState = reconciledPowerState(publicSnapshot: publicSnapshot, smartBattery: smartBattery)

        XCTAssertEqual(powerState, .onBattery)
    }

    func testSmartDisconnectWithDischargeCurrentSuppressesPublicACPower() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: false,
            isCharged: false,
            isExternalPowerConnected: true,
            isInternalBattery: true,
            stateOfChargePercent: 60,
            powerSourceState: "AC Power",
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 3_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: -900,
            isExternalPowerConnected: false,
            isCharging: false,
            isFullyCharged: false
        )

        let powerState = reconciledPowerState(publicSnapshot: publicSnapshot, smartBattery: smartBattery)

        XCTAssertEqual(powerState, .onBattery)
    }

    func testExplicitPublicBatteryPowerSuppressesStalePublicChargingFlagWhenCurrentIsUnavailable() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: true,
            isCharged: false,
            isExternalPowerConnected: true,
            isInternalBattery: true,
            stateOfChargePercent: 60,
            powerSourceState: "Battery Power",
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 3_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: nil,
            isExternalPowerConnected: nil,
            isCharging: nil,
            isFullyCharged: nil
        )

        let powerState = reconciledPowerState(publicSnapshot: publicSnapshot, smartBattery: smartBattery)

        XCTAssertEqual(powerState, .onBattery)
    }

    func testExplicitPublicBatteryPowerStateIsWhitespaceAndCaseInsensitive() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: false,
            isCharged: false,
            isExternalPowerConnected: false,
            isInternalBattery: true,
            stateOfChargePercent: 60,
            powerSourceState: " battery power\n",
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 3_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: 900,
            isExternalPowerConnected: true,
            isCharging: true,
            isFullyCharged: false
        )

        let powerState = reconciledPowerState(publicSnapshot: publicSnapshot, smartBattery: smartBattery)

        XCTAssertEqual(powerState, .onBattery)
    }

    func testExplicitPublicBatteryPowerSuppressesStalePublicChargedFlagWhenCurrentIsUnavailable() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: false,
            isCharged: true,
            isExternalPowerConnected: true,
            isInternalBattery: true,
            stateOfChargePercent: 100,
            powerSourceState: "Battery Power",
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 5_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: nil,
            isExternalPowerConnected: nil,
            isCharging: nil,
            isFullyCharged: nil
        )

        let isCharged = reconciledChargedState(publicSnapshot: publicSnapshot, smartBattery: smartBattery)
        let powerState = reconciledPowerState(
            publicSnapshot: publicSnapshot,
            smartBattery: smartBattery,
            isCharged: isCharged
        )

        XCTAssertFalse(isCharged)
        XCTAssertEqual(powerState, .onBattery)
    }

    func testExplicitPublicBatteryPowerSuppressesStaleSmartExternalPowerFlagWhenCurrentIsUnavailable() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: false,
            isCharged: false,
            isExternalPowerConnected: false,
            isInternalBattery: true,
            stateOfChargePercent: 60,
            powerSourceState: "Battery Power",
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 3_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: nil,
            isExternalPowerConnected: true,
            isCharging: false,
            isFullyCharged: false
        )

        let powerState = reconciledPowerState(publicSnapshot: publicSnapshot, smartBattery: smartBattery)

        XCTAssertEqual(powerState, .onBattery)
    }

    func testSmartChargingFlagImpliesExternalPowerWhenPublicStateIsStale() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: false,
            isCharged: false,
            isExternalPowerConnected: false,
            isInternalBattery: true,
            stateOfChargePercent: 60,
            powerSourceState: nil,
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 3_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: nil,
            isExternalPowerConnected: nil,
            isCharging: true,
            isFullyCharged: false
        )

        let powerState = reconciledPowerState(publicSnapshot: publicSnapshot, smartBattery: smartBattery)

        XCTAssertEqual(powerState, .charging)
    }

    func testExplicitPublicBatteryPowerSuppressesStaleSmartChargingFlagWhenCurrentIsUnavailable() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: false,
            isCharged: false,
            isExternalPowerConnected: false,
            isInternalBattery: true,
            stateOfChargePercent: 60,
            powerSourceState: "Battery Power",
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 3_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: nil,
            isExternalPowerConnected: nil,
            isCharging: true,
            isFullyCharged: false
        )

        let powerState = reconciledPowerState(publicSnapshot: publicSnapshot, smartBattery: smartBattery)

        XCTAssertEqual(powerState, .onBattery)
    }

    func testExplicitPublicBatteryPowerSuppressesStaleLiveInputPowerAsConnected() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: false,
            isCharged: false,
            isExternalPowerConnected: false,
            isInternalBattery: true,
            stateOfChargePercent: 60,
            powerSourceState: "Battery Power",
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 3_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: nil,
            inputPowerWatts: 31.2,
            isExternalPowerConnected: nil,
            isCharging: false,
            isFullyCharged: false
        )

        let powerState = reconciledPowerState(publicSnapshot: publicSnapshot, smartBattery: smartBattery)

        XCTAssertEqual(powerState, .onBattery)
    }

    func testExplicitPublicBatteryPowerAndDischargeCurrentSuppressStaleInputPower() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: false,
            isCharged: false,
            isExternalPowerConnected: false,
            isInternalBattery: true,
            stateOfChargePercent: 60,
            powerSourceState: "Battery Power",
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 3_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: -900,
            inputPowerWatts: 31.2,
            isExternalPowerConnected: nil,
            isCharging: false,
            isFullyCharged: false
        )

        let powerState = reconciledPowerState(publicSnapshot: publicSnapshot, smartBattery: smartBattery)

        XCTAssertEqual(powerState, .onBattery)
    }

    func testExplicitPublicBatteryPowerSuppressesCounterBackedInputPower() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: false,
            isCharged: false,
            isExternalPowerConnected: false,
            isInternalBattery: true,
            stateOfChargePercent: 60,
            powerSourceState: "Battery Power",
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 3_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: -900,
            inputPowerWatts: 31.2,
            inputPowerEvidence: .counterBacked,
            isExternalPowerConnected: nil,
            isCharging: false,
            isFullyCharged: false
        )

        let powerState = reconciledPowerState(publicSnapshot: publicSnapshot, smartBattery: smartBattery)

        XCTAssertEqual(powerState, .onBattery)
    }

    func testExplicitPublicBatteryPowerSuppressesLiveInputPowerAndPositiveCurrent() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: false,
            isCharged: false,
            isExternalPowerConnected: false,
            isInternalBattery: true,
            stateOfChargePercent: 60,
            powerSourceState: "Battery Power",
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 3_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: 1_200,
            inputPowerWatts: 31.2,
            isExternalPowerConnected: nil,
            isCharging: true,
            isFullyCharged: false
        )

        let powerState = reconciledPowerState(publicSnapshot: publicSnapshot, smartBattery: smartBattery)

        XCTAssertEqual(powerState, .onBattery)
    }

    func testExplicitPublicBatteryPowerSuppressesStalePositiveCurrent() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: false,
            isCharged: false,
            isExternalPowerConnected: false,
            isInternalBattery: true,
            stateOfChargePercent: 60,
            powerSourceState: "Battery Power",
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 3_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: 1_200,
            isExternalPowerConnected: nil,
            isCharging: true,
            isFullyCharged: false
        )

        let powerState = reconciledPowerState(publicSnapshot: publicSnapshot, smartBattery: smartBattery)

        XCTAssertEqual(powerState, .onBattery)
    }

    func testExplicitPublicBatteryPowerSuppressesStaleSmartFullChargeFlag() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: false,
            isCharged: false,
            isExternalPowerConnected: false,
            isInternalBattery: true,
            stateOfChargePercent: 100,
            powerSourceState: "Battery Power",
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 5_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: nil,
            isExternalPowerConnected: nil,
            isCharging: false,
            isFullyCharged: true
        )

        let isCharged = reconciledChargedState(publicSnapshot: publicSnapshot, smartBattery: smartBattery)
        let powerState = reconciledPowerState(
            publicSnapshot: publicSnapshot,
            smartBattery: smartBattery,
            isCharged: isCharged
        )

        XCTAssertFalse(isCharged)
        XCTAssertEqual(powerState, .onBattery)
    }

    func testSmartDisconnectSuppressesStalePublicChargedFlagDuringReconciliation() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: false,
            isCharged: true,
            isExternalPowerConnected: true,
            isInternalBattery: true,
            stateOfChargePercent: 100,
            powerSourceState: "AC Power",
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 5_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: nil,
            isExternalPowerConnected: false,
            isCharging: false,
            isFullyCharged: true
        )

        let powerState = reconciledPowerState(publicSnapshot: publicSnapshot, smartBattery: smartBattery)

        XCTAssertEqual(powerState, .onBattery)
    }

    func testSmartDisconnectOverridesStalePublicACAndChargingTelemetry() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: true,
            isCharged: false,
            isExternalPowerConnected: true,
            isInternalBattery: true,
            stateOfChargePercent: 75,
            timeToFullMinutes: 55,
            powerSourceState: "AC Power",
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 3_439,
            fullChargeCapacityMilliampHours: 4_592,
            signedCurrentMilliamps: 707,
            inputPowerWatts: 8.8,
            adapterMaxWatts: 100,
            reportedTimeToFullMinutes: 55,
            isExternalPowerConnected: false,
            isCharging: true,
            isFullyCharged: false
        )
        let reconciledCurrent = BatteryReadingService.reconciledSignedCurrentMilliamps(
            publicSnapshot: publicSnapshot,
            smartBattery: smartBattery,
            signedCurrentMilliamps: smartBattery.signedCurrentMilliamps
        )
        let powerState = reconciledPowerState(
            publicSnapshot: publicSnapshot,
            smartBattery: smartBattery,
            signedCurrentMilliamps: reconciledCurrent
        )

        XCTAssertNil(reconciledCurrent)
        XCTAssertEqual(powerState, .onBattery)
        XCTAssertNil(BatteryTelemetrySanitization.displayableAdapterMaxWatts(smartBattery.adapterMaxWatts, powerState: powerState))
        XCTAssertNil(BatteryTelemetrySanitization.displayableInputPowerWatts(
            smartBattery.inputPowerWatts,
            adapterMaxWatts: smartBattery.adapterMaxWatts,
            powerState: powerState
        ))
        XCTAssertNil(BatteryTelemetrySanitization.displayablePowerRates(
            powerState: powerState,
            chargeRateWatts: 8.8,
            dischargeRateWatts: nil
        ).chargeRateWatts)
        XCTAssertNil(BatteryTelemetrySanitization.displayableTiming(
            powerState: powerState,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: smartBattery.reportedTimeToFullMinutes
        ).timeToFullMinutes)
    }

    func testDischargeCurrentStillWinsOverSmartExternalPowerFlag() throws {
        let publicSnapshot = makePublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: false,
            isCharged: false,
            isExternalPowerConnected: false,
            isInternalBattery: true,
            stateOfChargePercent: 60,
            powerSourceState: "Battery Power",
        )
        let smartBattery = makeSmartBatteryDetails(
            currentChargeMilliampHours: 3_000,
            fullChargeCapacityMilliampHours: 5_000,
            signedCurrentMilliamps: -900,
            isExternalPowerConnected: true,
            isCharging: false,
            isFullyCharged: false
        )

        let powerState = reconciledPowerState(publicSnapshot: publicSnapshot, smartBattery: smartBattery)

        XCTAssertEqual(powerState, .onBattery)
    }

    func testAdapterWattageOnlyDisplaysForExternalPowerStates() {
        XCTAssertEqual(
            BatteryTelemetrySanitization.displayableAdapterMaxWatts(70, powerState: .charging),
            70
        )
        XCTAssertEqual(
            BatteryTelemetrySanitization.displayableAdapterMaxWatts(70, powerState: .connectedDischarging),
            70
        )
        XCTAssertEqual(
            BatteryTelemetrySanitization.displayableAdapterMaxWatts(70, powerState: .connectedNotCharging),
            70
        )
        XCTAssertEqual(
            BatteryTelemetrySanitization.displayableAdapterMaxWatts(70, powerState: .fullOnAC),
            70
        )
        XCTAssertNil(BatteryTelemetrySanitization.displayableAdapterMaxWatts(70, powerState: .onBattery))
        XCTAssertNil(BatteryTelemetrySanitization.displayableAdapterMaxWatts(70, powerState: .unknown))
        XCTAssertNil(BatteryTelemetrySanitization.displayableAdapterMaxWatts(Int.max, powerState: .charging))
    }

    func testPowerRatesOnlyDisplayForActivePowerStates() {
        let chargingRates = BatteryTelemetrySanitization.displayablePowerRates(
            powerState: .charging,
            chargeRateWatts: 18,
            dischargeRateWatts: 14
        )
        XCTAssertEqual(chargingRates.chargeRateWatts, 18)
        XCTAssertNil(chargingRates.dischargeRateWatts)

        let batteryRates = BatteryTelemetrySanitization.displayablePowerRates(
            powerState: .onBattery,
            chargeRateWatts: 18,
            dischargeRateWatts: 14
        )
        XCTAssertNil(batteryRates.chargeRateWatts)
        XCTAssertEqual(batteryRates.dischargeRateWatts, 14)

        let connectedDischargingRates = BatteryTelemetrySanitization.displayablePowerRates(
            powerState: .connectedDischarging,
            chargeRateWatts: 18,
            dischargeRateWatts: 14
        )
        XCTAssertNil(connectedDischargingRates.chargeRateWatts)
        XCTAssertEqual(connectedDischargingRates.dischargeRateWatts, 14)

        for powerState in [BatteryPowerState.connectedNotCharging, .fullOnAC, .unknown] {
            let idleRates = BatteryTelemetrySanitization.displayablePowerRates(
                powerState: powerState,
                chargeRateWatts: 18,
                dischargeRateWatts: 14
            )
            XCTAssertNil(idleRates.chargeRateWatts)
            XCTAssertNil(idleRates.dischargeRateWatts)
        }
    }

    func testInputPowerDisplaysForExternalPowerStates() throws {
        for powerState in [BatteryPowerState.charging, .connectedDischarging, .connectedNotCharging, .fullOnAC] {
            XCTAssertEqual(
                try XCTUnwrap(BatteryTelemetrySanitization.displayableInputPowerWatts(39.8, powerState: powerState)),
                39.8,
                accuracy: 0.001
            )
        }

        XCTAssertNil(BatteryTelemetrySanitization.displayableInputPowerWatts(39.8, powerState: .onBattery))
        XCTAssertNil(BatteryTelemetrySanitization.displayableInputPowerWatts(39.8, powerState: .unknown))
        XCTAssertNil(BatteryTelemetrySanitization.displayableInputPowerWatts(.infinity, powerState: .charging))
        XCTAssertNil(BatteryTelemetrySanitization.displayableInputPowerWatts(100, adapterMaxWatts: nil, powerState: .charging))
        XCTAssertNil(BatteryTelemetrySanitization.displayableInputPowerWatts(100, adapterMaxWatts: 70, powerState: .charging))
        XCTAssertNil(BatteryTelemetrySanitization.displayableInputPowerWatts(100, adapterMaxWatts: 100, powerState: .charging))
        XCTAssertEqual(
            try XCTUnwrap(BatteryTelemetrySanitization.displayableInputPowerWatts(80.5, adapterMaxWatts: 70, powerState: .charging)),
            80.5,
            accuracy: 0.001
        )
    }

    func testChargingRateStaysBatteryCurrentWhenVerifiedLiveInputPowerExists() throws {
        XCTAssertEqual(
            try XCTUnwrap(chargeRateWatts(
                voltageMillivolts: 12_044,
                signedCurrentMilliamps: 2_111,
                adapterMaxWatts: 100
            )),
            25.424884,
            accuracy: 0.001
        )
    }

    func testChargingPowerUsesBatteryCurrentWhenInputPowerIsUnavailable() throws {
        XCTAssertEqual(
            try XCTUnwrap(chargeRateWatts(
                voltageMillivolts: 12_044,
                signedCurrentMilliamps: 2_111,
                adapterMaxWatts: 100
            )),
            25.424884,
            accuracy: 0.001
        )
    }

    func testChargingPowerFallsBackToBatteryCurrentWhenInputPowerMirrorsAdapterCapability() throws {
        XCTAssertEqual(
            try XCTUnwrap(chargeRateWatts(
                voltageMillivolts: 12_044,
                signedCurrentMilliamps: 2_111,
                adapterMaxWatts: 100
            )),
            25.424884,
            accuracy: 0.001
        )
    }

    func testChargingPowerDoesNotUseBatteryCurrentWattsAboveAdapterContract() {
        XCTAssertNil(chargeRateWatts(
            voltageMillivolts: 12_000,
            signedCurrentMilliamps: 8_333,
            adapterMaxWatts: 70
        ))
    }

    func testChargingPowerUsesCurrentDerivedRateNearAdapterCapability() throws {
        XCTAssertEqual(
            try XCTUnwrap(chargeRateWatts(
                voltageMillivolts: 12_000,
                signedCurrentMilliamps: 5_785,
                adapterMaxWatts: 70
            )),
            69.42,
            accuracy: 0.001
        )
    }

    func testChargingPowerDoesNotUseBatteryCurrentThatMirrorsStaleAdapterCapability() {
        XCTAssertNil(chargeRateWatts(
            voltageMillivolts: 12_000,
            signedCurrentMilliamps: 8_333,
            adapterMaxWatts: 100
        ))
    }

    func testChargingPowerDoesNotUseUnverifiedHundredWattBatteryCurrentWithoutAdapterContract() {
        XCTAssertNil(chargeRateWatts(
            voltageMillivolts: 12_000,
            signedCurrentMilliamps: 8_333,
            adapterMaxWatts: nil
        ))
    }

    func testChargingRateStaysBatteryCurrentWhenCounterBackedInputPowerIsNearAdapterCapability() throws {
        XCTAssertEqual(
            try XCTUnwrap(chargeRateWatts(
                voltageMillivolts: 12_044,
                signedCurrentMilliamps: 2_111,
                adapterMaxWatts: 70
            )),
            25.424884,
            accuracy: 0.001
        )
    }

    func testChargingRateDoesNotUseLiveInputPowerWhenBatteryCurrentIsUnavailable() {
        XCTAssertNil(chargeRateWatts(
            voltageMillivolts: 12_044,
            signedCurrentMilliamps: nil,
            adapterMaxWatts: 70
        ))
    }

    func testChargingPowerDoesNotFallBackToUnverifiedHundredWattInputPower() {
        XCTAssertNil(chargeRateWatts(
            voltageMillivolts: 12_044,
            signedCurrentMilliamps: nil,
            adapterMaxWatts: nil
        ))
    }

    func testChargingPowerFallsBackToBatteryCurrentWhenInputPowerIsInvalid() throws {
        XCTAssertEqual(
            try XCTUnwrap(chargeRateWatts(
                voltageMillivolts: 12_044,
                signedCurrentMilliamps: 2_111,
                adapterMaxWatts: 70
            )),
            25.424884,
            accuracy: 0.001
        )
    }

    func testReadPathUsesDynamicChargingPowerForSnapshotChargeRate() throws {
        let source = try Self.loadSource(relativePath: "BatteryStats/Features/Battery/Data/BatteryReadingService.swift")

        XCTAssertSource(
            source,
            contains: [
                "chargeRateWatts: BatteryTelemetrySanitization.chargeRateWattsWithinAdapterContract(\n                voltageMillivolts: voltageMillivolts,",
                "adapterMaxWatts: adapterMaxWatts"
            ],
            excludes: [
                "Self.dynamicChargeRateWatts(",
                "chargeRateWatts: BatteryCalculations.chargeRateWatts(\n                voltageMillivolts: voltageMillivolts,\n                signedCurrentMilliamps: signedCurrentMilliamps"
            ]
        )
    }

    func testTimingOnlyDisplaysForMatchingPowerState() {
        let batteryTiming = BatteryTelemetrySanitization.displayableTiming(
            powerState: .onBattery,
            rateBasedTimeRemainingMinutes: 25,
            systemTimeRemainingMinutes: 24,
            timeToFullMinutes: 20
        )
        XCTAssertEqual(batteryTiming.rateBasedTimeRemainingMinutes, 25)
        XCTAssertEqual(batteryTiming.systemTimeRemainingMinutes, 24)
        XCTAssertNil(batteryTiming.timeToFullMinutes)

        let connectedDischargingTiming = BatteryTelemetrySanitization.displayableTiming(
            powerState: .connectedDischarging,
            rateBasedTimeRemainingMinutes: 25,
            systemTimeRemainingMinutes: 24,
            timeToFullMinutes: 20
        )
        XCTAssertEqual(connectedDischargingTiming.rateBasedTimeRemainingMinutes, 25)
        XCTAssertEqual(connectedDischargingTiming.systemTimeRemainingMinutes, 24)
        XCTAssertNil(connectedDischargingTiming.timeToFullMinutes)

        let chargingTiming = BatteryTelemetrySanitization.displayableTiming(
            powerState: .charging,
            rateBasedTimeRemainingMinutes: 25,
            systemTimeRemainingMinutes: 24,
            timeToFullMinutes: 20
        )
        XCTAssertNil(chargingTiming.rateBasedTimeRemainingMinutes)
        XCTAssertNil(chargingTiming.systemTimeRemainingMinutes)
        XCTAssertEqual(chargingTiming.timeToFullMinutes, 20)

        for powerState in [BatteryPowerState.connectedNotCharging, .fullOnAC, .unknown] {
            let idleTiming = BatteryTelemetrySanitization.displayableTiming(
                powerState: powerState,
                rateBasedTimeRemainingMinutes: 25,
                systemTimeRemainingMinutes: 24,
                timeToFullMinutes: 20
            )
            XCTAssertNil(idleTiming.rateBasedTimeRemainingMinutes)
            XCTAssertNil(idleTiming.systemTimeRemainingMinutes)
            XCTAssertNil(idleTiming.timeToFullMinutes)
        }
    }

    func testPreferredTimeToFullUsesReportedValueBeforeCurrentBasedEstimate() {
        XCTAssertEqual(
            BatteryTelemetrySanitization.preferredTimeToFullMinutes(
                computedTimeToFullMinutes: 38,
                reportedTimeToFullMinutes: 112
            ),
            112
        )
    }

    func testPreferredTimeToFullFallsBackToReportedValueWhenEstimateIsUnavailable() {
        XCTAssertEqual(
            BatteryTelemetrySanitization.preferredTimeToFullMinutes(
                computedTimeToFullMinutes: nil,
                reportedTimeToFullMinutes: 112
            ),
            112
        )

        XCTAssertEqual(
            BatteryTelemetrySanitization.preferredTimeToFullMinutes(
                computedTimeToFullMinutes: Int.max,
                reportedTimeToFullMinutes: 112
            ),
            112
        )
    }

    func testPreferredTimeToFullKeepsReportedTopOffTimeAheadOfComputedZero() {
        XCTAssertEqual(
            BatteryTelemetrySanitization.preferredTimeToFullMinutes(
                computedTimeToFullMinutes: 0,
                reportedTimeToFullMinutes: 112
            ),
            112
        )
    }

    func testDisplayableEnergyEstimatesDoNotDeriveCapacityEnergyFromLiveVoltage() throws {
        let source = try Self.loadSource(relativePath: "BatteryStats/Features/Battery/Data/BatteryReadingService.swift")

        XCTAssertEqual(BatteryCalculations.wattHours(
            milliampHours: 3_000,
            voltageMillivolts: 12_000
        ), 36)
        XCTAssertSource(
            source,
            contains: ["currentChargeWattHours: BatteryCalculations.wattHours(", "fullChargeCapacityWattHours: nil"],
            excludes: ["designCapacityWattHours:"]
        )
    }

    func testDiagnosticRendererPrintsBooleansAsBooleansAndNumbersAsNumbers() {
        let rendered = BatteryReadingService.renderDiagnosticValue([
            "BooleanLiteral": true,
            "FalseNumber": NSNumber(value: false),
            "NumericOne": NSNumber(value: 1),
            "Nested": [
                "TrueNumber": NSNumber(value: true),
                "Integer": NSNumber(value: 42)
            ] as [String: Any]
        ])

        XCTAssertTrue(rendered.contains("BooleanLiteral: true"))
        XCTAssertTrue(rendered.contains("FalseNumber: false"))
        XCTAssertTrue(rendered.contains("TrueNumber: true"))
        XCTAssertTrue(rendered.contains("NumericOne: 1"))
        XCTAssertTrue(rendered.contains("Integer: 42"))
    }

    private func reconciledChargedState(
        publicSnapshot: PublicPowerSourceSnapshot,
        smartBattery: SmartBatteryDetails
    ) -> Bool {
        BatteryReadingService.reconciledChargedState(
            publicSnapshot: publicSnapshot,
            smartBattery: smartBattery,
            signedCurrentMilliamps: smartBattery.signedCurrentMilliamps,
            currentChargeMilliampHours: smartBattery.currentChargeMilliampHours,
            fullChargeCapacityMilliampHours: smartBattery.fullChargeCapacityMilliampHours
        )
    }

    private func reconciledPowerState(
        publicSnapshot: PublicPowerSourceSnapshot,
        smartBattery: SmartBatteryDetails
    ) -> BatteryPowerState {
        BatteryReadingService.reconciledPowerState(
            publicSnapshot: publicSnapshot,
            smartBattery: smartBattery,
            signedCurrentMilliamps: smartBattery.signedCurrentMilliamps,
            currentChargeMilliampHours: smartBattery.currentChargeMilliampHours,
            fullChargeCapacityMilliampHours: smartBattery.fullChargeCapacityMilliampHours
        )
    }

    private func reconciledPowerState(
        publicSnapshot: PublicPowerSourceSnapshot,
        smartBattery: SmartBatteryDetails,
        isCharged: Bool
    ) -> BatteryPowerState {
        BatteryReadingService.reconciledPowerState(
            publicSnapshot: publicSnapshot,
            smartBattery: smartBattery,
            isCharged: isCharged,
            signedCurrentMilliamps: smartBattery.signedCurrentMilliamps,
            currentChargeMilliampHours: smartBattery.currentChargeMilliampHours,
            fullChargeCapacityMilliampHours: smartBattery.fullChargeCapacityMilliampHours
        )
    }

    private func reconciledPowerState(
        publicSnapshot: PublicPowerSourceSnapshot,
        smartBattery: SmartBatteryDetails,
        signedCurrentMilliamps: Int?
    ) -> BatteryPowerState {
        BatteryReadingService.reconciledPowerState(
            publicSnapshot: publicSnapshot,
            smartBattery: smartBattery,
            signedCurrentMilliamps: signedCurrentMilliamps,
            currentChargeMilliampHours: smartBattery.currentChargeMilliampHours,
            fullChargeCapacityMilliampHours: smartBattery.fullChargeCapacityMilliampHours
        )
    }

    private func chargeRateWatts(
        voltageMillivolts: Int?,
        signedCurrentMilliamps: Int?,
        adapterMaxWatts: Int?
    ) -> Double? {
        BatteryTelemetrySanitization.chargeRateWattsWithinAdapterContract(
            voltageMillivolts: voltageMillivolts,
            signedCurrentMilliamps: signedCurrentMilliamps,
            adapterMaxWatts: adapterMaxWatts
        )
    }

    private func makeSmartBatteryDetails(
        currentChargeMilliampHours: Int?,
        fullChargeCapacityMilliampHours: Int?,
        signedCurrentMilliamps: Int?,
        inputPowerWatts: Double? = nil,
        inputPowerEvidence: BatteryInputPowerEvidence? = nil,
        adapterMaxWatts: Int? = nil,
        reportedTimeToEmptyMinutes: Int? = nil,
        reportedTimeToFullMinutes: Int? = nil,
        isExternalPowerConnected: Bool? = nil,
        isCharging: Bool? = nil,
        isFullyCharged: Bool? = nil
    ) -> SmartBatteryDetails {
        SmartBatteryDetails(
            currentChargeMilliampHours: currentChargeMilliampHours,
            fullChargeCapacityMilliampHours: fullChargeCapacityMilliampHours,
            designCapacityMilliampHours: 6_000,
            cycleCount: 120,
            voltageMillivolts: 12_000,
            signedCurrentMilliamps: signedCurrentMilliamps,
            reportedTimeToEmptyMinutes: reportedTimeToEmptyMinutes,
            reportedTimeToFullMinutes: reportedTimeToFullMinutes,
            isExternalPowerConnected: isExternalPowerConnected,
            isCharging: isCharging,
            isFullyCharged: isFullyCharged,
            rawTemperature: 3_200,
            temperatureCelsius: 32,
            manufactureDate: nil,
            inputPowerWatts: inputPowerWatts,
            inputPowerEvidence: inputPowerEvidence,
            adapterMaxWatts: adapterMaxWatts,
            rawProperties: [:]
        )
    }
}
