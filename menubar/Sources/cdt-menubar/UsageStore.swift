import AppKit

/// Coordinates the two data sources at independent cadences:
///  - local token usage (#2): cheap, no rate limit → refresh every 60s
///  - subscription % (#1): the undocumented endpoint rate-limits → poll gently (5 min) and back off on 429
final class UsageStore {
    private let controller: MenuBarController
    private var snapshot = UsageSnapshot()

    private var localTimer: Timer?
    private var subTimer: Timer?

    private let localInterval: TimeInterval = 60     // 1 min (local files)
    private let subNormal: TimeInterval = 300        // 5 min (endpoint, healthy)
    private let subError: TimeInterval = 60          // base retry after a failure (e.g. expired token) — recover fast
    private let subBackoff: TimeInterval = 900       // 15 min after HTTP 429 (respect rate limits)
    private var subFailures = 0                      // consecutive non-429 failures → escalating backoff

    init(controller: MenuBarController) {
        self.controller = controller
        controller.onRefresh = { [weak self] in self?.refreshNow() }
    }

    func start() {
        refreshLocal()
        fetchSubscription()
        // Add in .common mode so it also fires while a menu/tracking run-loop mode is active. (App Nap is
        // disabled app-wide via LSAppNapIsDisabled in Info.plist so background timers aren't suspended.)
        let lt = Timer(timeInterval: localInterval, repeats: true) { [weak self] _ in self?.refreshLocal() }
        RunLoop.main.add(lt, forMode: .common)
        localTimer = lt
    }

    /// Manual "Refresh now" — refresh local immediately and retry the subscription now.
    func refreshNow() {
        refreshLocal()
        subTimer?.invalidate()
        fetchSubscription()
    }

    private func refreshLocal() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let local = readLocalUsage()
            let team = readTeamActivity()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.snapshot.local = local
                self.snapshot.team = team
                self.snapshot.lastUpdated = Date()
                self.controller.render(self.snapshot)
            }
        }
    }

    private func fetchSubscription() {
        Task { [weak self] in
            guard let self = self else { return }   // don't keep the store alive via the in-flight task
            let nextDelay: TimeInterval
            do {
                let sub = try await fetchSubscriptionUsage()
                await MainActor.run { self.applySubscription(sub, error: nil); self.subFailures = 0 }
                nextDelay = self.subNormal
            } catch let e as NSError {
                // 429 → back off 15m. 401 (expired) / 403 (forbidden) → a clear, actionable note. Other
                // errors (network/decode/keychain) → that error's message.
                let msg: String
                switch e.code {
                case 429: msg = "rate limited — retrying in 15m"
                case 401: msg = "token expired — open Claude Code or re-login to refresh"
                case 403: msg = "access denied — re-login may be needed"
                default:  msg = e.localizedDescription
                }
                // Recover fast on the first failure (token likely just refreshed elsewhere), but escalate
                // 60→120→240→…(capped at 5m) so a persistently-bad token never hammers the endpoint.
                let is429 = (e.code == 429)
                nextDelay = await MainActor.run { () -> TimeInterval in
                    self.applySubscription(nil, error: msg)
                    if is429 { return self.subBackoff }
                    self.subFailures += 1
                    return min(self.subNormal, self.subError * pow(2, Double(self.subFailures - 1)))
                }
            }
            await MainActor.run { self.scheduleSubscription(after: nextDelay) }
        }
    }

    private func scheduleSubscription(after delay: TimeInterval) {
        subTimer?.invalidate()
        // .common mode so the next poll fires even if the menu is open (event-tracking run-loop mode).
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in self?.fetchSubscription() }
        RunLoop.main.add(t, forMode: .common)
        subTimer = t
    }

    private func applySubscription(_ sub: SubscriptionUsage?, error: String?) {
        // Keep the last good subscription reading visible if a refresh fails (don't blank it out on error).
        if let sub = sub {
            snapshot.subscription = sub
            snapshot.subscriptionError = nil
            snapshot.subscriptionAsOf = Date()                                // last good fetch (for the stale note)
            writeUsageCache(session: sub.sessionPct, weekly: sub.weeklyPct)   // keep Eco mode's data fresh
        } else {
            snapshot.subscriptionError = error                               // keep last-good `subscription`; mark stale
        }
        snapshot.lastUpdated = Date()
        controller.render(snapshot)
    }

    /// Persist the latest usage % to ~/.claude/.cdt-usage.json so `cdt-budget` / Eco mode work on macOS
    /// without needing the status line enabled (the status line writes the same file cross-platform).
    private func writeUsageCache(session: Int, weekly: Int) {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.cdt-usage.json")
        let json = "{\"session\":\(session),\"weekly\":\(weekly),\"ts\":\(Int(Date().timeIntervalSince1970))}"
        try? json.data(using: .utf8)?.write(to: url)
    }
}
