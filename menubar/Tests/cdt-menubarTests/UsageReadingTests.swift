import XCTest
@testable import cdt_menubar

/// Covers the menu bar's cache-only usage reader: parsing the shared status-line cache, the staleness
/// boundary that decides graying, the snapshot states the dropdown renders, and the GitHub update check.
/// All pure — no network, no Keychain (the menu bar no longer touches either after the OAuth fetch removal).
final class UsageReadingTests: XCTestCase {

    // MARK: - cache parse (the status line's merged file, tolerant of sibling fields)

    func testCacheParsesMergedFile() {
        // The real on-disk cache carries the status-line's sibling fields too — must still parse the %s.
        let json = #"{"weekly":2,"ctx_mtime":0,"ctx_tokens":148000,"agent_count":3,"session":13,"session_start":1781829635,"ts":1781829176}"#
        let c = parseUsageCache(Data(json.utf8))
        XCTAssertEqual(c?.session, 13)
        XCTAssertEqual(c?.weekly, 2)
        XCTAssertEqual(c?.ts, 1781829176)
    }

    func testCacheTsOptional() {
        let c = parseUsageCache(Data(#"{"session":5,"weekly":9}"#.utf8))
        XCTAssertEqual(c?.session, 5)
        XCTAssertEqual(c?.weekly, 9)
        XCTAssertNil(c?.ts)
    }

    func testCacheRejectsIncompleteOrGarbage() {
        XCTAssertNil(parseUsageCache(Data(#"{"session":5}"#.utf8)))       // no weekly
        XCTAssertNil(parseUsageCache(Data(#"{"weekly":5}"#.utf8)))        // no session
        XCTAssertNil(parseUsageCache(Data(#"{}"#.utf8)))
        XCTAssertNil(parseUsageCache(Data("not json".utf8)))
    }

    // MARK: - staleness boundary (decides whether the reading is grayed)

    private let now = Date(timeIntervalSince1970: 10_000)
    private func ts(secondsAgo: TimeInterval) -> Int { Int(now.timeIntervalSince1970 - secondsAgo) }

    func testFreshReadingNotStale() {
        XCTAssertFalse(usageReadingIsStale(ts: ts(secondsAgo: 0), now: now))     // just written
        XCTAssertFalse(usageReadingIsStale(ts: ts(secondsAgo: 1799), now: now))  // 1s inside the 30-min window
    }

    func testAgedReadingIsStale() {
        XCTAssertTrue(usageReadingIsStale(ts: ts(secondsAgo: 1800), now: now))   // exactly at edge → stale
        XCTAssertTrue(usageReadingIsStale(ts: ts(secondsAgo: 7200), now: now))   // 2h old
    }

    func testUndatedAndFutureReadingsAreStale() {
        XCTAssertTrue(usageReadingIsStale(ts: nil, now: now))                    // can't trust an undated reading
        XCTAssertTrue(usageReadingIsStale(ts: ts(secondsAgo: -120), now: now))   // clock skew → never trust
    }

    // MARK: - snapshot states the dropdown / badge branch on

    func testSnapshotWithFreshReading() {
        var snap = UsageSnapshot()
        snap.usage = UsageReading(sessionPct: 27, weeklyPct: 14)
        snap.usageStale = false
        XCTAssertNotNil(snap.usage)
        XCTAssertFalse(snap.usageStale)           // colored, presented as live
    }

    func testSnapshotWithStaleReading() {
        var snap = UsageSnapshot()
        snap.usage = UsageReading(sessionPct: 27, weeklyPct: 14)
        snap.usageStale = true
        snap.usageAsOf = Date(timeIntervalSince1970: 1_000)
        XCTAssertNotNil(snap.usage)               // we still show the last %s…
        XCTAssertTrue(snap.usageStale)            // …grayed, with an "as of"
    }

    func testEmptySnapshotHasNoReading() {
        let snap = UsageSnapshot()
        XCTAssertNil(snap.usage)                  // → dropdown shows the "enable status line" hint
        XCTAssertFalse(snap.usageStale)
    }

    // MARK: - app self-update check (GitHub releases)

    func testParseLatestRelease() {
        let json = #"{"tag_name":"v1.49.0","name":"v1.49.0","html_url":"https://github.com/jaysonventura/claude-dev-team/releases/tag/v1.49.0"}"#
        let r = parseLatestRelease(Data(json.utf8))
        XCTAssertEqual(r?.version, "1.49.0")            // "v" stripped
        XCTAssertEqual(r?.url, "https://github.com/jaysonventura/claude-dev-team/releases/tag/v1.49.0")
        XCTAssertEqual(parseLatestRelease(Data(#"{"tag_name":"2.0.0"}"#.utf8))?.version, "2.0.0")  // no "v"
        XCTAssertNil(parseLatestRelease(Data(#"{"name":"x"}"#.utf8)))                              // no tag
        XCTAssertNil(parseLatestRelease(Data(#"{"tag_name":""}"#.utf8)))                            // empty tag
        XCTAssertNil(parseLatestRelease(Data("not json".utf8)))
    }

    func testIsNewerVersion() {
        XCTAssertTrue(isNewerVersion("1.49.0", than: "1.48.0"))
        XCTAssertTrue(isNewerVersion("v1.49.0", than: "1.48.0"))   // v prefix tolerated
        XCTAssertTrue(isNewerVersion("1.10.0", than: "1.9.0"))     // numeric-aware (10 > 9)
        XCTAssertTrue(isNewerVersion("2.0.0", than: "1.99.99"))
        XCTAssertFalse(isNewerVersion("1.48.0", than: "1.48.0"))   // equal → not newer
        XCTAssertFalse(isNewerVersion("1.47.0", than: "1.48.0"))   // older
        XCTAssertFalse(isNewerVersion("1.48", than: "1.48.0"))     // 1.48 == 1.48.0
    }

    /// Live E2E: hit the real GitHub releases API and confirm the full chain (request → parse → compare).
    /// Skipped unless CDT_LIVE_UPDATE_CHECK is set (so CI without network stays green).
    func testLiveGitHubReleaseCheck() throws {
        guard ProcessInfo.processInfo.environment["CDT_LIVE_UPDATE_CHECK"] != nil else {
            throw XCTSkip("set CDT_LIVE_UPDATE_CHECK=1 to hit the real GitHub releases API")
        }
        let exp = expectation(description: "github releases")
        let checker = UpdateChecker(currentVersion: "0.0.0")   // 0.0.0 → any published release is "newer"
        checker.onResult = { exp.fulfill() }
        checker.checkNow(force: true)
        wait(for: [exp], timeout: 25)
        XCTAssertNotNil(checker.lastChecked)
        XCTAssertNotNil(checker.available, "expected a newer release vs 0.0.0")
        print("LIVE latest release:", checker.available?.version ?? "nil", checker.available?.url ?? "")
    }
}
