import AppKit

/// Coordinates the two data sources at independent cadences:
///  - local token usage (#2): cheap, no rate limit → refresh every 60s
///  - subscription % (#1): the undocumented endpoint rate-limits → poll gently (5 min) and back off on 429
///
/// Both run off **repeating** timers added in `.common` run-loop mode, so a single hung/failed fetch can
/// never break the poll chain (the bug that froze the subscription % for hours after one transient 429).
final class UsageStore {
    private let controller: MenuBarController
    private var snapshot = UsageSnapshot()

    private var localTimer: Timer?
    private var heartbeat: Timer?

    private let localInterval: TimeInterval = 60     // 1 min (local files)
    private let heartbeatInterval: TimeInterval = 20 // how often we re-evaluate whether to poll the endpoint
    private let subNormal: TimeInterval = 300        // 5 min (endpoint, healthy)
    private let subError: TimeInterval = 60          // base retry after a non-429 failure — recover fast
    private let subBackoff: TimeInterval = 900        // 15 min after HTTP 429 (respect rate limits)
    private let inFlightMax: TimeInterval = 30        // a fetch overdue past this is treated as lost
    private var subFailures = 0                       // consecutive non-429 failures → escalating backoff

    // Resilient subscription scheduling: the repeating heartbeat drives fetches; these track when the next
    // one is allowed and whether one is in flight — so backoff is honored without a fragile re-arm chain.
    private var subInFlight = false
    private var subStartedAt = Date.distantPast
    private var nextSubFetch = Date.distantPast

    init(controller: MenuBarController) {
        self.controller = controller
        controller.onRefresh = { [weak self] in self?.refreshNow() }
    }

    func start() {
        refreshLocal()
        // Local token usage — a plain repeating timer in .common mode.
        let lt = Timer(timeInterval: localInterval, repeats: true) { [weak self] _ in self?.refreshLocal() }
        RunLoop.main.add(lt, forMode: .common)
        localTimer = lt

        // Subscription heartbeat — repeating + .common + never re-created, so polling can't die. It fetches
        // immediately on launch, then re-checks every `heartbeatInterval` and fetches when backoff elapses.
        nextSubFetch = Date()
        let hb = Timer(timeInterval: heartbeatInterval, repeats: true) { [weak self] _ in self?.subTick() }
        RunLoop.main.add(hb, forMode: .common)
        heartbeat = hb
        subTick()
    }

    /// Manual "Refresh now" — refresh local immediately and force an immediate subscription refetch.
    func refreshNow() {
        refreshLocal()
        nextSubFetch = .distantPast
        if subInFlight && Date().timeIntervalSince(subStartedAt) > inFlightMax { subInFlight = false }
        subTick()
    }

    /// Heartbeat tick: decide whether to start a subscription fetch (honoring in-flight + backoff).
    private func subTick() {
        if subInFlight {
            // Force-clear a stuck fetch — the resource timeout (25s) should make this impossible, but if a
            // fetch is ever overdue we treat it as lost rather than letting it block all future polls.
            if Date().timeIntervalSince(subStartedAt) <= inFlightMax { return }
            subInFlight = false
        }
        if Date() < nextSubFetch { return }
        fetchSubscription()
    }

    private func fetchSubscription() {
        subInFlight = true
        subStartedAt = Date()
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let sub = try await fetchSubscriptionUsage()
                await MainActor.run {
                    self.applySubscription(sub, error: nil)
                    self.subFailures = 0
                    self.nextSubFetch = Date().addingTimeInterval(self.subNormal)
                    self.subInFlight = false
                }
            } catch let e as NSError {
                // 429 → back off 15m. 401 (expired) / 403 (forbidden) → a clear, actionable note. Other
                // errors (network/decode/keychain) → that error's message, with escalating retry.
                let msg: String
                switch e.code {
                case 429: msg = "rate limited — retrying in 15m"
                case 401: msg = "token expired — open Claude Code or re-login to refresh"
                case 403: msg = "access denied — re-login may be needed"
                default:  msg = e.localizedDescription
                }
                let is429 = (e.code == 429)
                await MainActor.run {
                    self.applySubscription(nil, error: msg)
                    let delay: TimeInterval
                    if is429 {
                        delay = self.subBackoff
                    } else {
                        self.subFailures += 1
                        delay = min(self.subNormal, self.subError * pow(2, Double(self.subFailures - 1)))
                    }
                    self.nextSubFetch = Date().addingTimeInterval(delay)
                    self.subInFlight = false
                }
            }
        }
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
