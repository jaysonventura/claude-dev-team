import Foundation
import Security
import CryptoKit

enum KeychainError: LocalizedError {
    case notFound(OSStatus)
    case noToken

    var errorDescription: String? {
        switch self {
        case .notFound(let status):
            // Surface the OSStatus so a genuine Keychain error (e.g. interaction-not-allowed) is
            // distinguishable from the common "not logged in" (errSecItemNotFound).
            let reason = (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
            return "Claude Code credentials not readable from Keychain (\(reason)) — is Claude Code installed and logged in?"
        case .noToken:
            return "Could not read the OAuth access token from the Keychain item."
        }
    }

    /// A TRANSIENT "can't read it right this second" — the item is momentarily locked or interaction isn't
    /// allowed (typically just after Claude Code rewrote the credential, which briefly resets its ACL).
    /// These clear on their own within seconds, so the menu bar retries quietly and keeps showing the cached
    /// %s instead of flashing a scary error.
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

// The Keychain item "Claude Code-credentials" stores JSON:
//   {"claudeAiOauth":{"accessToken":"…","subscriptionType":"max","rateLimitTier":"default_claude_max_5x", …}}
private struct ClaudeCredentials: Decodable {
    struct OAuth: Decodable {
        let accessToken: String
        let subscriptionType: String?   // "max" | "pro" | "free" | … (absent on older logins)
        let rateLimitTier: String?      // e.g. "default_claude_max_5x" — encodes the 5x/20x multiplier
    }
    let claudeAiOauth: OAuth
}

/// The Claude Code account from the Keychain: the OAuth token plus the plan fields.
/// Plan fields are optional — never assume a tier that isn't present (see the 1.22.1 mislabel fix).
struct ClaudeAccount {
    let accessToken: String
    let subscriptionType: String?
    let rateLimitTier: String?
}

/// Reads the Claude Code OAuth credentials from the macOS Keychain. Never logs the token.
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
        return ClaudeAccount(accessToken: creds.claudeAiOauth.accessToken,
                             subscriptionType: creds.claudeAiOauth.subscriptionType,
                             rateLimitTier: creds.claudeAiOauth.rateLimitTier)
    }
    // Defensive fallback: scan for an "accessToken":"..." field if the shape ever changes.
    if let json = String(data: data, encoding: .utf8),
       let range = json.range(of: "\"accessToken\"\\s*:\\s*\"([^\"]+)\"", options: .regularExpression) {
        let match = String(json[range])
        if let q = match.range(of: ":\\s*\"", options: .regularExpression) {
            let token = match[q.upperBound...].dropLast()
            if !token.isEmpty {
                return ClaudeAccount(accessToken: String(token), subscriptionType: nil, rateLimitTier: nil)
            }
        }
    }
    throw KeychainError.noToken
}

/// Reads just the OAuth access token (for callers that don't need the plan fields).
func readClaudeOAuthToken() throws -> String { try readClaudeAccount().accessToken }

/// A stable, non-reversible fingerprint of the current Keychain access token (first 16 hex of its
/// SHA-256), or nil if it can't be read. Used ONLY to notice when Claude Code has rotated the token
/// (so the menu bar can refetch immediately and recover from an expired-token state in seconds, rather
/// than waiting out a backoff). The raw token is never logged, persisted, or returned by this function.
func claudeTokenFingerprint() -> String? {
    guard let token = try? readClaudeAccount().accessToken,
          let data = token.data(using: .utf8) else { return nil }
    let digest = SHA256.hash(data: data)
    return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
}
