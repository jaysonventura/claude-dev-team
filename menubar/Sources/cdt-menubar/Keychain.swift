import Foundation
import Security
import LocalAuthentication
import CryptoKit

/// A clean, classifiable Keychain failure. The OSStatus lets the realtime scheduler tell a persistent
/// "can't read without the user's consent" denial from a genuine "not logged in" (both actionable) without
/// string-matching a localized message.
enum KeychainError: LocalizedError {
    case notFound(OSStatus)
    case noToken

    var errorDescription: String? {
        switch self {
        case .notFound(let status):
            let reason = (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
            return "Claude Code credentials not readable from Keychain (\(reason))"
        case .noToken:
            return "Could not read the OAuth access token from the Keychain item."
        }
    }

    /// A persistent "can't read this without the user's consent" denial: the app isn't in the item's
    /// trusted-app ACL (macOS resets it when Claude Code rewrites the credential) or the keychain is locked,
    /// and we deliberately suppress interactive UI so no password/allow dialog is ever shown for a background
    /// read. The read returns one of these codes INSTEAD of prompting. The scheduler treats them as
    /// "pause + offer an explicit Grant" — never a busy retry loop. (Same status family as
    /// `keychainDenialPausesRealtime`.)
    var isInteractionRequired: Bool {
        if case .notFound(let s) = self { return keychainDenialPausesRealtime(s) }
        return false
    }

    /// The Keychain item genuinely doesn't exist → Claude Code isn't logged in (an actionable state).
    var isLoggedOut: Bool {
        if case .notFound(let s) = self { return s == errSecItemNotFound }
        return false
    }
}

/// PURE decision: does an OSStatus from a FAILED automatic (non-interactive) Keychain read mean the realtime
/// scheduler must PAUSE (back off to the 10-min floor and offer an explicit Grant) rather than retry on the
/// next 30s tick? True for the no-UI denial family — the app isn't in the item's trusted-app ACL (reset when
/// Claude Code rewrote the credential), the keychain is locked, or the item is momentarily unavailable, and
/// UI is suppressed. Empirically the same denial surfaces as either `errSecInteractionNotAllowed` or
/// `errSecAuthFailed` on this platform, so they are NOT cleanly separable from a momentary lock — we prefer
/// the SAFE backoff (never a 30s busy-retry loop under default-ON). No clock/IO → exhaustively unit-tested.
func keychainDenialPausesRealtime(_ status: OSStatus) -> Bool {
    status == errSecInteractionNotAllowed || status == errSecAuthFailed || status == errSecNotAvailable
}

// The Keychain item "Claude Code-credentials" stores JSON: {"claudeAiOauth":{"accessToken":"…", …}}.
// We read ONLY the access token — the menu bar no longer displays the plan tier, so nothing else is decoded.
private struct ClaudeCredentials: Decodable {
    struct OAuth: Decodable { let accessToken: String }
    let claudeAiOauth: OAuth
}

/// The Claude Code account read from the Keychain: just the OAuth access token. Read-only — the menu bar
/// NEVER mints, refreshes, rotates, or writes a credential; it only performs a `SecItemCopyMatching` read.
struct ClaudeAccount {
    let accessToken: String
}

/// Globally gate whether Keychain operations for THIS process may show UI, across a single read.
///
/// `SecKeychainSetUserInteractionAllowed(false)` is the ONE API that governs the legacy ACL confirmation
/// dialog this app hits — the "CDT Usage wants to access key 'Claude Code-credentials' … enter the login
/// keychain password" prompt. With interaction disabled, a read that WOULD prompt instead returns
/// `errSecInteractionNotAllowed` / `errSecAuthFailed` (handled by `keychainDenialPausesRealtime`), so no
/// dialog ever appears for a background read. There is no non-deprecated replacement for this specific
/// process-wide gate; the deprecation warning is expected and load-bearing.
private func setKeychainInteractionAllowed(_ allowed: Bool) {
    _ = SecKeychainSetUserInteractionAllowed(allowed)   // deprecated (10.10) but the only gate for this prompt
}

/// The ONE serial queue every Keychain read runs on, so the PROCESS-GLOBAL interaction toggle can't be
/// corrupted by two reads at once. `SecKeychainSetUserInteractionAllowed` is process-wide: without this,
/// the automatic non-interactive read (realtime fetch on a utility queue / token fingerprint on main) and the
/// interactive Grant (`grantKeychainNow`, a background queue) could interleave on that flag — a Grant running
/// while interaction was flipped off (its prompt silently suppressed) or a background read running while it
/// was flipped on (a stray dialog). Funneling BOTH `copyClaudeAccount` entry points — and therefore the
/// fingerprint read, which goes through `readClaudeAccount` — through this queue makes them mutually exclusive.
private let keychainQueue = DispatchQueue(label: "com.claude-dev-team.menubar.keychain-read")

/// The single, READ-ONLY Keychain read. `allowInteraction` is FALSE for every automatic/background read
/// (belt-and-suspenders UI suppression → a non-trusted / ACL-reset read returns a denial code instead of
/// popping a dialog) and TRUE only for the one explicit, user-initiated Grant. NEVER `SecItemAdd`/`Update`/
/// `Delete`; never mints/refreshes/rotates a token; never logs the token.
private func copyClaudeAccount(allowInteraction: Bool) throws -> ClaudeAccount {
    var query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "Claude Code-credentials",
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne
    ]
    if !allowInteraction {
        // Modern belt (non-deprecated): an LAContext with interaction disallowed makes any auth-controlled
        // item fail rather than present the biometric/passcode UI. Harmless for a plain item (this one),
        // and Apple's recommended replacement for the deprecated `kSecUseAuthenticationUI` flag.
        let ctx = LAContext()
        ctx.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = ctx
    }

    // Suspenders: gate the legacy ACL prompt for the duration of THIS read, then always restore interaction
    // so the explicit Grant path (and any unrelated system UI) is never left disabled. The WHOLE section runs
    // on `keychainQueue` so "set process-global flag → SecItemCopyMatching → restore" is one atomic critical
    // section: an automatic (non-interactive) read can never overlap the interactive Grant on that shared
    // flag. Strictly read-only — `SecItemCopyMatching` only.
    return try keychainQueue.sync {
        setKeychainInteractionAllowed(allowInteraction)
        defer { setKeychainInteractionAllowed(true) }

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.notFound(status)
        }
        if let creds = try? JSONDecoder().decode(ClaudeCredentials.self, from: data) {
            return ClaudeAccount(accessToken: creds.claudeAiOauth.accessToken)
        }
        // Defensive fallback: scan for an "accessToken":"..." field if the shape ever changes.
        if let json = String(data: data, encoding: .utf8),
           let range = json.range(of: "\"accessToken\"\\s*:\\s*\"([^\"]+)\"", options: .regularExpression) {
            let match = String(json[range])
            if let q = match.range(of: ":\\s*\"", options: .regularExpression) {
                let token = match[q.upperBound...].dropLast()
                if !token.isEmpty { return ClaudeAccount(accessToken: String(token)) }
            }
        }
        throw KeychainError.noToken
    }
}

/// Reads the Claude Code OAuth access token from the macOS Keychain — NON-INTERACTIVELY. This is the read
/// every automatic/background path uses (realtime fetch, token fingerprint): it can NEVER show a dialog. A
/// non-trusted / ACL-reset read fails with a denial code (`isInteractionRequired`) instead of prompting.
/// Read-only; never logs the token.
func readClaudeAccount() throws -> ClaudeAccount {
    try copyClaudeAccount(allowInteraction: false)
}

/// The ONLY place a Keychain prompt may appear: a single INTERACTIVE read, run from an explicit,
/// user-initiated action (the "Grant Keychain access…" menu item / `--grant` CLI) so the user can
/// consciously click "Always Allow" and re-add this app to the item's trusted-app ACL. Still strictly
/// READ-ONLY (`SecItemCopyMatching` only) — it never mints, refreshes, rotates, or writes a credential.
/// Returns success or the classifiable `KeychainError` (e.g. the user clicked Deny).
@discardableResult
func grantKeychainAccess() -> Result<Void, KeychainError> {
    do {
        _ = try copyClaudeAccount(allowInteraction: true)
        return .success(())
    } catch let e as KeychainError {
        return .failure(e)
    } catch {
        return .failure(.notFound(errSecInternalError))
    }
}

/// A stable, non-reversible fingerprint of the current Keychain access token (first 16 hex of its
/// SHA-256), or nil if it can't be read. Used ONLY to notice when Claude Code has rotated the token
/// (so a menu bar stuck on an expired token can refetch immediately, rather than waiting out a backoff).
/// Reads NON-INTERACTIVELY (via `readClaudeAccount`), so it can never prompt either. The raw token is never
/// logged, persisted, or returned.
func claudeTokenFingerprint() -> String? {
    guard let token = try? readClaudeAccount().accessToken,
          let data = token.data(using: .utf8) else { return nil }
    let digest = SHA256.hash(data: data)
    return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
}
