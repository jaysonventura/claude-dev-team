import XCTest
@testable import cdt_menubar

/// Covers the pure freshness math behind the cache reader: the age of a reading and whether it's still
/// within the window (above which the menu bar grays it). `usageReadingIsStale` is built on `usageCacheFresh`,
/// so these boundaries underpin the displayed staleness. No filesystem: `ts`/`now` are injected.
final class UsageCacheTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)

    private func ts(secondsAgo: TimeInterval) -> Int { Int(now.timeIntervalSince1970 - secondsAgo) }

    func testAgeSeconds() throws {
        let age = try XCTUnwrap(usageCacheAgeSeconds(ts: ts(secondsAgo: 120), now: now))
        XCTAssertEqual(age, 120, accuracy: 0.5)
        XCTAssertNil(usageCacheAgeSeconds(ts: nil, now: now))           // no timestamp → unknown age
    }

    func testFreshWithinWindow() {
        XCTAssertTrue(usageCacheFresh(ts: ts(secondsAgo: 0), now: now, maxAge: 600))     // just written
        XCTAssertTrue(usageCacheFresh(ts: ts(secondsAgo: 599), now: now, maxAge: 600))   // 1s inside
    }

    func testStaleAtOrBeyondWindow() {
        XCTAssertFalse(usageCacheFresh(ts: ts(secondsAgo: 600), now: now, maxAge: 600))  // exactly at edge → stale
        XCTAssertFalse(usageCacheFresh(ts: ts(secondsAgo: 3600), now: now, maxAge: 600)) // an hour old
    }

    func testMissingTimestampIsNotFresh() {
        XCTAssertFalse(usageCacheFresh(ts: nil, now: now, maxAge: 600))  // can't trust an undated reading
    }

    func testFutureTimestampIsNotFresh() {
        // Clock skew: a `ts` in the future yields a negative age — treat as not fresh, never trust it.
        XCTAssertFalse(usageCacheFresh(ts: ts(secondsAgo: -120), now: now, maxAge: 600))
    }
}
