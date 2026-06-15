import Foundation

// Response shape of GET https://api.anthropic.com/api/oauth/usage (undocumented; verified).
private struct OAuthUsageResponse: Decodable {
    struct Period: Decodable {
        let utilization: Double
        let resetsAt: String

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }

        var resetDate: Date? {
            let full = ISO8601DateFormatter()
            full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = full.date(from: resetsAt) { return d }
            return ISO8601DateFormatter().date(from: resetsAt)
        }
    }

    let fiveHour: Period?
    let sevenDay: Period?
    let sevenDaySonnet: Period?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
    }
}

/// Fetches the real subscription usage. Throws on missing token / network / non-200 / decode error.
/// The token is read from the Keychain and only sent to api.anthropic.com — never logged or persisted.
func fetchSubscriptionUsage() async throws -> SubscriptionUsage {
    let token = try readClaudeOAuthToken()

    var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
    req.httpMethod = "GET"
    req.timeoutInterval = 15
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

    let (data, response) = try await URLSession.shared.data(for: req)
    guard let http = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
    }
    guard http.statusCode == 200 else {
        throw NSError(domain: "oauth-usage", code: http.statusCode,
                      userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
    }

    let r = try JSONDecoder().decode(OAuthUsageResponse.self, from: data)
    return SubscriptionUsage(
        sessionPct: Int((r.fiveHour?.utilization ?? 0).rounded()),
        weeklyPct: Int((r.sevenDay?.utilization ?? 0).rounded()),
        sonnetPct: r.sevenDaySonnet.map { Int($0.utilization.rounded()) },
        sessionResetIn: r.fiveHour?.resetDate.map { formatCountdown(to: $0) },
        weeklyResetIn: r.sevenDay?.resetDate.map { formatCountdown(to: $0) }
    )
}
