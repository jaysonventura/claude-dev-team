import Foundation

/// One-shot, no-GUI readout. Fetches subscription (real) + local usage, prints, exits.
/// Used by `cdt-menubar --once` for testing and for a quick terminal check.
func runOnce() {
    var snap = UsageSnapshot()
    snap.local = readLocalUsage()
    snap.team = readTeamActivity()

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

    print("claude-dev-team — usage")
    if let s = snap.subscription {
        var parts = ["Session \(s.sessionPct)%" + (s.sessionResetIn.map { " (resets \($0))" } ?? ""),
                     "Weekly \(s.weeklyPct)%" + (s.weeklyResetIn.map { " (resets \($0))" } ?? "")]
        if let sonnet = s.sonnetPct { parts.append("Sonnet \(sonnet)%") }
        print("  Subscription: " + parts.joined(separator: " · "))
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
