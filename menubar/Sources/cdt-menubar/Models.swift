import Foundation

// Real subscription usage from /api/oauth/usage (nil if the endpoint/login is unavailable).
struct SubscriptionUsage {
    let sessionPct: Int          // five_hour utilization (0-100)
    let weeklyPct: Int           // seven_day
    let sonnetPct: Int?          // seven_day_sonnet
    let sessionResetIn: String?  // formatted countdown, e.g. "33m"
    let weeklyResetIn: String?
    let planLabel: String?       // e.g. "Max 5x" / "Pro" (from the Keychain plan fields); nil when unknown
}

/// Human-readable plan label from the Keychain credential fields (`subscriptionType` + `rateLimitTier`).
/// Returns nil when the tier isn't present — never guess a tier that isn't in the data (the 1.22.1
/// regression hardcoded "Claude Max" and mislabeled Pro users; this only ever reports the real field).
func planLabel(subscriptionType: String?, rateLimitTier: String?) -> String? {
    guard let raw = subscriptionType?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
    let base: String
    switch raw.lowercased() {
    case "max":        base = "Max"
    case "pro":        base = "Pro"
    case "free":       base = "Free"
    case "team":       base = "Team"
    case "enterprise": base = "Enterprise"
    default:           base = raw.prefix(1).uppercased() + raw.dropFirst()   // title-case an unknown tier verbatim
    }
    // Append the rate multiplier only when the tier string clearly encodes one (e.g. "…_5x", "…_20x").
    if let tier = rateLimitTier?.lowercased(),
       let m = tier.range(of: "[0-9]+x", options: .regularExpression) {
        return "\(base) \(tier[m])"
    }
    return base
}

// Accurate local token usage, summed from ~/.claude/projects/*/*.jsonl.
struct ModelTokens {
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheCreate = 0
    var total: Int { input + output }   // headline "tokens" = input + output
}

struct LocalUsage {
    var today: [String: ModelTokens] = [:]
    var week: [String: ModelTokens] = [:]

    var todayTotal: Int { today.values.reduce(0) { $0 + $1.total } }
    var weekTotal: Int { week.values.reduce(0) { $0 + $1.total } }
}

// claude-dev-team activity from the SQLite DB.
struct TeamActivity {
    var sessions = 0                                      // chats logged in the last 7 days
    var agentRuns: [(role: String, count: Int)] = []     // subagent dispatches (specialists), by role
    var tasksByTier: [(tier: String, count: Int)] = []
}

// Everything the menu bar renders.
struct UsageSnapshot {
    var subscription: SubscriptionUsage?
    var subscriptionError: String?
    var subscriptionAsOf: Date?            // when `subscription` was last fetched successfully
    var local = LocalUsage()
    var team = TeamActivity()
    var lastUpdated = Date()

    /// True when we're still showing the last-good subscription reading but the most recent
    /// refresh failed (e.g. the OAuth token expired) — the displayed %s are stale, not live.
    var subscriptionStale: Bool { subscription != nil && subscriptionError != nil }

    /// True before the very first fetch resolves (no reading and no error yet). Lets the UI show
    /// "loading…" on first paint instead of a premature "unavailable" while the request is in flight.
    var subscriptionLoading: Bool { subscription == nil && subscriptionError == nil }
}

// MARK: - formatting helpers

func formatTokens(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
    if n >= 1_000 { return String(format: "%.0fk", Double(n) / 1_000) }
    return "\(n)"
}

func textBar(_ pct: Int, width: Int = 10) -> String {
    let filled = max(0, min(width, pct * width / 100))
    return String(repeating: "▓", count: filled) + String(repeating: "░", count: width - filled)
}

// 12-hour wall-clock time, e.g. "1:50 PM" (or "1:50:23 PM" with seconds). Used for "updated" / "as of".
func clockTime(_ d: Date, seconds: Bool = false) -> String {
    let f = DateFormatter()
    f.dateFormat = seconds ? "h:mm:ss a" : "h:mm a"
    f.amSymbol = "AM"; f.pmSymbol = "PM"
    return f.string(from: d)
}

func formatCountdown(to date: Date, now: Date = Date()) -> String {
    let s = date.timeIntervalSince(now)
    if s <= 0 { return "now" }
    // Under a day → a countdown ("in 3h 47m"); a day or more away → an absolute time ("Fri 1:59 AM").
    if s < 24 * 3600 {
        let h = Int(s) / 3600
        let m = (Int(s) % 3600) / 60
        return h > 0 ? "in \(h)h \(m)m" : "in \(m)m"
    }
    let f = DateFormatter()
    f.dateFormat = "EEE h:mm a"
    return f.string(from: date)
}

// Bare role name for display: drop a "plugin:" namespace prefix
// (e.g. "claude-dev-team:backend-engineer" -> "backend-engineer"; "claude-code-guide" stays as-is).
func shortRole(_ id: String) -> String {
    if let last = id.split(separator: ":").last { return String(last) }
    return id
}

// Short display name for a model id (e.g. "claude-opus-4-7" -> "Opus").
func shortModelName(_ id: String) -> String {
    let s = id.lowercased()
    if s.contains("opus") { return "Opus" }
    if s.contains("sonnet") { return "Sonnet" }
    if s.contains("haiku") { return "Haiku" }
    if s.contains("fable") { return "Fable" }
    return id
}

// Installed claude-dev-team version, for display. Prefer the app bundle's baked
// CFBundleShortVersionString (set from plugin.json at build time); fall back to the newest
// plugin-cache plugin.json for un-bundled runs (e.g. `cdt-menubar --once` straight from .build).
// Returns nil if neither is found (the caller then omits the version line).
func cdtVersion() -> String? {
    if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
       !v.isEmpty, v != "__VERSION__" {
        return v
    }
    let cache = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/plugins/cache/claude-dev-team/cdt", isDirectory: true)
    guard let dirs = try? FileManager.default.contentsOfDirectory(
        at: cache, includingPropertiesForKeys: nil) else { return nil }
    // Newest version directory (numeric-aware compare so 1.21.2 sorts above 1.9.0).
    let newest = dirs.max {
        $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedAscending
    }
    guard let pj = newest?.appendingPathComponent(".claude-plugin/plugin.json"),
          let data = try? Data(contentsOf: pj),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let v = obj["version"] as? String else { return nil }
    return v
}
