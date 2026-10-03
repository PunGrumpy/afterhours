import Foundation
import Testing
@testable import AfterhoursCore

private let now = Date(timeIntervalSince1970: 1_790_000_000)

private func minutes(_ count: Double) -> TimeInterval { count * 60 }

// MARK: - What state wins

@Test func turningAfterhoursOffBeatsEverything() {
    #expect(HoldPolicy.state(enabled: false, pausedUntil: now, reason: .working, blocker: "Your Mac is too hot")
            == .disabled)
}

@Test func aPauseBeatsAHoldAndASafetyRule() {
    let until = now.addingTimeInterval(minutes(30))
    #expect(HoldPolicy.state(enabled: true, pausedUntil: until, reason: .working, blocker: "Battery is below 15%")
            == .paused(until: until))
}

@Test func nothingToHoldForIsIdleEvenWhenASafetyRuleApplies() {
    #expect(HoldPolicy.state(enabled: true, pausedUntil: nil, reason: nil, blocker: "Battery is below 15%") == .idle)
}

@Test func aSafetyRuleBlocksAHold() {
    #expect(HoldPolicy.state(enabled: true, pausedUntil: nil, reason: .working, blocker: "Your Mac is too hot")
            == .blocked("Your Mac is too hot"))
}

@Test func workingOrWaitingForYouHolds() {
    #expect(HoldPolicy.state(enabled: true, pausedUntil: nil, reason: .working, blocker: nil) == .holding)
    #expect(HoldPolicy.state(enabled: true, pausedUntil: nil, reason: .waitingForYou(until: nil), blocker: nil).isHolding)
}

// MARK: - Safety rules

private func blocker(thermalCritical: Bool = false, lowPowerMode: Bool = false, respectLowPowerMode: Bool = true,
                     onAC: Bool = false, onlyWhenPluggedIn: Bool = false, batteryPercent: Int? = 80,
                     batteryThreshold: Int = 15) -> String? {
    HoldPolicy.blocker(thermalCritical: thermalCritical, lowPowerMode: lowPowerMode,
                       respectLowPowerMode: respectLowPowerMode, onAC: onAC, onlyWhenPluggedIn: onlyWhenPluggedIn,
                       batteryPercent: batteryPercent, batteryThreshold: batteryThreshold)
}

@Test func aCriticalThermalStateBlocksEvenOnPower() {
    #expect(blocker(thermalCritical: true, onAC: true) == "Your Mac is too hot")
}

@Test func lowPowerModeBlocksOnlyWhenRespected() {
    #expect(blocker(lowPowerMode: true) == "Low Power Mode is on")
    #expect(blocker(lowPowerMode: true, respectLowPowerMode: false) == nil)
}

@Test func batteryRulesDontApplyOnPower() {
    #expect(blocker(onAC: true, onlyWhenPluggedIn: true, batteryPercent: 5) == nil)
}

@Test func onlyWhenPluggedInBlocksOnBattery() {
    #expect(blocker(onlyWhenPluggedIn: true) == "Your Mac isn't plugged in")
}

@Test func theBatteryCutoffBlocksOnlyBelowTheThreshold() {
    #expect(blocker(batteryPercent: 14) == "Battery is below 15%")
    #expect(blocker(batteryPercent: 15) == nil)
    #expect(blocker(batteryPercent: 5, batteryThreshold: 0) == nil)
    #expect(blocker(batteryPercent: nil) == nil)
}

// MARK: - Waiting for your reply

private func reason(working: Bool = false, hasSessions: Bool = true, lastWorkingAt: Date? = now, onAC: Bool,
                    pluggedIn: Int = HoldPolicy.untilSessionsClose, battery: Int = 60, at time: Date) -> HoldReason? {
    HoldPolicy.reason(working: working, hasSessions: hasSessions, lastWorkingAt: lastWorkingAt, onAC: onAC,
                      pluggedInWaitMinutes: pluggedIn, batteryWaitMinutes: battery, now: time)
}

@Test func aWorkingAgentIsTheReason() {
    #expect(reason(working: true, lastWorkingAt: nil, onAC: false, at: now) == .working)
}

@Test func pluggedInItWaitsUntilEverySessionCloses() {
    #expect(reason(onAC: true, at: now.addingTimeInterval(minutes(600))) == .waitingForYou(until: nil))
    #expect(reason(hasSessions: false, onAC: true, at: now) == nil)
}

@Test func onBatteryItWaitsAnHourFromWhenAnAgentLastWorked() {
    let until = now.addingTimeInterval(minutes(60))
    #expect(reason(onAC: false, at: now.addingTimeInterval(minutes(59))) == .waitingForYou(until: until))
    #expect(reason(onAC: false, at: now.addingTimeInterval(minutes(61))) == nil)
}

@Test func thereIsNoWaitWithoutEarlierWorkOrWhenWaitingIsOff() {
    #expect(reason(lastWorkingAt: nil, onAC: true, at: now) == nil)
    #expect(reason(onAC: false, battery: 0, at: now) == nil)
}

@Test func lastWorkingAtFollowsWorkAndIsForgottenWhenSessionsClose() {
    let earlier = now.addingTimeInterval(-minutes(10))
    #expect(HoldPolicy.lastWorkingAt(previous: earlier, working: true, hasSessions: true, now: now) == now)
    #expect(HoldPolicy.lastWorkingAt(previous: earlier, working: false, hasSessions: true, now: now) == earlier)
    #expect(HoldPolicy.lastWorkingAt(previous: earlier, working: false, hasSessions: false, now: now) == nil)
}
