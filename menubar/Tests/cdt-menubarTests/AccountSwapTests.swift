import XCTest
@testable import cdt_menubar

/// Unit tests for AccountSwap.parseList(_:) — pure decoder, no live cswap process.
/// Feeds fixture JSON strings (matching the cswap 0.14+ schema) and asserts the model.
final class AccountSwapTests: XCTestCase {

    // MARK: - Fixtures

    /// Full two-account response matching the cswap 0.14 schema.
    private let twoAccountJSON = """
    {
      "schemaVersion": 1,
      "activeAccountNumber": 1,
      "accounts": [
        {
          "number": 1,
          "email": "user@example.com",
          "active": true,
          "usageStatus": "ok",
          "usage": {
            "fiveHour": { "pct": 25.0, "resetsAt": "2026-06-22T23:29:59Z" },
            "sevenDay":  { "pct": 16.0, "resetsAt": "2026-06-26T17:59:59Z" }
          }
        },
        {
          "number": 2,
          "email": "other@example.com",
          "active": false,
          "usageStatus": "rate_limited",
          "usage": {
            "fiveHour": { "pct": 100.0, "resetsAt": "2026-06-22T23:29:59Z" },
            "sevenDay":  { "pct": 88.5, "resetsAt": "2026-06-26T17:59:59Z" }
          }
        }
      ]
    }
    """

    /// A single active account with no usage fields (older schema compat / missing usage).
    private let minimalAccountJSON = """
    {
      "schemaVersion": 1,
      "activeAccountNumber": 3,
      "accounts": [
        {
          "number": 3,
          "email": "minimal@example.com",
          "active": true
        }
      ]
    }
    """

    /// Error payload — cswap returns {"schemaVersion":1,"error":{...}} with non-zero exit.
    private let errorPayloadJSON = """
    {
      "schemaVersion": 1,
      "error": { "message": "No accounts configured" }
    }
    """

    /// Completely empty / garbage bytes.
    private let garbageJSON = Data([0x00, 0x01, 0x02, 0xFF])

    // MARK: - Tests

    func testTwoAccountsDecoded() {
        let accounts = AccountSwap.parseList(Data(twoAccountJSON.utf8))
        XCTAssertEqual(accounts.count, 2)
    }

    func testFirstAccountIsActive() {
        let accounts = AccountSwap.parseList(Data(twoAccountJSON.utf8))
        let first = accounts.first
        XCTAssertNotNil(first)
        XCTAssertEqual(first?.number, 1)
        XCTAssertEqual(first?.email, "user@example.com")
        XCTAssertTrue(first?.active == true)
        XCTAssertFalse(first?.rateLimited == true)
    }

    func testFirstAccountUsagePercentages() {
        let accounts = AccountSwap.parseList(Data(twoAccountJSON.utf8))
        let first = accounts.first!
        XCTAssertEqual(first.fiveHourPct, 25)
        XCTAssertEqual(first.sevenDayPct, 16)
    }

    func testSecondAccountIsRateLimited() {
        let accounts = AccountSwap.parseList(Data(twoAccountJSON.utf8))
        XCTAssertEqual(accounts.count, 2)
        let second = accounts[1]
        XCTAssertEqual(second.number, 2)
        XCTAssertEqual(second.email, "other@example.com")
        XCTAssertFalse(second.active)
        XCTAssertTrue(second.rateLimited)
        XCTAssertEqual(second.fiveHourPct, 100)
        XCTAssertEqual(second.sevenDayPct, 89)   // 88.5 rounded to 89
    }

    func testSecondAccountResetInfo() {
        let accounts = AccountSwap.parseList(Data(twoAccountJSON.utf8))
        let second = accounts[1]
        // resetIn should return the 7d resets timestamp
        XCTAssertNotNil(second.resetIn)
        XCTAssertEqual(second.sevenDayResetsAt, "2026-06-26T17:59:59Z")
    }

    func testMinimalAccountMissingUsageIsNil() {
        let accounts = AccountSwap.parseList(Data(minimalAccountJSON.utf8))
        XCTAssertEqual(accounts.count, 1)
        let acc = accounts.first!
        XCTAssertEqual(acc.number, 3)
        XCTAssertEqual(acc.email, "minimal@example.com")
        XCTAssertTrue(acc.active)
        XCTAssertNil(acc.fiveHourPct)
        XCTAssertNil(acc.sevenDayPct)
        XCTAssertNil(acc.usageStatus)
        XCTAssertFalse(acc.rateLimited)    // nil usageStatus → not rate limited
    }

    func testErrorPayloadReturnsEmpty() {
        let accounts = AccountSwap.parseList(Data(errorPayloadJSON.utf8))
        XCTAssertTrue(accounts.isEmpty, "Error payload should decode to no accounts")
    }

    func testGarbageDataReturnsEmpty() {
        let accounts = AccountSwap.parseList(garbageJSON)
        XCTAssertTrue(accounts.isEmpty, "Garbage data must not crash or return accounts")
    }

    func testEmptyDataReturnsEmpty() {
        let accounts = AccountSwap.parseList(Data())
        XCTAssertTrue(accounts.isEmpty, "Empty data must not crash")
    }

    func testFractionalPctRounded() {
        // 88.5 → 89 (standard rounding)
        let accounts = AccountSwap.parseList(Data(twoAccountJSON.utf8))
        let second = accounts[1]
        XCTAssertEqual(second.sevenDayPct, 89)
    }

    func testAccountsWithNullResetsAt() {
        let json = """
        {
          "schemaVersion": 1,
          "activeAccountNumber": 1,
          "accounts": [{
            "number": 1,
            "email": "test@example.com",
            "active": true,
            "usageStatus": "ok",
            "usage": {
              "fiveHour": { "pct": 10.0, "resetsAt": null },
              "sevenDay":  { "pct": 50.0, "resetsAt": null }
            }
          }]
        }
        """
        let accounts = AccountSwap.parseList(Data(json.utf8))
        XCTAssertEqual(accounts.count, 1)
        let acc = accounts[0]
        XCTAssertEqual(acc.fiveHourPct, 10)
        XCTAssertEqual(acc.sevenDayPct, 50)
        XCTAssertNil(acc.fiveHourResetsAt)
        XCTAssertNil(acc.sevenDayResetsAt)
        XCTAssertNil(acc.resetIn)
    }

    func testExtraUnknownFieldsAreIgnored() {
        // Forward-compat: new fields in future cswap versions must not crash the decode.
        let json = """
        {
          "schemaVersion": 2,
          "activeAccountNumber": 1,
          "futureField": "some future value",
          "accounts": [{
            "number": 1,
            "email": "compat@example.com",
            "active": true,
            "usageStatus": "ok",
            "newUnknownField": 42,
            "usage": {
              "fiveHour": { "pct": 5.0, "resetsAt": "2026-06-30T00:00:00Z", "newWindow": true },
              "sevenDay":  { "pct": 20.0, "resetsAt": "2026-07-01T00:00:00Z" }
            }
          }]
        }
        """
        let accounts = AccountSwap.parseList(Data(json.utf8))
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts[0].email, "compat@example.com")
        XCTAssertEqual(accounts[0].fiveHourPct, 5)
    }

    func testMissingNumberOrEmailSkipsAccount() {
        let json = """
        {
          "schemaVersion": 1,
          "accounts": [
            { "number": 1, "email": "good@example.com", "active": false },
            { "email": "no-number@example.com", "active": false },
            { "number": 99, "active": false }
          ]
        }
        """
        let accounts = AccountSwap.parseList(Data(json.utf8))
        // Only the entry with both number AND email is returned.
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts[0].number, 1)
    }
}
