import XCTest
import Security
@testable import cdt_menubar

/// Covers the keychain-denial backoff gating — the PURE decision that stops a persistent, non-interactive
/// Keychain denial from becoming a ~30s busy-retry loop under default-ON. `keychainDenialPausesRealtime`
/// answers: does this failed-read OSStatus mean "pause + offer an explicit Grant" (back off to the 10-min
/// floor) instead of a next-tick retry? Also verifies `KeychainError.isInteractionRequired` agrees, so the
/// scheduler and the CLI classify a denial identically. No clock, no filesystem, no Keychain access.
final class KeychainBackoffTests: XCTestCase {

    // MARK: - the pure gating predicate

    func testDenialFamilyPauses() {
        // The no-UI denial family: a background read that WOULD have prompted returns one of these instead.
        // Empirically the same denial surfaces as either notAllowed or authFailed on macOS, so BOTH pause.
        XCTAssertTrue(keychainDenialPausesRealtime(errSecInteractionNotAllowed))
        XCTAssertTrue(keychainDenialPausesRealtime(errSecAuthFailed))
        XCTAssertTrue(keychainDenialPausesRealtime(errSecNotAvailable))
    }

    func testNonDenialDoesNotPause() {
        // A genuine "logged out" is actionable but NOT a grant/pause case (handled separately, and the
        // 10-min floor already prevents a loop). Success and unrelated codes never pause.
        XCTAssertFalse(keychainDenialPausesRealtime(errSecItemNotFound))
        XCTAssertFalse(keychainDenialPausesRealtime(errSecSuccess))
        XCTAssertFalse(keychainDenialPausesRealtime(errSecDuplicateItem))
        XCTAssertFalse(keychainDenialPausesRealtime(errSecDecode))
        XCTAssertFalse(keychainDenialPausesRealtime(errSecUserCanceled))
    }

    // MARK: - the error classifier used by the store + CLI agrees with the pure predicate

    func testIsInteractionRequiredMatchesPredicate() {
        for status: OSStatus in [errSecInteractionNotAllowed, errSecAuthFailed, errSecNotAvailable,
                                 errSecItemNotFound, errSecSuccess, errSecDuplicateItem, errSecUserCanceled] {
            XCTAssertEqual(KeychainError.notFound(status).isInteractionRequired,
                           keychainDenialPausesRealtime(status),
                           "classifier must agree with the pure predicate for status \(status)")
        }
        // `.noToken` (item read, shape unreadable) is never an interaction/grant case.
        XCTAssertFalse(KeychainError.noToken.isInteractionRequired)
    }

    func testInteractionRequiredAndLoggedOutAreMutuallyExclusive() {
        // A single status is at most one of {needs-grant, logged-out} — the store branches on this.
        let denial = KeychainError.notFound(errSecInteractionNotAllowed)
        XCTAssertTrue(denial.isInteractionRequired)
        XCTAssertFalse(denial.isLoggedOut)

        let loggedOut = KeychainError.notFound(errSecItemNotFound)
        XCTAssertTrue(loggedOut.isLoggedOut)
        XCTAssertFalse(loggedOut.isInteractionRequired)
    }
}
