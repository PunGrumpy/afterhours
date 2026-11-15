import Foundation
import Testing
@testable import AfterhoursCore

private let now = Date(timeIntervalSince1970: 1_790_000_000)

private func minutes(_ count: Double) -> TimeInterval { count * 60 }

// MARK: - Battery left

@Test func withoutACutoffTheWholeBatteryCounts() {
    #expect(HoldPolicy.minutesUntilCutoff(batteryPercent: 80, batteryThreshold: 0, minutesToEmpty: 240) == 240)
}

@Test func aCutoffTakesItsShareOffTheEstimate() {
    #expect(HoldPolicy.minutesUntilCutoff(batteryPercent: 80, batteryThreshold: 20, minutesToEmpty: 240) == 180)
}

@Test func atOrBelowTheCutoffNothingIsLeft() {
    #expect(HoldPolicy.minutesUntilCutoff(batteryPercent: 15, batteryThreshold: 20, minutesToEmpty: 60) == 0)
}

@Test func anUnknownEstimateGivesNoAnswer() {
    #expect(HoldPolicy.minutesUntilCutoff(batteryPercent: 80, batteryThreshold: 20, minutesToEmpty: -1) == nil)
}

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

// MARK: - What gets announced

private let until = now.addingTimeInterval(minutes(30))

/// The notice for a change, with nothing that points at a wait running out unless a test says so.
private func notice(from: HoldState, to: HoldState, lastReason: HoldReason = .working,
                    sessionsOpen: Bool = false) -> HoldNotice? {
    HoldPolicy.notice(from: from, to: to, lastReason: lastReason, sessionsOpen: sessionsOpen)
}

@Test func startingAHoldSpeaks() {
    #expect(notice(from: .idle, to: .holding) == .started)
    #expect(notice(from: .blocked("Your Mac is too hot"), to: .holding) == .started)
}

@Test func aHoldThatEndsWhenEverySessionClosesSaysTheAgentsFinished() {
    #expect(notice(from: .holding, to: .idle) == .finished(waitRanOut: false))
    #expect(notice(from: .holding, to: .idle, lastReason: .waitingForYou(until: nil)) == .finished(waitRanOut: false))
}

@Test func aHoldThatEndsInTheReplyWaitWithSessionsOpenSaysTheWaitRanOut() {
    let timed = notice(from: .holding, to: .idle, lastReason: .waitingForYou(until: until), sessionsOpen: true)
    #expect(timed == .finished(waitRanOut: true))
    let unplugged = notice(from: .holding, to: .idle, lastReason: .waitingForYou(until: nil), sessionsOpen: true)
    #expect(unplugged == .finished(waitRanOut: true))
}

@Test func withWaitingOffAHoldThatEndsWithSessionsOpenStillSaysTheAgentsFinished() {
    // The tick after the work ends has no reason at all, so the hold's last reason is still working.
    #expect(reason(lastWorkingAt: now.addingTimeInterval(-4), onAC: false, battery: 0, at: now) == nil)
    #expect(notice(from: .holding, to: .idle, lastReason: .working, sessionsOpen: true) == .finished(waitRanOut: false))
}

@Test func aSafetyRuleEndingAHoldSaysWhich() {
    #expect(notice(from: .holding, to: .blocked("Battery is below 15%")) == .blocked("Battery is below 15%"))
}

@Test func yourOwnChangesStaySilent() {
    let states: [HoldState] = [.idle, .holding, .blocked("Low Power Mode is on")]
    for state in states {
        #expect(notice(from: .disabled, to: state) == nil)
        #expect(notice(from: state, to: .disabled) == nil)
        #expect(notice(from: .paused(until: until), to: state) == nil)
        #expect(notice(from: state, to: .paused(until: until)) == nil)
    }
    #expect(notice(from: .disabled, to: .paused(until: until)) == nil)
}

@Test func changesThatDoNotStartOrEndAHoldStaySilent() {
    #expect(notice(from: .holding, to: .holding) == nil)
    #expect(notice(from: .idle, to: .blocked("Your Mac isn't plugged in")) == nil)
    #expect(notice(from: .blocked("Your Mac isn't plugged in"), to: .idle) == nil)
    #expect(notice(from: .idle, to: .idle) == nil)
}
