import Foundation

// Response shape of GET https://api.anthropic.com/api/oauth/usage (undocumented; verified live).
//
// RESILIENCE IS THE WHOLE POINT HERE. The live payload contains nulls and fields that come and go
// (e.g. `"seven_day_sonnet":{"utilization":0.0,"resets_at":null}` — a JSON null). A non-tolerant model
// would let ONE null abort the entire decode ("The data couldn't be read because it is missing.") and
// discard the perfectly-valid session/weekly numbers. Every field is tolerant: a missing/null/wrong-typed
// field becomes nil and can never break the read of the fields that ARE valid. We only need `five_hour`
// (session) and `seven_day` (weekly) — the menu bar no longer shows sonnet or reset countdowns.
private struct OAuthUsageResponse: Decodable {
    struct Period: Decodable {
        let utilization: Double?

        enum CodingKeys: String, CodingKey { case utilization }

        // Fully fault-tolerant: `utilization` decodes with `try?`, so a null or unexpectedly typed value
        // yields nil instead of throwing and taking the whole response down with it.
        init(from decoder: Decoder) throws {
            let c = try? decoder.container(keyedBy: CodingKeys.self)
            utilization = (try? c?.decodeIfPresent(Double.self, forKey: .utilization)) ?? nil
        }
    }

    let fiveHour: Period?
    let sevenDay: Period?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }

    // Each period decodes independently — a malformed period can't abort its sibling.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fiveHour = (try? c.decodeIfPresent(Period.self, forKey: .fiveHour)) ?? nil
        sevenDay = (try? c.decodeIfPresent(Period.self, forKey: .sevenDay)) ?? nil
    }
}

/// A clean, user-facing failure for the usage fetch — so the menu never shows a raw Cocoa string like
/// "The data couldn't be read because it is missing." The `httpStatus` (when set) lets the scheduler
/// distinguish 429 / 401 / 403 for backoff and recovery without re-parsing a localized message.
enum UsageError: LocalizedError, Equatable {
    case http(Int)                              // non-200 (401 expired, 403 denied, 5xx, …)
    case rateLimited(retryAfter: TimeInterval?) // HTTP 429 — carries the server's Retry-After when present
    case emptyResponse                          // 200 but zero bytes
    case unexpectedFormat                       // 200 but the body isn't a usage payload we can read

    /// The HTTP status (429 for `.rateLimited`), else nil — lets the scheduler branch without string matching.
    var httpStatus: Int? {
        switch self {
        case .http(let c): return c
        case .rateLimited: return 429
        default: return nil
        }
    }

    /// The server-advertised back-off for a 429 (from the Retry-After header), in seconds, when known.
    var retryAfter: TimeInterval? {
        if case .rateLimited(let r) = self { return r }
        return nil
    }

    var errorDescription: String? {
        switch self {
        case .rateLimited: return "rate limited — will retry when allowed"
        case .http(401): return "token expired — Claude Code will refresh it"
        case .http(403): return "access denied — re-login may be needed"
        case .http(let c): return "service error (HTTP \(c)) — retrying"
        case .emptyResponse: return "no data returned — retrying"
        case .unexpectedFormat: return "usage format changed — retrying"
        }
    }
}

/// Parses a 429's back-off hint from the `Retry-After` header (delta-seconds or an HTTP-date), so we wait
/// exactly as long as the server asks instead of a blind fixed interval. Returns nil if absent/unparseable.
func retryAfterSeconds(from http: HTTPURLResponse) -> TimeInterval? {
    guard let raw = (http.value(forHTTPHeaderField: "Retry-After"))?
            .trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
    if let secs = TimeInterval(raw) { return max(0, secs) }       // "120" → 120s
    let fmt = DateFormatter()                                     // "Wed, 21 Oct 2026 07:28:00 GMT"
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.timeZone = TimeZone(identifier: "GMT")
    fmt.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    if let date = fmt.date(from: raw) { return max(0, date.timeIntervalSinceNow) }
    return nil
}

// A dedicated session that NEVER caches: usage % must be read live, so every fetch does a real network
// round-trip and can't be served a stale response from URLSession.shared's on-disk URLCache.
private let liveUsageSession: URLSession = {
    let cfg = URLSessionConfiguration.ephemeral          // no persistent cache/cookies
    cfg.urlCache = nil
    cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    cfg.timeoutIntervalForResource = 25                  // HARD cap so a stalled request can't hang polling
    return URLSession(configuration: cfg)
}()

/// Turns a raw `/api/oauth/usage` body into a `UsageReading` (session + weekly used %). PURE (no network)
/// so it is unit-tested against captured real payloads. Throws a clean `UsageError` — never a raw decoder
/// error — and REFUSES to fabricate a "0%" reading from a body it couldn't actually parse.
func parseUsageResponse(_ data: Data) throws -> UsageReading {
    guard !data.isEmpty else { throw UsageError.emptyResponse }
    guard let r = try? JSONDecoder().decode(OAuthUsageResponse.self, from: data) else {
        throw UsageError.unexpectedFormat
    }
    // Require at least one real utilization reading; otherwise this wasn't a usage payload (e.g. an error
    // envelope) and showing "0%" would be a lie. Surface it as a clean, retryable format error instead.
    guard r.fiveHour?.utilization != nil || r.sevenDay?.utilization != nil else {
        throw UsageError.unexpectedFormat
    }
    return UsageReading(
        sessionPct: Int((r.fiveHour?.utilization ?? 0).rounded()),
        weeklyPct: Int((r.sevenDay?.utilization ?? 0).rounded()))
}

/// Fetches the real subscription usage. Throws `UsageError`/`KeychainError` on missing token / network /
/// non-200 / decode. The token is read from the Keychain and only sent to api.anthropic.com — never logged
/// or persisted. Read-only on credentials: this NEVER mints, refreshes, or rotates a token.
func fetchSubscriptionUsage() async throws -> UsageReading {
    let token = try readClaudeAccount().accessToken

    var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                         cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
    req.httpMethod = "GET"
    req.timeoutInterval = 15
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
    req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")   // ask any intermediary to revalidate

    let (data, response) = try await liveUsageSession.data(for: req)
    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    guard http.statusCode == 200 else {
        if http.statusCode == 429 {
            throw UsageError.rateLimited(retryAfter: retryAfterSeconds(from: http))
        }
        throw UsageError.http(http.statusCode)
    }
    return try parseUsageResponse(data)
}

/// Blocking bridge around `fetchSubscriptionUsage()` for synchronous callers (the store's off-main path and
/// the `--refresh-usage` CLI). The async work runs in a detached task that captures NO `self`, so callers
/// stay warning-free under Swift 5 concurrency; the semaphore wait is bounded by the session's 25s cap.
/// Call this OFF the main thread only.
func fetchSubscriptionUsageBlocking() -> Result<UsageReading, Error> {
    let sem = DispatchSemaphore(value: 0)
    var result: Result<UsageReading, Error> = .failure(UsageError.emptyResponse)
    Task.detached {
        do { result = .success(try await fetchSubscriptionUsage()) }
        catch { result = .failure(error) }
        sem.signal()
    }
    sem.wait()
    return result
}
