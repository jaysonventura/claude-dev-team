import Foundation
import Security
import CryptoKit

/// A clean, classifiable Keychain failure. The OSStatus lets the realtime scheduler tell a momentary blip
/// (retry quietly) from a genuine "not logged in" (actionable) without string-matching a localized message.
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

    /// A TRANSIENT "can't read it right this second" — the item is momentarily locked or interaction isn't
    /// allowed (typically just after Claude Code rewrote the credential, which briefly resets its ACL).
    /// These clear on their own within seconds, so the menu bar retries quietly and keeps the cached %s.
    var isTransient: Bool {
        if case .notFound(let s) = self {
            return s == errSecInteractionNotAllowed || s == errSecAuthFailed || s == errSecNotAvailable
        }
        return false
    }

    /// The Keychain item genuinely doesn't exist → Claude Code isn't logged in (an actionable state).
    var isLoggedOut: Bool {
        if case .notFound(let s) = self { return s == errSecItemNotFound }
        return false
    }
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

/// Reads the Claude Code OAuth access token from the macOS Keychain. Read-only. Never logs the token.
func readClaudeAccount() throws -> ClaudeAccount {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "Claude Code-credentials",
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne
    ]
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

/// A stable, non-reversible fingerprint of the current Keychain access token (first 16 hex of its
/// SHA-256), or nil if it can't be read. Used ONLY to notice when Claude Code has rotated the token
/// (so a menu bar stuck on an expired token can refetch immediately, rather than waiting out a backoff).
/// The raw token is never logged, persisted, or returned.
func claudeTokenFingerprint() -> String? {
    guard let token = try? readClaudeAccount().accessToken,
          let data = token.data(using: .utf8) else { return nil }
    let digest = SHA256.hash(data: data)
    return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
}
