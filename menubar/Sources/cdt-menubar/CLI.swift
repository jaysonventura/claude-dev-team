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
        if snap.usageStale {
            // The status line only runs in a terminal — tell IDE-panel users where to refresh it.
            print("    refresh: run claude in a terminal (VS Code: integrated terminal)")
        }
    } else {
        print("  Usage: none yet — enable the CDT status line (cdt-config statusline on), then run claude in a terminal")
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

/// Terminal-runnable e2e of the FULL realtime path (Keychain → network → parse → atomic cache merge).
/// Honors the opt-in flag: with realtime OFF and no `--force` it does nothing and exits non-zero. On a real
/// fetch it merges `{session, weekly, ts}` into the cache and prints a one-line outcome. NEVER prints the
/// token. Returns the process exit code (0 = success, non-zero = off/failure).
func runRefreshUsage(force: Bool) -> Int32 {
    guard readCDTConfig().realtimeUsage || force else {
        print("Realtime usage: off — enable with `cdt-config realtime-usage on` (or pass --force)")
        return 1
    }

    // Honor an active server 429 back-off even under --force: --force overrides the opt-in flag, NEVER the
    // rate limit. This is what stops a scripted `--refresh-usage` loop from bursting the endpoint.
    let now = Date()
    if let until = readPersistedCooldown(), until > now {
        print("Realtime usage: rate-limited — retry after \(clockTime(until)) (server back-off)")
        return 2
    }

    // One real Keychain → network → parse round-trip via the shared blocking bridge.
    switch fetchSubscriptionUsageBlocking() {
    case .success(let reading):
        let ts = Int(Date().timeIntervalSince1970)
        writeUsageCacheMerging(session: reading.sessionPct, weekly: reading.weeklyPct, ts: ts)
        writeCooldownMerging(until: nil)   // success → clear any persisted back-off
        print("Realtime usage: Session \(reading.sessionPct)% · Weekly \(reading.weeklyPct)% (written to cache)")
        return 0
    case .failure(let error):
        // Persist a 429 back-off so the next invocation — and the app — honor the same server cooldown.
        if case UsageError.rateLimited(let retryAfter) = error {
            writeCooldownMerging(until: now.addingTimeInterval(clampedCooldownSeconds(retryAfter)))
        }
        let reason: String
        if let ue = error as? UsageError { reason = ue.errorDescription ?? "usage fetch failed" }
        else if let ke = error as? KeychainError { reason = ke.errorDescription ?? "keychain error" }
        else { reason = "network error — \(error.localizedDescription)" }
        print("Realtime usage: \(reason)")
        return 2
    }
}
