import Foundation

/// One-shot, no-GUI readout. Used by `cdt-menubar status` (`--once`) for a quick terminal check.
///
/// **Cache-first** (the default): if the menu bar (or status line) already wrote a fresh reading to the
/// shared cache, reuse it instead of hitting the rate-limited endpoint — so running `status` never adds to
/// the burst that triggers 429s. Only when the cache is missing/stale (or `forceLive`) do we fetch live, and
/// a live fetch is persisted back to the cache so the next reader (a later `status`, `cdt-budget`) gets it
/// for free. Pass `--live`/`--fresh` to force a live fetch (the only way to see the plan label, Sonnet %,
/// and reset countdowns, which the cache doesn't carry).
func runOnce(forceLive: Bool = false) {
    var snap = UsageSnapshot()
    snap.local = readLocalUsage()
    snap.team = readTeamActivity()

    var cachedAsOf: Date? = nil
    // Reuse the menu bar's poll cadence as the freshness window (one shared constant — can't drift).
    if !forceLive, let c = readUsageCache(), usageCacheFresh(ts: c.ts, maxAge: subscriptionPollInterval) {
        snap.subscription = SubscriptionUsage(
            sessionPct: c.session, weeklyPct: c.weekly, sonnetPct: nil,
            sessionResetIn: nil, weeklyResetIn: nil, planLabel: nil)
        cachedAsOf = c.ts.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    } else {
        let sem = DispatchSemaphore(value: 0)
        Task {
            do { snap.subscription = try await fetchSubscriptionUsage() }
            catch { snap.subscriptionError = error.localizedDescription }
            sem.signal()
        }
        // Never hang: the first Keychain read may require a one-time macOS approval prompt.
        if sem.wait(timeout: .now() + 15) == .timedOut {
            snap.subscriptionError = "timed out (approve Keychain access, or check network)"
        }
        // Feed the shared cache so cdt-budget / a later `status` reads it instead of re-fetching.
        if let s = snap.subscription { writeUsageCache(session: s.sessionPct, weekly: s.weeklyPct) }
    }

    print("claude-dev-team — usage" + (cdtVersion().map { " · v\($0)" } ?? ""))
    if let s = snap.subscription {
        var parts = ["Session \(s.sessionPct)%" + (s.sessionResetIn.map { " (resets \($0))" } ?? ""),
                     "Weekly \(s.weeklyPct)%" + (s.weeklyResetIn.map { " (resets \($0))" } ?? "")]
        if let sonnet = s.sonnetPct { parts.append("Sonnet \(sonnet)%") }
        let plan = s.planLabel.map { " · \($0)" } ?? ""
        // A cached reading is labeled with its age so it's never mistaken for a live one (run with --live
        // for the full reading: plan label + Sonnet % + reset countdowns).
        let asOf = cachedAsOf.map { "  (cached, as of \(clockTime($0)))" } ?? ""
        print("  Subscription\(plan): " + parts.joined(separator: " · ") + asOf)
    } else {
        print("  Subscription: unavailable — \(snap.subscriptionError ?? "endpoint/login")")
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
