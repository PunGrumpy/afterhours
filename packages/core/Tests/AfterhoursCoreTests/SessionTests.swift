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
