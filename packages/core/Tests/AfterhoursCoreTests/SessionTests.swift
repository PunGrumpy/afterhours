import Foundation
import Testing
@testable import AfterhoursCore

@Test func sessionFileNamesCannotEscapeTheSessionsDirectory() {
    let url = AfterhoursPaths.sessionFile(agent: "claude", id: "../../etc/passwd")
    #expect(url.lastPathComponent == "claude-______etc_passwd.json")
    #expect(url.deletingLastPathComponent().standardizedFileURL == AfterhoursPaths.sessions.standardizedFileURL)
}

@Test func sessionFileKeepsLettersDigitsDashesAndUnderscores() {
    let url = AfterhoursPaths.sessionFile(agent: "amp", id: "abc-123_XYZ")
    #expect(url.lastPathComponent == "amp-abc-123_XYZ.json")
}

@Test func sessionRecordsRoundTripThroughTheSharedCoders() throws {
    let record = SessionRecord(id: "s1", agent: "claude", state: .waiting, pid: 4242, cwd: "/tmp/x",
                               updatedAt: Date(timeIntervalSince1970: 1_790_000_000))
    let data = try JSONEncoder.afterhours.encode(record)
    let decoded = try JSONDecoder.afterhours.decode(SessionRecord.self, from: data)
    #expect(decoded.id == "s1")
    #expect(decoded.state == .waiting)
    #expect(decoded.pid == 4242)
    #expect(decoded.updatedAt == record.updatedAt)
    #expect(String(decoding: data, as: UTF8.self).contains("2026-09-"))
}

@Test func agentStatesUseTheirNamesOnTheWire() {
    #expect(AgentState(rawValue: "working") == .working)
    #expect(AgentState(rawValue: "end") == nil)
}

@Test func claudeEventsMapToStatesAndUnknownEventsToNothing() {
    #expect(HookAction(claudeEvent: "PreToolUse") == .set(.working))
    #expect(HookAction(claudeEvent: "Notification") == .set(.waiting))
    #expect(HookAction(claudeEvent: "Stop") == .set(.idle))
    #expect(HookAction(claudeEvent: "SessionEnd") == .end)
    #expect(HookAction(claudeEvent: "SubagentStop") == nil)
}

@Test func explicitStatesAcceptOnlyTheDocumentedValues() {
    #expect(HookAction(explicitState: "working") == .set(.working))
    #expect(HookAction(explicitState: "end") == .end)
    #expect(HookAction(explicitState: "done") == nil)
    #expect(HookAction(explicitState: "Working") == nil)
}

@Test func sectionStatusCountsSessionsNotAgents() {
    #expect(SessionTally([]).sectionStatus == "No sessions")
    #expect(SessionTally([.idle]).sectionStatus == "1 session open")
    #expect(SessionTally([.idle, .waiting, .idle]).sectionStatus == "3 sessions open")
    #expect(SessionTally([.working]).sectionStatus == "1 of 1 session working")
    #expect(SessionTally([.working, .idle, .idle, .waiting]).sectionStatus == "1 of 4 sessions working")
    #expect(SessionTally([.working, .working]).sectionStatus == "2 of 2 sessions working")
}

@Test func rowStatusListsOnlyTheStatesThatHaveSessions() {
    #expect(SessionTally([]).rowStatus == [])
    #expect(SessionTally([.idle, .idle]).rowStatus == ["2 idle"])
    #expect(SessionTally([.idle, .working, .waiting, .working]).rowStatus == ["2 working", "1 needs you", "1 idle"])
    #expect(SessionTally([.waiting]).rowStatus == ["1 needs you"])
}

@Test func aRowOfIdleSessionsNeverCountsThemAsWorking() {
    let tally = SessionTally([.idle, .idle, .idle])
    #expect(tally.working == 0)
    #expect(tally.total == 3)
    #expect(tally.rowStatus == ["3 idle"])
}
