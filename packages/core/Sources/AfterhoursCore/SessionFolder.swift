import Foundation

public enum SessionFolder {
    private static let temporaryMarker = ".json.sb-"
    /// A live write takes under a millisecond, so only a hook stalled for a minute could lose one, and its next event writes it again.
    private static let staleAfter: TimeInterval = 60

    /// Whether a file in the sessions folder is the temporary half of an atomic session write.
    public static func isTemporary(_ url: URL) -> Bool {
        url.lastPathComponent.contains(temporaryMarker)
    }

    /// Removes leftovers of a killed atomic write once they are a minute old, off the caller's actor because deleting a backlog of hundreds can take seconds.
    @concurrent
    public static func removeStaleTemporaries(in directory: URL, now: Date) async -> Int {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: directory,
                                                 includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        var removed = 0
        for url in files where isTemporary(url) {
            guard let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  now.timeIntervalSince(modified) > staleAfter
            else { continue }
            if (try? fm.removeItem(at: url)) != nil { removed += 1 }
        }
        return removed
    }
}
