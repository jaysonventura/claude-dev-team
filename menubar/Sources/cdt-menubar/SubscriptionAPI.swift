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

// A dedicated session that NEVER caches: usage % must be read live, so "Refresh now" always does a real
// network round-trip and can't be served a stale response from URLSession.shared's on-disk URLCache.
private let liveUsageSession: URLSession = {
    let cfg = URLSessionConfiguration.ephemeral          // no persistent cache/cookies
    cfg.urlCache = nil
    cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    cfg.timeoutIntervalForResource = 25                   // HARD cap on the whole fetch so a stalled
                                                          // request can't hang for days and freeze polling
    return URLSession(configuration: cfg)
}()

/// Fetches the real subscription usage. Throws on missing token / network / non-200 / decode error.
/// The token is read from the Keychain and only sent to api.anthropic.com — never logged or persisted.
func fetchSubscriptionUsage() async throws -> SubscriptionUsage {
    let account = try readClaudeAccount()
    let token = account.accessToken

    var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                         cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
    req.httpMethod = "GET"
    req.timeoutInterval = 15
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
    req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")   // ask any intermediary to revalidate

    let (data, response) = try await liveUsageSession.data(for: req)
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
        weeklyResetIn: r.sevenDay?.resetDate.map { formatCountdown(to: $0) },
        planLabel: planLabel(subscriptionType: account.subscriptionType, rateLimitTier: account.rateLimitTier)
    )
}
