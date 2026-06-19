import AppKit

/// Parses the persisted usage cache (`~/.claude/.cdt-usage.json`) into the displayable %s. Returns nil when
/// the file lacks both `session` and `weekly`. Tolerates the extra sibling fields other writers merge in
/// (context size, session age, subagent count). PURE (takes Data) so it is unit-tested.
func parseUsageCache(_ data: Data) -> (session: Int, weekly: Int, ts: Int?)? {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let session = obj["session"] as? Int, let weekly = obj["weekly"] as? Int else { return nil }
    return (session, weekly, obj["ts"] as? Int)
}

/// Coordinates the two data sources at independent cadences:
///  - local token usage (#2): cheap, no rate limit → refresh every 60s
///  - subscription % (#1): the undocumented endpoint rate-limits → poll gently (5 min) and back off on 429
///
/// Both run off **repeating** timers added in `.common` run-loop mode, so a single hung/failed fetch can
/// never break the poll chain (the bug that froze the subscription % for hours after one transient 429).
/// Recovery is also actively accelerated: an expired token (401/403) retries quickly AND the moment Claude
/// Code rotates the Keychain token we refetch, and we refresh immediately on wake-from-sleep.
final class UsageStore {
    private let controller: MenuBarController
    private var snapshot = UsageSnapshot()

    private var localTimer: Timer?
    private var heartbeat: Timer?

    private let localInterval: TimeInterval = 60     // 1 min (local files)
    private let heartbeatInterval: TimeInterval = 20 // how often we re-evaluate whether to poll the endpoint
    private let subNormal: TimeInterval = 300        // 5 min (endpoint, healthy)
    private let subError: TimeInterval = 60          // base retry after a non-429 failure — recover fast
    private let subAuthRetry: TimeInterval = 45      // 401/403: retry fast — Claude Code refreshes in ~60s
    private let subBackoff: TimeInterval = 300        // after HTTP 429 with no Retry-After (server typically sends 300)
    private let subBackoffMin: TimeInterval = 60      // floor on a 429 back-off (don't retry faster than this)
    private let subBackoffMax: TimeInterval = 1800    // ceiling on a 429 back-off (cap a huge Retry-After)
    private let subMinInterval: TimeInterval = 20     // don't re-hit the endpoint if the reading is this fresh
    private let inFlightMax: TimeInterval = 30        // a fetch overdue past this is treated as lost
    private var subFailures = 0                       // consecutive non-429 failures → escalating backoff

    // While we're inside a 429 cooldown nothing may hit the endpoint — not the heartbeat, not "Refresh now",
    // not a wake event, not token-rotation. This is what stops the menu bar from worsening a rate limit.
    private var rateLimitedUntil = Date.distantPast

    // Resilient subscription scheduling: the repeating heartbeat drives fetches; these track when the next
    // one is allowed and whether one is in flight — so backoff is honored without a fragile re-arm chain.
    private var subInFlight = false
    private var subStartedAt = Date.distantPast
    private var nextSubFetch = Date.distantPast

    // Fingerprint of the access token used for the last fetch attempt. When this changes (Claude Code
    // rotated the token) while we're in an error state, we refetch immediately instead of waiting out the
    // backoff — so an "expired token" clears within seconds of Claude Code refreshing it.
    private var lastTokenFingerprint: String?

    init(controller: MenuBarController) {
        self.controller = controller
        controller.onRefresh = { [weak self] in self?.refreshNow() }
    }

    func start() {
        seedFromCache()   // show the last-known % immediately, grayed, so first paint is never blank
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

        // Timers don't fire while the machine is asleep — refresh the instant it wakes so the menu bar is
        // never showing a reading from hours ago after the lid was closed overnight.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshNow() }

        subTick()
    }

    /// Manual "Refresh now" — refresh local immediately and force a subscription refetch, EXCEPT when doing
    /// so would hammer the rate-limited endpoint: an active 429 cooldown is always respected, and a healthy
    /// reading newer than `subMinInterval` is reused rather than re-fetched (clicking Refresh repeatedly, or
    /// a flurry of wake events, can't trip a 429). Local token usage is unlimited, so it always refreshes.
    func refreshNow() {
        refreshLocal()
        let now = Date()
        if now < rateLimitedUntil { return }                        // honor the server's rate-limit window
        if snapshot.subscriptionError == nil, let asOf = snapshot.subscriptionAsOf,
           now.timeIntervalSince(asOf) < subMinInterval { return }  // reading is fresh — don't re-hit endpoint
        nextSubFetch = .distantPast
        if subInFlight && now.timeIntervalSince(subStartedAt) > inFlightMax { subInFlight = false }
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
        // Never poll inside a 429 cooldown — wait the server's window out (this is the rate-limit guard).
        if Date() < rateLimitedUntil { return }
        // If we're in an error/stale state and Claude Code has since rotated the token, recover at once.
        // (Skipped during a 429 cooldown above — a new token doesn't lift a rate limit.)
        if snapshot.subscriptionError != nil, let last = lastTokenFingerprint,
           let now = claudeTokenFingerprint(), now != last {
            nextSubFetch = .distantPast
        }
        if Date() < nextSubFetch { return }
        fetchSubscription()
    }

    private func fetchSubscription() {
        subInFlight = true
        subStartedAt = Date()
        lastTokenFingerprint = claudeTokenFingerprint()   // the token this attempt uses (for rotation detection)
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let sub = try await fetchSubscriptionUsage()
                await MainActor.run {
                    self.applySubscription(sub, error: nil)
                    self.subFailures = 0
                    self.rateLimitedUntil = .distantPast            // recovered — clear any 429 cooldown
                    self.nextSubFetch = Date().addingTimeInterval(self.subNormal)
                    self.subInFlight = false
                }
            } catch {
                // Map the failure to a clean message + the right recovery cadence:
                //   429        → honor Retry-After (respect the rate limit), show a countdown
                //   401 / 403  → token expired/denied: retry fast (Claude Code refreshes in ~60s)
                //   other      → network/decode/keychain: that error's message, escalating retry
                let status = (error as? UsageError)?.httpStatus
                let retryHint = (error as? UsageError)?.retryAfter
                let msg = error.localizedDescription
                await MainActor.run {
                    let delay: TimeInterval
                    var retryAt: Date? = nil
                    switch status {
                    case 429:
                        // Wait exactly as long as the server asks (Retry-After), clamped to a sane window;
                        // fall back to the gentle fixed back-off when it gives no hint. Mark the cooldown so
                        // nothing re-hits the endpoint until it elapses, and surface a countdown to the user.
                        let hint = retryHint ?? self.subBackoff
                        delay = min(self.subBackoffMax, max(self.subBackoffMin, hint))
                        self.rateLimitedUntil = Date().addingTimeInterval(delay)
                        retryAt = self.rateLimitedUntil
                    case 401, 403:
                        delay = self.subAuthRetry            // fast, fixed — don't escalate auth recovery
                    default:
                        self.subFailures += 1
                        delay = min(self.subNormal, self.subError * pow(2, Double(self.subFailures - 1)))
                    }
                    self.applySubscription(nil, error: msg, retryAt: retryAt)
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

    private func applySubscription(_ sub: SubscriptionUsage?, error: String?, retryAt: Date? = nil) {
        // Keep the last good subscription reading visible if a refresh fails (don't blank it out on error).
        if let sub = sub {
            snapshot.subscription = sub
            snapshot.subscriptionError = nil
            snapshot.subscriptionSeeded = false                               // a live reading supersedes the cache seed
            snapshot.subscriptionRetryAt = nil
            snapshot.subscriptionAsOf = Date()                                // last good fetch (for the stale note)
            writeUsageCache(session: sub.sessionPct, weekly: sub.weeklyPct)   // keep Eco mode's data fresh
        } else {
            snapshot.subscriptionError = error                               // keep last-good `subscription`; mark stale
            snapshot.subscriptionRetryAt = retryAt                           // rate-limit countdown (nil otherwise)
        }
        snapshot.lastUpdated = Date()
        controller.render(snapshot)
    }

    /// Seed the displayed subscription % from the on-disk cache (~/.claude/.cdt-usage.json) at launch, so the
    /// menu bar shows the last-known reading (grayed) immediately instead of a blank "unavailable" while the
    /// first live fetch is in flight — and keeps showing it if that first fetch is rate-limited. The reading
    /// is marked `seeded` (stale) and is replaced the instant a live fetch lands.
    private func seedFromCache() {
        guard snapshot.subscription == nil else { return }
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.cdt-usage.json")
        guard let data = try? Data(contentsOf: url), let c = parseUsageCache(data) else { return }
        snapshot.subscription = SubscriptionUsage(
            sessionPct: c.session, weeklyPct: c.weekly, sonnetPct: nil,
            sessionResetIn: nil, weeklyResetIn: nil, planLabel: nil)
        snapshot.subscriptionSeeded = true
        if let ts = c.ts { snapshot.subscriptionAsOf = Date(timeIntervalSince1970: TimeInterval(ts)) }
        controller.render(snapshot)
    }

    /// Persist the latest usage % to ~/.claude/.cdt-usage.json so `cdt-budget` / Eco mode work on macOS
    /// without needing the status line enabled (the status line writes the same file cross-platform).
    /// Merge-writes (preserves sibling fields like context size that other writers own).
    private func writeUsageCache(session: Int, weekly: Int) {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.cdt-usage.json")
        var obj = (try? Data(contentsOf: url)).flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        } ?? [:]
        obj["session"] = session
        obj["weekly"] = weekly
        obj["ts"] = Int(Date().timeIntervalSince1970)
        if let data = try? JSONSerialization.data(withJSONObject: obj) {
            try? data.write(to: url)
        }
    }
}
