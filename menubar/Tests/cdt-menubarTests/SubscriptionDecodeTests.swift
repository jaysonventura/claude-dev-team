import XCTest
import Security
@testable import cdt_menubar

/// Regression coverage for the resilient `/api/oauth/usage` decoder, the `Retry-After` parser, the clean
/// `UsageError` surface, and the Keychain error classification — the pieces the throttled realtime fetch
/// leans on. All PURE (no network, no live Keychain): captured bodies + synthesized HTTP responses.
///
/// The bug these guard against: the live response carries `"seven_day_sonnet":{...,"resets_at":null}`, and a
/// non-tolerant model threw `DecodingError` on that one null — aborting the WHOLE decode and discarding the
/// valid session/weekly numbers. The parser must tolerate nulls/missing/new fields, and must surface a CLEAN
/// error (never a fabricated "0%") when a body genuinely isn't a usage payload.
final class SubscriptionDecodeTests: XCTestCase {

    private func parse(_ json: String) throws -> UsageReading {
        try parseUsageResponse(Data(json.utf8))
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
        XCTAssertEqual(u.sessionPct, 1)             // five_hour 1.0 → 1% (previously lost entirely to one null)
        XCTAssertEqual(u.weeklyPct, 0)
    }

    func testNullUtilizationOnSessionStillUsesWeekly() throws {
        let u = try parse(#"{"five_hour":{"utilization":null,"resets_at":null},"seven_day":{"utilization":42.0}}"#)
        XCTAssertEqual(u.sessionPct, 0)    // null utilization → 0, not a crash
        XCTAssertEqual(u.weeklyPct, 42)
    }

    func testMissingFiveHourStillUsable() throws {
        let u = try parse(#"{"seven_day":{"utilization":73.0}}"#)
        XCTAssertEqual(u.sessionPct, 0)
        XCTAssertEqual(u.weeklyPct, 73)
    }

    func testRoundingHalfUp() throws {
        let u = try parse(#"{"five_hour":{"utilization":12.5},"seven_day":{"utilization":88.4}}"#)
        XCTAssertEqual(u.sessionPct, 13)
        XCTAssertEqual(u.weeklyPct, 88)
    }

    // MARK: - clean failures (never a raw Cocoa "couldn't be read" string, never a fake 0%)

    func testEmptyBodyThrowsEmptyResponse() {
        XCTAssertThrowsError(try parse("")) { error in
            XCTAssertEqual(error as? UsageError, .emptyResponse)
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

    func testGarbageBodyThrowsUnexpectedFormat() {
        XCTAssertThrowsError(try parse("not json at all")) { error in
            XCTAssertEqual(error as? UsageError, .unexpectedFormat)
        }
    }

    // MARK: - UsageError surface (the scheduler branches on httpStatus / retryAfter, no string matching)

    func testHttpErrorMessagesAreActionable() {
        XCTAssertEqual(UsageError.http(401).errorDescription, "token expired — Claude Code will refresh it")
        XCTAssertEqual(UsageError.http(403).httpStatus, 403)
        XCTAssertNil(UsageError.emptyResponse.httpStatus)
    }

    func testRateLimitedReportsStatusAndRetryAfter() {
        XCTAssertEqual(UsageError.rateLimited(retryAfter: 120).httpStatus, 429)
        XCTAssertEqual(UsageError.rateLimited(retryAfter: 120).retryAfter, 120)
        XCTAssertNil(UsageError.rateLimited(retryAfter: nil).retryAfter)
        XCTAssertEqual(UsageError.rateLimited(retryAfter: nil).errorDescription, "rate limited — will retry when allowed")
    }

    // MARK: - Retry-After parsing (delta-seconds / HTTP-date / garbage)

    func testRetryAfterHeaderParsing() {
        let url = URL(string: "https://api.anthropic.com")!
        func resp(_ headers: [String: String]) -> HTTPURLResponse {
            HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: headers)!
        }
        XCTAssertEqual(retryAfterSeconds(from: resp(["Retry-After": "120"])), 120)     // delta-seconds
        XCTAssertEqual(retryAfterSeconds(from: resp(["Retry-After": "  0 "])), 0)       // trimmed
        XCTAssertNil(retryAfterSeconds(from: resp([:])))                                // absent → nil
        XCTAssertNil(retryAfterSeconds(from: resp(["Retry-After": "garbage"])))         // unparseable → nil
        let httpDate = retryAfterSeconds(from: resp(["Retry-After": "Wed, 21 Oct 2099 07:28:00 GMT"]))
        XCTAssertNotNil(httpDate)                                                       // HTTP-date supported
        XCTAssertGreaterThan(httpDate ?? 0, 0)
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
}
