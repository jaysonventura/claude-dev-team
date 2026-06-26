import Foundation

/// One-shot, no-GUI readout for `cdt-menubar status` (`--once`). A pure reader of the CLI status line's
/// shared cache (`~/.claude/.cdt-usage.json`) — no network, no Keychain, no rate limit. The session/weekly
/// %s come from whatever the status line last wrote (Claude Code's native rate_limits); local token usage is
/// summed from the project JSONL files.
func runOnce() {
    var snap = UsageSnapshot()
    snap.local = readLocalUsage()
    snap.team = readTeamActivity()

    if let c = readUsageCache() {
        snap.usage = UsageReading(sessionPct: c.session, weeklyPct: c.weekly)
        snap.usageAsOf = c.ts.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        snap.usageStale = usageReadingIsStale(ts: c.ts)
    }

    print("claude-dev-team — usage" + (cdtVersion().map { " · v\($0)" } ?? ""))
    if let u = snap.usage {
        // A stale reading is stamped with when it was last current so it's never mistaken for live.
        let asOf = (snap.usageStale ? snap.usageAsOf : nil).map { "  (as of \(clockTime($0)))" } ?? ""
        print("  Usage: Session \(u.sessionPct)% · Weekly \(u.weeklyPct)%\(asOf)")
    } else {
        print("  Usage: none yet — enable the CDT status line (cdt-config statusline on)")
    }

    if snap.local.today.isEmpty {
        print("  Tokens today: none yet")
    } else {
        let byModel = snap.local.today
            .sorted { $0.value.total > $1.value.total }
            .map { "\(shortModelName($0.key)) \(formatTokens($0.value.total))" }
            .joined(separator: ", ")
        print("  Tokens today: \(byModel)  (total \(formatTokens(snap.local.todayTotal)) · week \(formatTokens(snap.local.weekTotal)))")
    }

    if snap.team.sessions > 0 || !snap.team.tasksByTier.isEmpty || !snap.team.agentRuns.isEmpty {
        let tiers = snap.team.tasksByTier.map { "\($0.tier)×\($0.count)" }.joined(separator: " ")
        let agents = snap.team.agentRuns.prefix(5).map { "\($0.role)×\($0.count)" }.joined(separator: " ")
        print("  Team (7d): sessions \(snap.team.sessions) · tasks \(tiers.isEmpty ? "-" : tiers) · agents \(agents.isEmpty ? "-" : agents)")
    }
}
