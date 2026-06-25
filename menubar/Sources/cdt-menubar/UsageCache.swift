import Foundation

/// The shared on-disk usage cache (`~/.claude/.cdt-usage.json`) — the single file the menu bar, the status
/// line, the `--once` CLI, and `cdt-budget` all read/write. Centralized here so every reader/writer agrees on
/// the SAME schema and uses a merge-write that never clobbers a sibling field another writer owns (e.g. the
/// per-workspace `sessions{}` the status line keeps). The account-wide subscription %s (`session`/`weekly`)
/// are top-level + shared — they describe the account rate limit, not a single workspace.
let usageCacheURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".claude/.cdt-usage.json")

/// Healthy poll cadence for the subscription endpoint, in seconds (10 min). The menu bar polls at this
/// interval and the `--once` CLI treats a cached reading younger than this as fresh — a SINGLE constant so
/// the poll cadence and the cache-first window can't silently drift apart. The % moves slowly, so this
/// gentle cadence loses no real freshness while halving steady-state load.
let subscriptionPollInterval: TimeInterval = 600

/// Read + parse the cache. Returns nil when the file is missing or lacks both `session` and `weekly`
/// (the tolerant parse lives in `parseUsageCache`, which ignores extra sibling fields).
func readUsageCache() -> (session: Int, weekly: Int, ts: Int?)? {
    guard let data = try? Data(contentsOf: usageCacheURL) else { return nil }
    return parseUsageCache(data)
}

/// Pure freshness math — no filesystem, so it's unit-tested. Age (seconds) of a cache timestamp relative to
/// `now`; nil when there's no timestamp. A future `ts` (clock skew) yields a negative age, which callers
/// treat as "not fresh" rather than trusting it.
func usageCacheAgeSeconds(ts: Int?, now: Date) -> TimeInterval? {
    guard let ts = ts else { return nil }
    return now.timeIntervalSince1970 - TimeInterval(ts)
}

/// True when a cache timestamp is within `maxAge` of `now` and not in the future. Pure → unit-tested.
func usageCacheFresh(ts: Int?, now: Date = Date(), maxAge: TimeInterval) -> Bool {
    guard let age = usageCacheAgeSeconds(ts: ts, now: now) else { return false }
    return age >= 0 && age < maxAge
}

/// Age (seconds) of the on-disk cached reading, or nil if it's missing / has no timestamp.
func usageCacheAge(now: Date = Date()) -> TimeInterval? {
    usageCacheAgeSeconds(ts: readUsageCache()?.ts, now: now)
}

/// Merge-write the account-wide subscription %s, preserving every sibling field other writers own, and
/// stamp `ts` so freshness checks work. Best-effort (never throws — a usage cache is non-critical) and
/// READ-ONLY with respect to credentials: it only persists already-fetched %s, never touches the Keychain.
func writeUsageCache(session: Int, weekly: Int, now: Date = Date()) {
    var obj = (try? Data(contentsOf: usageCacheURL)).flatMap {
        try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
    } ?? [:]
    obj["session"] = session
    obj["weekly"] = weekly
    obj["ts"] = Int(now.timeIntervalSince1970)
    if let data = try? JSONSerialization.data(withJSONObject: obj) {
        // Atomic write (temp file + rename) so a concurrent reader/writer — the status line's Python writer
        // uses os.replace — never sees a half-written file or clobbers a sibling update mid-write.
        try? data.write(to: usageCacheURL, options: .atomic)
    }
}
