import XCTest
@testable import cdt_menubar

/// Covers the opt-in realtime usage layer's PURE decision + IO helpers:
///   • `shouldFetchRealtimeUsage` — the full throttle truth table (this is what guarantees ≤6 fetches/hour
///     and ZERO fetches when realtime is off or the terminal reading is fresh);
///   • `mergeUsageJSON` — the atomic cache merge preserves every sibling field the status line owns;
///   • `parseRealtimeFlag` — the config flag interpretation (default OFF).
/// No clock, no filesystem, no network — `now`/`ts` are injected.
final class RealtimeUsageTests: XCTestCase {

    // MARK: - throttle gate (the whole point: never poll when off / recently attempted / cache fresh)

    private let now = Date(timeIntervalSince1970: 1_000_000)
    private func ago(_ s: TimeInterval) -> Date { now.addingTimeInterval(-s) }
    private func tsAgo(_ s: TimeInterval) -> Int { Int(now.timeIntervalSince1970 - s) }

    func testGateOffAlwaysFalse() {
        // Realtime OFF short-circuits before any Keychain/network — the default-user guarantee.
        XCTAssertFalse(shouldFetchRealtimeUsage(
            realtimeOn: false, cacheTs: nil, lastAttempt: nil, cooldownUntil: nil, now: now))
        XCTAssertFalse(shouldFetchRealtimeUsage(
            realtimeOn: false, cacheTs: tsAgo(9999), lastAttempt: ago(9999), cooldownUntil: nil, now: now))
    }

    func testGateInCooldownFalse() {
        XCTAssertFalse(shouldFetchRealtimeUsage(
            realtimeOn: true, cacheTs: nil, lastAttempt: nil,
            cooldownUntil: now.addingTimeInterval(120), now: now))
    }

    func testGateWithinMinIntervalFalse() {
        // < 10 min since the last attempt → held off even though the cache is stale.
        XCTAssertFalse(shouldFetchRealtimeUsage(
            realtimeOn: true, cacheTs: tsAgo(9999), lastAttempt: ago(300), cooldownUntil: nil, now: now))
        // 1s short of the floor → still false.
        XCTAssertFalse(shouldFetchRealtimeUsage(
            realtimeOn: true, cacheTs: tsAgo(9999), lastAttempt: ago(599), cooldownUntil: nil, now: now))
    }

    func testGateFreshCacheFalse() {
        // The terminal just wrote a reading (<5 min old) → realtime stays idle.
        XCTAssertFalse(shouldFetchRealtimeUsage(
            realtimeOn: true, cacheTs: tsAgo(60), lastAttempt: nil, cooldownUntil: nil, now: now))
        XCTAssertFalse(shouldFetchRealtimeUsage(
            realtimeOn: true, cacheTs: tsAgo(299), lastAttempt: nil, cooldownUntil: nil, now: now))
    }

    func testGateStaleCacheOnIntervalElapsedTrue() {
        // The canonical fetch case: realtime on, cache stale, floor elapsed, no cooldown.
        XCTAssertTrue(shouldFetchRealtimeUsage(
            realtimeOn: true, cacheTs: tsAgo(600), lastAttempt: ago(700), cooldownUntil: nil, now: now))
    }

    func testGateNilCacheTsTrue() {
        // No reading has ever been written → fetch to seed it (nil lastAttempt ⇒ allowed).
        XCTAssertTrue(shouldFetchRealtimeUsage(
            realtimeOn: true, cacheTs: nil, lastAttempt: nil, cooldownUntil: nil, now: now))
    }

    func testGateBoundaries() {
        // Exactly at staleTrigger (300s) → stale → eligible.
        XCTAssertTrue(shouldFetchRealtimeUsage(
            realtimeOn: true, cacheTs: tsAgo(300), lastAttempt: nil, cooldownUntil: nil, now: now))
        // Exactly at minFetchInterval (600s) since last attempt → floor satisfied.
        XCTAssertTrue(shouldFetchRealtimeUsage(
            realtimeOn: true, cacheTs: tsAgo(400), lastAttempt: ago(600), cooldownUntil: nil, now: now))
        // Cooldown just expired (now >= cooldownUntil) → no longer blocked.
        XCTAssertTrue(shouldFetchRealtimeUsage(
            realtimeOn: true, cacheTs: tsAgo(400), lastAttempt: ago(700), cooldownUntil: ago(1), now: now))
        // A future (clock-skewed) cache ts is treated as not-fresh → eligible.
        XCTAssertTrue(shouldFetchRealtimeUsage(
            realtimeOn: true, cacheTs: tsAgo(-120), lastAttempt: nil, cooldownUntil: nil, now: now))
    }

    // MARK: - atomic cache merge preserves every sibling field

    func testMergePreservesSiblings() throws {
        // A realistic cache: per-workspace sessions{} plus top-level context/agent fields the menu bar must
        // never clobber. Merging the 3 account-wide keys must touch ONLY those keys.
        let original = #"""
        {"session":13,"weekly":2,"ts":100,
         "sessions":{"proj":{"ctx_tokens":148000,"agent_count":3,"ts":50,"session_start":40}},
         "ctx_tokens":9,"agent_count":1}
        """#
        let merged = try XCTUnwrap(mergeUsageJSON(existing: Data(original.utf8), session: 55, weekly: 66, ts: 999))
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: merged) as? [String: Any])

        // Updated keys.
        XCTAssertEqual(obj["session"] as? Int, 55)
        XCTAssertEqual(obj["weekly"] as? Int, 66)
        XCTAssertEqual(obj["ts"] as? Int, 999)

        // Every sibling preserved, values intact.
        let sessions = try XCTUnwrap(obj["sessions"] as? [String: Any])
        let proj = try XCTUnwrap(sessions["proj"] as? [String: Any])
        XCTAssertEqual(proj["ctx_tokens"] as? Int, 148000)
        XCTAssertEqual(proj["agent_count"] as? Int, 3)
        XCTAssertEqual(proj["ts"] as? Int, 50)
        XCTAssertEqual(proj["session_start"] as? Int, 40)
        XCTAssertEqual(obj["ctx_tokens"] as? Int, 9)
        XCTAssertEqual(obj["agent_count"] as? Int, 1)

        // Round-trips as a valid readable cache.
        let reread = try XCTUnwrap(parseUsageCache(merged))
        XCTAssertEqual(reread.session, 55)
        XCTAssertEqual(reread.weekly, 66)
        XCTAssertEqual(reread.ts, 999)
    }

    func testMergeFromEmptyCreatesOnlyThreeKeys() throws {
        // No existing cache → a fresh dict with exactly the 3 account-wide keys.
        let merged = try XCTUnwrap(mergeUsageJSON(existing: nil, session: 1, weekly: 2, ts: 3))
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: merged) as? [String: Any])
        XCTAssertEqual(obj["session"] as? Int, 1)
        XCTAssertEqual(obj["weekly"] as? Int, 2)
        XCTAssertEqual(obj["ts"] as? Int, 3)
        XCTAssertEqual(obj.count, 3)
    }

    func testMergeFromGarbageStillWritesKeys() throws {
        // Corrupt/non-object existing body must not lose the write — treat as empty and set the 3 keys.
        let merged = try XCTUnwrap(mergeUsageJSON(existing: Data("not json".utf8), session: 7, weekly: 8, ts: 9))
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: merged) as? [String: Any])
        XCTAssertEqual(obj["session"] as? Int, 7)
        XCTAssertEqual(obj.count, 3)
    }

    // MARK: - config flag parse (default OFF)

    func testRealtimeFlagOnTokens() {
        XCTAssertTrue(parseRealtimeFlag("1"))
        XCTAssertTrue(parseRealtimeFlag("on"))
        XCTAssertTrue(parseRealtimeFlag("true"))
        XCTAssertTrue(parseRealtimeFlag("  1 "))     // trimmed
        XCTAssertTrue(parseRealtimeFlag("ON"))       // case-insensitive
    }

    func testRealtimeFlagOffTokens() {
        XCTAssertFalse(parseRealtimeFlag("0"))
        XCTAssertFalse(parseRealtimeFlag("false"))
        XCTAssertFalse(parseRealtimeFlag("off"))
        XCTAssertFalse(parseRealtimeFlag(""))
        XCTAssertFalse(parseRealtimeFlag("   "))
    }

    func testRealtimeDefaultIsOff() {
        // A fresh config (env line absent) must default OFF — the pure-reader guarantee.
        XCTAssertFalse(CDTConfig().realtimeUsage)
    }

    // MARK: - persisted 429 back-off (survives restart; honored by the --refresh-usage CLI)

    func testClampCooldownSeconds() {
        XCTAssertEqual(clampedCooldownSeconds(nil), 900)       // no header → sane default
        XCTAssertEqual(clampedCooldownSeconds(10), 60)         // floor 60s
        XCTAssertEqual(clampedCooldownSeconds(120), 120)       // passed through
        XCTAssertEqual(clampedCooldownSeconds(99999), 1800)    // ceiling 30m
    }

    func testCooldownMergeSetsAndClearsPreservingSiblings() throws {
        let original = #"{"session":13,"weekly":2,"ts":100,"sessions":{"p":{"agent_count":3}},"ctx_tokens":9}"#
        // Persist a cooldown → the key is added, every sibling untouched.
        let until = Date(timeIntervalSince1970: 2_000_000)
        let set = try XCTUnwrap(mergeCooldownJSON(existing: Data(original.utf8), until: until))
        let a = try XCTUnwrap(try JSONSerialization.jsonObject(with: set) as? [String: Any])
        XCTAssertEqual((a[cooldownCacheKey] as? NSNumber)?.doubleValue, 2_000_000)
        XCTAssertEqual(a["session"] as? Int, 13)
        XCTAssertEqual(a["ctx_tokens"] as? Int, 9)
        let sessions = try XCTUnwrap(a["sessions"] as? [String: Any])
        let p = try XCTUnwrap(sessions["p"] as? [String: Any])
        XCTAssertEqual(p["agent_count"] as? Int, 3)   // nested sibling untouched
        // The account-usage reader ignores the extra key.
        XCTAssertEqual(try XCTUnwrap(parseUsageCache(set)).session, 13)

        // Clear (nil) → the key is removed, siblings still intact.
        let cleared = try XCTUnwrap(mergeCooldownJSON(existing: set, until: nil))
        let b = try XCTUnwrap(try JSONSerialization.jsonObject(with: cleared) as? [String: Any])
        XCTAssertNil(b[cooldownCacheKey])
        XCTAssertEqual(b["session"] as? Int, 13)
        XCTAssertEqual(b["ctx_tokens"] as? Int, 9)
    }

    func testPersistedCooldownRoundTrip() throws {
        // Filesystem round-trip: write → read back the same deadline; clear → nil.
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cdt-cooldown-\(getpid()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        // Seed with a sibling to prove the write preserves it.
        try Data(#"{"session":5,"weekly":1,"ts":1}"#.utf8).write(to: url)

        let until = Date(timeIntervalSince1970: 1_800_000)
        writeCooldownMerging(until: until, url: url)
        let read = try XCTUnwrap(readPersistedCooldown(url: url))
        XCTAssertEqual(read.timeIntervalSince1970, 1_800_000, accuracy: 0.5)
        // Sibling survived.
        XCTAssertEqual(try XCTUnwrap(parseUsageCache(try Data(contentsOf: url))).session, 5)

        writeCooldownMerging(until: nil, url: url)
        XCTAssertNil(readPersistedCooldown(url: url))
    }

    func testReadPersistedCooldownAbsentIsNil() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cdt-cooldown-absent-\(getpid()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"session":5,"weekly":1,"ts":1}"#.utf8).write(to: url)
        XCTAssertNil(readPersistedCooldown(url: url))   // no cooldown key → nil (not a crash)
    }
}
