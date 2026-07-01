import Foundation

// Opt-in, throttled realtime usage — the ONLY place the menu bar reaches the network. Default users never
// hit this: the gate short-circuits when `realtimeOn` is false, so no Keychain read and no request happen.

/// Hard floor between fetch attempts (10 min). This is the user's cadence — the endpoint moves slowly and a
/// shared OAuth token bursting it was the sole cause of the old 429 storms, so we never poll faster.
let minFetchInterval: TimeInterval = 600

/// Don't fetch when the terminal just wrote a fresh reading (5 min). While Claude Code is active in a
/// terminal the status line keeps the cache fresh, so realtime stays completely idle — it only steps in
/// once that on-disk reading ages past this window.
let staleTrigger: TimeInterval = 300

/// PURE gating decision (no clock, no filesystem, no network) so it is exhaustively unit-tested. Returns
/// true ONLY when every guard holds:
///   • realtime is on;
///   • we're not inside a 429 cooldown (`cooldownUntil == nil || now >= cooldownUntil`);
///   • at least `minFetchInterval` has elapsed since the last attempt (nil ⇒ never attempted ⇒ allowed);
///   • the status-line cache reading is stale/absent — its age is ≥ `staleTrigger`, or there's no `cacheTs`
///     (a future `ts` is clock-skew and treated as not-fresh, consistent with `usageCacheFresh`).
/// This yields ≤ 6 fetches/hour worst case, and ZERO while the terminal is active or realtime is off.
func shouldFetchRealtimeUsage(realtimeOn: Bool,
                              cacheTs: Int?,
                              lastAttempt: Date?,
                              cooldownUntil: Date?,
                              now: Date) -> Bool {
    guard realtimeOn else { return false }
    if let cd = cooldownUntil, now < cd { return false }                       // honor the 429 back-off
    if let last = lastAttempt, now.timeIntervalSince(last) < minFetchInterval { return false }
    if let ts = cacheTs {                                                      // fresh terminal reading?
        let age = now.timeIntervalSince1970 - TimeInterval(ts)
        if age >= 0 && age < staleTrigger { return false }                    // fresh → leave it be
    }
    return true
}

/// Merges the fetched `{session, weekly, ts}` into an existing cache JSON body, PRESERVING every sibling
/// field (the per-workspace `sessions{}` object, `ctx_tokens`, `agent_count`, …). Mirrors `usage_cache.py`'s
/// load-dict → update-3-keys → dump discipline so the menu bar and the status line never clobber each other.
/// PURE (Data in, Data out) so the round-trip is unit-tested. Returns nil only if the merged dict can't be
/// re-serialized (never expected).
func mergeUsageJSON(existing: Data?, session: Int, weekly: Int, ts: Int) -> Data? {
    var dict: [String: Any] = [:]
    if let d = existing, let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
        dict = obj                                          // keep all sibling fields the status line owns
    }
    dict["session"] = session
    dict["weekly"] = weekly
    dict["ts"] = ts
    return try? JSONSerialization.data(withJSONObject: dict)
}

/// Atomic write of a merged cache body: per-pid `.tmp` → `rename(2)` over the target (mirrors Python's
/// `os.replace`). Best-effort and fail-open; the tmp is removed if the rename fails so it can never leak.
/// Shared by every cache writer so they are all atomic and none leaves a partial file.
private func atomicWriteCache(_ merged: Data, to url: URL) {
    let tmp = URL(fileURLWithPath: url.path + ".mb.\(getpid()).tmp")
    do {
        try merged.write(to: tmp)
        if rename(tmp.path, url.path) != 0 { try? FileManager.default.removeItem(at: tmp) }
    } catch {
        try? FileManager.default.removeItem(at: tmp)
    }
}

/// Atomic read-modify-write of the shared cache: load → merge the 3 account-wide keys → atomic write.
/// Best-effort and fail-open — the token is NEVER written here, only the two integer %s and a timestamp.
func writeUsageCacheMerging(session: Int, weekly: Int, ts: Int, url: URL = usageCacheURL) {
    let existing = try? Data(contentsOf: url)
    guard let merged = mergeUsageJSON(existing: existing, session: session, weekly: weekly, ts: ts) else { return }
    atomicWriteCache(merged, to: url)
}

// MARK: - Persisted 429 back-off (survives restart; honored by the separate --refresh-usage CLI)

/// Cache key holding the epoch-seconds until which realtime fetching is backed off after a 429. Persisted so
/// the server's `Retry-After` survives an app relaunch AND is honored by the `--refresh-usage` CLI (a separate
/// process that shares no in-memory state) — closing the only path that could manually burst the endpoint.
let cooldownCacheKey = "rt_cooldown_until"

/// Clamps a 429 `Retry-After` (or a missing one) to a sane back-off window [60s, 30m]. Single source of truth
/// so the store and the CLI back off identically. PURE → unit-tested.
func clampedCooldownSeconds(_ retryAfter: TimeInterval?) -> TimeInterval {
    min(max(retryAfter ?? 900, 60), 1800)
}

/// Merges (or clears, when `until` is nil) the persisted cooldown into an existing cache body, PRESERVING
/// every sibling field. PURE (Data in, Data out) so the round-trip is unit-tested.
func mergeCooldownJSON(existing: Data?, until: Date?) -> Data? {
    var dict: [String: Any] = [:]
    if let d = existing, let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { dict = obj }
    if let until = until { dict[cooldownCacheKey] = until.timeIntervalSince1970 }
    else { dict.removeValue(forKey: cooldownCacheKey) }
    return try? JSONSerialization.data(withJSONObject: dict)
}

/// Reads the persisted cooldown deadline, or nil if absent/unreadable. Accepts int or double JSON numbers.
func readPersistedCooldown(url: URL = usageCacheURL) -> Date? {
    guard let d = try? Data(contentsOf: url),
          let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
          let epoch = (obj[cooldownCacheKey] as? NSNumber)?.doubleValue else { return nil }
    return Date(timeIntervalSince1970: epoch)
}

/// Atomic persist (or clear when nil) of the cooldown deadline, preserving siblings. Best-effort/fail-open.
func writeCooldownMerging(until: Date?, url: URL = usageCacheURL) {
    let existing = try? Data(contentsOf: url)
    guard let merged = mergeCooldownJSON(existing: existing, until: until) else { return }
    atomicWriteCache(merged, to: url)
}
