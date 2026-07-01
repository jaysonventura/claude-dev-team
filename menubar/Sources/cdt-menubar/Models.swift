import Foundation

// Account usage %s, read from the CLI status line's shared cache (`~/.claude/.cdt-usage.json`). The status
// line gets these straight from Claude Code's native `rate_limits` payload — no OAuth endpoint, no Keychain,
// no rate limit. The menu bar is a pure reader of that cache.
struct UsageReading {
    let sessionPct: Int   // five_hour used % (0-100)
    let weeklyPct: Int    // seven_day used %
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
    var usage: UsageReading?               // last reading from the CLI status-line cache (nil = none written yet)
    var usageAsOf: Date?                   // the cache `ts` — for the "as of" label + staleness check
    var usageStale = false                 // reading is older than `usageFreshWindow` → grayed, never live-looking

    // Opt-in realtime usage refresh (network). All default OFF; populated by UsageStore only when enabled.
    var realtimeEnabled = false            // CDT_REALTIME_USAGE — drives the dropdown toggle + status lines
    var usageRetryAt: Date?                // 429 cooldown end (future) → "live refresh paused — retry in Nm"
    var usageFetchError: String?           // subtle one-line reason (e.g. token expired) — never alarmist

    var local = LocalUsage()
    var team = TeamActivity()
    var lastUpdated = Date()

    // App self-update check (notify-only): a newer release if one exists, the last-checked time, and the
    // auto-check toggle state. Populated by UpdateChecker; rendered as the "Updates" section.
    var update: ReleaseInfo?
    var updateLastChecked: Date?
    var updateAutoCheck = true
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
