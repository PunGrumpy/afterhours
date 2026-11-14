import Foundation
import Testing

@testable import AfterhoursCore

private let leftoverName = "claude-0f3c9a52-7b1e-4c1d-9a55-2f1c4e7d8a90.json.sb-35d5aadf-Xy3Kq9"

private func makeFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("afterhours-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@discardableResult
private func write(_ name: String, in folder: URL, modified: Date) throws -> URL {
    let url = folder.appendingPathComponent(name)
    try Data("{}".utf8).write(to: url)
    try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    return url
}

private func exists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
}

@Test func staleLeftoverIsRemovedAndCounted() async throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let now = Date()
    let leftover = try write(leftoverName, in: folder, modified: now.addingTimeInterval(-61))

    let removed = await SessionFolder.removeStaleTemporaries(in: folder, now: now)

    #expect(removed == 1)
    #expect(!exists(leftover))
}

@Test func freshLeftoverStays() async throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let now = Date()
    let leftover = try write(leftoverName, in: folder, modified: now.addingTimeInterval(-10))

    let removed = await SessionFolder.removeStaleTemporaries(in: folder, now: now)

    #expect(removed == 0)
    #expect(exists(leftover))
}

@Test func liveSessionFileStaysWhateverItsAge() async throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let now = Date()
    let live = try write(
        "claude-0f3c9a52-7b1e-4c1d-9a55-2f1c4e7d8a90.json", in: folder,
        modified: now.addingTimeInterval(-3600))

    let removed = await SessionFolder.removeStaleTemporaries(in: folder, now: now)

    #expect(removed == 0)
    #expect(exists(live))
}

@Test func unrelatedOldFilesStay() async throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let now = Date()
    let old = now.addingTimeInterval(-3600)
    let notes = try write("notes.txt", in: folder, modified: old)
    let lookalike = try write("x.sb-1", in: folder, modified: old)

    let removed = await SessionFolder.removeStaleTemporaries(in: folder, now: now)

    #expect(removed == 0)
    #expect(exists(notes))
    #expect(exists(lookalike))
}

@Test func missingFolderRemovesNothing() async {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("afterhours-tests-\(UUID().uuidString)", isDirectory: true)

    #expect(await SessionFolder.removeStaleTemporaries(in: folder, now: Date()) == 0)
}

@Test func returnCountMatchesEveryStaleLeftoverRemoved() async throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let now = Date()
    let stale = try (0..<3).map {
        try write("codex-\($0).json.sb-35d5aadf-Ab\($0)Cd", in: folder, modified: now.addingTimeInterval(-600))
    }
    let fresh = try write(leftoverName, in: folder, modified: now.addingTimeInterval(-5))

    let removed = await SessionFolder.removeStaleTemporaries(in: folder, now: now)

    #expect(removed == 3)
    #expect(stale.allSatisfy { !exists($0) })
    #expect(exists(fresh))
}

@Test func onlyTheTemporaryHalfOfASessionWriteCountsAsTemporary() {
    let folder = URL(fileURLWithPath: "/tmp/sessions", isDirectory: true)
    #expect(SessionFolder.isTemporary(folder.appendingPathComponent(leftoverName)))
    #expect(!SessionFolder.isTemporary(folder.appendingPathComponent("claude-0f3c9a52-7b1e-4c1d-9a55-2f1c4e7d8a90.json")))
    #expect(!SessionFolder.isTemporary(folder.appendingPathComponent("x.sb-1")))
}
