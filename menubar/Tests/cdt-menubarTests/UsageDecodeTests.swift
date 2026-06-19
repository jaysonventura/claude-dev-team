import XCTest
import Security
@testable import cdt_menubar

/// Regression coverage for the resilient `/api/oauth/usage` decoder.
///
/// The bug these guard against: the live response carries `"seven_day_sonnet":{...,"resets_at":null}`,
/// and the old non-optional model threw `DecodingError` ("The data couldn't be read because it is
/// missing.") on that one null — aborting the WHOLE decode and discarding the valid session/weekly
/// numbers, so the menu bar was stuck on "unavailable" and never refreshed. The parser must now tolerate
/// nulls/missing/new fields, and must surface a CLEAN error (never the raw Cocoa string) when a body
/// genuinely isn't usable — rather than fabricating a misleading "0%".
final class UsageDecodeTests: XCTestCase {
    private func account() -> ClaudeAccount {
        ClaudeAccount(accessToken: "test-token", subscriptionType: "max", rateLimitTier: "default_claude_max_5x")
    }

    private func parse(_ json: String) throws -> SubscriptionUsage {
        try parseUsageResponse(Data(json.utf8), account: account())
    }

    /// The EXACT live payload captured from the endpoint (note `seven_day_sonnet.resets_at` is null).
    private let realPayload = #"""
    {"five_hour":{"utilization":1.0,"resets_at":"2026-06-19T03:59:59.941789+00:00"},
     "seven_day":{"utilization":0.0,"resets_at":"2026-06-25T17:59:59.941812+00:00"},
     "seven_day_oauth_apps":null,"seven_day_opus":null,
     "seven_day_sonnet":{"utilization":0.0,"resets_at":null},
     "extra_usage":{"is_enabled":false,"monthly_limit":null},
     "limits":[{"kind":"session","percent":1,"severity":"normal"}]}
    """#

    func testRealPayloadWithNullResetsDecodes() throws {
        let u = try parse(realPayload)
        XCTAssertEqual(u.sessionPct, 1)             // five_hour 1.0 → 1% (previously lost entirely)
        XCTAssertEqual(u.weeklyPct, 0)
        XCTAssertEqual(u.sonnetPct, 0)              // present with value 0.0
        XCTAssertEqual(u.planLabel, "Max 5x")       // plan comes from the Keychain fields, not the endpoint
    }

    func testNullSonnetResetYieldsNilCountdownNotThrow() throws {
        // The null resets_at must degrade to a nil countdown, never an error.
        let u = try parse(realPayload)
        XCTAssertEqual(u.sonnetPct, 0)
        // five_hour has a real reset → a countdown string is produced; sonnet's null reset is simply absent.
        XCTAssertNotNil(u.sessionResetIn)
    }

    func testNullUtilizationOnSessionStillUsesWeekly() throws {
        let u = try parse(#"{"five_hour":{"utilization":null,"resets_at":null},"seven_day":{"utilization":42.0,"resets_at":null}}"#)
        XCTAssertEqual(u.sessionPct, 0)    // null utilization → 0, not a crash
        XCTAssertEqual(u.weeklyPct, 42)
    }

    func testMissingFiveHourStillUsable() throws {
        let u = try parse(#"{"seven_day":{"utilization":73.0,"resets_at":null}}"#)
        XCTAssertEqual(u.sessionPct, 0)
        XCTAssertEqual(u.weeklyPct, 73)
    }

    func testRoundingHalfUp() throws {
        let u = try parse(#"{"five_hour":{"utilization":12.5,"resets_at":null},"seven_day":{"utilization":88.4,"resets_at":null}}"#)
        XCTAssertEqual(u.sessionPct, 13)
        XCTAssertEqual(u.weeklyPct, 88)
    }

    // MARK: - clean failures (never a raw Cocoa "couldn't be read" string, never a fake 0%)

    func testEmptyBodyThrowsCleanError() {
        XCTAssertThrowsError(try parse("")) { error in
            XCTAssertEqual(error as? UsageError, .emptyResponse)
            XCTAssertFalse((error.localizedDescription).contains("couldn’t be read"))
        }
    }

    func testErrorEnvelopeThrowsUnexpectedFormatNotFakeZero() {
        // An auth/error envelope has no utilization → must be a clean error, NOT a misleading "0%".
        XCTAssertThrowsError(try parse(#"{"error":{"type":"authentication_error","message":"x"}}"#)) { error in
            XCTAssertEqual(error as? UsageError, .unexpectedFormat)
        }
    }

    func testAllNullPeriodsThrowUnexpectedFormat() {
        XCTAssertThrowsError(try parse(#"{"five_hour":null,"seven_day":null,"seven_day_sonnet":null}"#)) { error in
            XCTAssertEqual(error as? UsageError, .unexpectedFormat)
        }
    }

    func testGarbageBodyThrowsCleanError() {
        XCTAssertThrowsError(try parse("not json at all")) { error in
            XCTAssertEqual(error as? UsageError, .unexpectedFormat)
            XCTAssertFalse(error.localizedDescription.contains("couldn’t be read"))
        }
    }

    /// Live smoke: parse a freshly-captured real endpoint body through the REAL parser. Skipped unless
    /// CDT_LIVE_USAGE_JSON points to a captured body (so CI without creds stays green). Proves the current
    /// live shape — whatever fields it adds or nulls — still yields a usable reading.
    func testLivePayloadParsesWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["CDT_LIVE_USAGE_JSON"],
              let data = FileManager.default.contents(atPath: path) else {
            throw XCTSkip("set CDT_LIVE_USAGE_JSON to a captured live body to run this smoke test")
        }
        let u = try parseUsageResponse(data, account: account())
        XCTAssert((0...100).contains(u.sessionPct), "session out of range: \(u.sessionPct)")
        XCTAssert((0...100).contains(u.weeklyPct), "weekly out of range: \(u.weeklyPct)")
        print("LIVE OK → session=\(u.sessionPct)% weekly=\(u.weeklyPct)% sonnet=\(u.sonnetPct.map(String.init) ?? "-")")
    }

    func testHttpErrorMessagesAreActionable() {
        XCTAssertEqual(UsageError.http(401).errorDescription, "token expired — open Claude Code or re-login to refresh")
        XCTAssertEqual(UsageError.http(403).httpStatus, 403)
        XCTAssertNil(UsageError.emptyResponse.httpStatus)
    }

    // MARK: - rate-limit (429) handling

    func testRateLimitedReportsStatusAndRetryAfter() {
        XCTAssertEqual(UsageError.rateLimited(retryAfter: 120).httpStatus, 429)        // scheduler branches on 429
        XCTAssertEqual(UsageError.rateLimited(retryAfter: 120).retryAfter, 120)
        XCTAssertNil(UsageError.rateLimited(retryAfter: nil).retryAfter)
        XCTAssertEqual(UsageError.rateLimited(retryAfter: nil).errorDescription, "rate limited — will retry when allowed")
    }

    // MARK: - cold-start cache seed (never blank "unavailable" if we have prior data)

    func testCacheSeedParsesMergedFile() {
        // The real on-disk cache carries the status-line's sibling fields too — must still parse.
        let json = #"{"weekly":2,"ctx_mtime":0,"ctx_tokens":148000,"agent_count":3,"session":13,"session_start":1781829635,"ts":1781829176}"#
        let c = parseUsageCache(Data(json.utf8))
        XCTAssertEqual(c?.session, 13)
        XCTAssertEqual(c?.weekly, 2)
        XCTAssertEqual(c?.ts, 1781829176)
    }

    func testCacheSeedTsOptional() {
        let c = parseUsageCache(Data(#"{"session":5,"weekly":9}"#.utf8))
        XCTAssertEqual(c?.session, 5)
        XCTAssertEqual(c?.weekly, 9)
        XCTAssertNil(c?.ts)
    }

    func testCacheSeedRejectsIncompleteOrGarbage() {
        XCTAssertNil(parseUsageCache(Data(#"{"session":5}"#.utf8)))       // no weekly
        XCTAssertNil(parseUsageCache(Data(#"{"weekly":5}"#.utf8)))        // no session
        XCTAssertNil(parseUsageCache(Data(#"{}"#.utf8)))
        XCTAssertNil(parseUsageCache(Data("not json".utf8)))
    }

    func testSeededSnapshotIsStaleNotLoadingNotUnavailable() {
        var snap = UsageSnapshot()
        snap.subscription = SubscriptionUsage(sessionPct: 13, weeklyPct: 2, sonnetPct: nil,
                                              sessionResetIn: nil, weeklyResetIn: nil, planLabel: nil)
        snap.subscriptionSeeded = true
        XCTAssertTrue(snap.subscriptionStale)      // grayed, not presented as live
        XCTAssertFalse(snap.subscriptionLoading)   // we DO have a reading → not "loading"
    }

    func testEmptySnapshotIsLoading() {
        let snap = UsageSnapshot()
        XCTAssertTrue(snap.subscriptionLoading)
        XCTAssertFalse(snap.subscriptionStale)
    }

    // MARK: - Keychain error classification (transient blip vs genuinely logged out)

    func testKeychainTransientVsLoggedOut() {
        // Transient: momentary unavailability (e.g. just after Claude Code rewrote the item) → retry quietly.
        XCTAssertTrue(KeychainError.notFound(errSecInteractionNotAllowed).isTransient)
        XCTAssertTrue(KeychainError.notFound(errSecAuthFailed).isTransient)
        XCTAssertTrue(KeychainError.notFound(errSecNotAvailable).isTransient)
        XCTAssertFalse(KeychainError.notFound(errSecInteractionNotAllowed).isLoggedOut)
        // Logged out: the item genuinely isn't there → actionable.
        XCTAssertTrue(KeychainError.notFound(errSecItemNotFound).isLoggedOut)
        XCTAssertFalse(KeychainError.notFound(errSecItemNotFound).isTransient)
        // noToken is neither (the item exists but the shape was unreadable).
        XCTAssertFalse(KeychainError.noToken.isTransient)
        XCTAssertFalse(KeychainError.noToken.isLoggedOut)
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

    func testRetryAfterHeaderParsing() {
        let url = URL(string: "https://api.anthropic.com")!
        func resp(_ headers: [String: String]) -> HTTPURLResponse {
            HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: headers)!
        }
        XCTAssertEqual(retryAfterSeconds(from: resp(["Retry-After": "90"])), 90)        // delta-seconds
        XCTAssertEqual(retryAfterSeconds(from: resp(["Retry-After": "  0 "])), 0)
        XCTAssertNil(retryAfterSeconds(from: resp([:])))                                 // absent → nil
        XCTAssertNil(retryAfterSeconds(from: resp(["Retry-After": "garbage"])))          // unparseable → nil
        let httpDate = retryAfterSeconds(from: resp(["Retry-After": "Wed, 21 Oct 2099 07:28:00 GMT"]))
        XCTAssertNotNil(httpDate)                                                        // HTTP-date supported
        XCTAssertGreaterThan(httpDate ?? 0, 0)
    }
}
