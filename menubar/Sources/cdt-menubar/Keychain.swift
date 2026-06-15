import Foundation
import Security

enum KeychainError: LocalizedError {
    case notFound(OSStatus)
    case noToken

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Claude Code credentials not found in Keychain — is Claude Code installed and logged in?"
        case .noToken:
            return "Could not read the OAuth access token from the Keychain item."
        }
    }
}

// The Keychain item "Claude Code-credentials" stores JSON: {"claudeAiOauth":{"accessToken":"...", ...}}
private struct ClaudeCredentials: Decodable {
    struct OAuth: Decodable { let accessToken: String }
    let claudeAiOauth: OAuth
}

/// Reads the Claude Code OAuth access token from the macOS Keychain. Never logs it.
func readClaudeOAuthToken() throws -> String {
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
        return creds.claudeAiOauth.accessToken
    }
    // Defensive fallback: scan for an "accessToken":"..." field if the shape ever changes.
    if let json = String(data: data, encoding: .utf8),
       let range = json.range(of: "\"accessToken\"\\s*:\\s*\"([^\"]+)\"", options: .regularExpression) {
        let match = String(json[range])
        if let q = match.range(of: ":\\s*\"", options: .regularExpression) {
            let token = match[q.upperBound...].dropLast()
            if !token.isEmpty { return String(token) }
        }
    }
    throw KeychainError.noToken
}
