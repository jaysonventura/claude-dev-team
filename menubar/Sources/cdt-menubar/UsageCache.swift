import Foundation

/// The shared on-disk usage cache (`~/.claude/.cdt-usage.json`). The CLI status line (`hooks/statusline.sh`)
/// is the SOLE writer of the account-wide usage %s (`session`/`weekly`) — it reads them straight from Claude
/// Code's native `rate_limits` payload (no OAuth endpoint, no Keychain, no rate limit) and merge-writes them
/// at the top level. The menu bar, the `--once` CLI, and `cdt-budget` are READERS only. Centralized here so
/// every reader agrees on the same schema and the tolerant parse (`parseUsageCache`) ignores the sibling
/// fields other writers own (per-workspace `sessions{}`, context size, …).
let usageCacheURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".claude/.cdt-usage.json")

/// How long a cached reading is treated as current before the menu bar grays it (30 min). The status line
/// rewrites it on every interaction, so a reading older than this means Claude Code has been idle (or the
/// CDT status line isn't enabled). The %s move slowly, so a generous window avoids needless graying. A
/// SINGLE constant so the menu bar and the `--once` CLI can't drift on what "fresh" means.
let usageFreshWindow: TimeInterval = 1800

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

/// True when a reading should be shown grayed: it's older than `window`, undated, or clock-skewed into the
/// future — anything we can't trust as current. The inverse of `usageCacheFresh`. Pure → unit-tested.
func usageReadingIsStale(ts: Int?, now: Date = Date(), window: TimeInterval = usageFreshWindow) -> Bool {
    !usageCacheFresh(ts: ts, now: now, maxAge: window)
}
