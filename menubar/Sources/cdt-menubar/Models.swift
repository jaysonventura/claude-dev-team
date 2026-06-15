import Foundation

// Real subscription usage from /api/oauth/usage (nil if the endpoint/login is unavailable).
struct SubscriptionUsage {
    let sessionPct: Int          // five_hour utilization (0-100)
    let weeklyPct: Int           // seven_day
    let sonnetPct: Int?          // seven_day_sonnet
    let sessionResetIn: String?  // formatted countdown, e.g. "33m"
    let weeklyResetIn: String?
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
    var local = LocalUsage()
    var team = TeamActivity()
    var lastUpdated = Date()
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

// Short display name for a model id (e.g. "claude-opus-4-7" -> "Opus").
func shortModelName(_ id: String) -> String {
    let s = id.lowercased()
    if s.contains("opus") { return "Opus" }
    if s.contains("sonnet") { return "Sonnet" }
    if s.contains("haiku") { return "Haiku" }
    if s.contains("fable") { return "Fable" }
    return id
}
