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
    private let subKeychainRetry: TimeInterval = 20   // transient Keychain blip: retry fast + quietly
    private let kcVisibleAfter = 6                     // only surface a Keychain note after ~2m of failures
    private let subBackoff: TimeInterval = 300        // after HTTP 429 with no Retry-After (server typically sends 300)
    private let subBackoffMin: TimeInterval = 60      // floor on a 429 back-off (don't retry faster than this)
    private let subBackoffMax: TimeInterval = 1800    // ceiling on a 429 back-off (cap a huge Retry-After)
    private let subMinInterval: TimeInterval = 20     // don't re-hit the endpoint if the reading is this fresh
    private let inFlightMax: TimeInterval = 30        // a fetch overdue past this is treated as lost
    private var subFailures = 0                       // consecutive non-429 failures → escalating backoff
    private var kcFailures = 0                         // consecutive transient Keychain failures (for the note)

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

    // App self-update check (notify-only). Owned here so its result renders into the same menu snapshot.
    private let updateChecker = UpdateChecker(currentVersion: cdtVersion() ?? "0.0.0")

    init(controller: MenuBarController) {
        self.controller = controller
        controller.onRefresh = { [weak self] in self?.refreshNow() }
        controller.onCheckUpdate = { [weak self] in self?.updateChecker.checkNow(force: true) }
        controller.onToggleAutoCheck = { [weak self] in
            guard let self = self else { return }
            self.updateChecker.autoCheckEnabled.toggle()
            self.applyUpdateState()
        }
    }

    /// Mirror the update checker's state into the snapshot + re-render (called after every check / toggle).
    private func applyUpdateState() {
        snapshot.update = updateChecker.available
        snapshot.updateLastChecked = updateChecker.lastChecked
        snapshot.updateAutoCheck = updateChecker.autoCheckEnabled
        controller.render(snapshot)
    }

    func start() {
        snapshot.updateAutoCheck = updateChecker.autoCheckEnabled
        updateChecker.onResult = { [weak self] in self?.applyUpdateState() }
        updateChecker.start()
        reseedFromCache()   // show the last-known % immediately, grayed, so first paint is never blank
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
    ///
    /// Also called after an AccountSwap switch (via onRefresh) to update the badge for the now-active
    /// account. Note: macOS Keychain cache is ~30s after a switch, so the subscription % may lag briefly
    /// before reflecting the new account. The badge grays (stale) during the lag and clears automatically
    /// when the next live fetch lands with the correct token.
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
                    self.kcFailures = 0
                    self.rateLimitedUntil = .distantPast            // recovered — clear any 429 cooldown
                    self.nextSubFetch = Date().addingTimeInterval(self.subNormal)
                    self.subInFlight = false
                }
            } catch {
                // Map the failure to the right recovery cadence + decide whether to show a note. The guiding
                // rule: a TRANSIENT blip must never flash a scary error — fall back to the status-line cache
                // (kept live without the Keychain) and show "cached · refreshing…". Only persistent or
                // actionable failures get a message.
                //   429        → honor Retry-After (respect the rate limit), show a countdown
                //   401 / 403  → token expired/denied: retry fast + show the actionable message
                //   keychain transient → retry fast + quiet; surface a note only after ~2m of failures
                //   keychain logged-out → "Claude Code not logged in"
                //   network/decode → soften the first couple, then show the message
                let status = (error as? UsageError)?.httpStatus
                let retryHint = (error as? UsageError)?.retryAfter
                let kc = error as? KeychainError
                await MainActor.run {
                    let delay: TimeInterval
                    var retryAt: Date? = nil
                    var visibleError: String? = nil
                    switch status {
                    case 429:
                        let hint = retryHint ?? self.subBackoff
                        delay = min(self.subBackoffMax, max(self.subBackoffMin, hint))
                        self.rateLimitedUntil = Date().addingTimeInterval(delay)
                        retryAt = self.rateLimitedUntil
                        visibleError = error.localizedDescription
                        self.subFailures = 0; self.kcFailures = 0
                    case 401, 403:
                        delay = self.subAuthRetry
                        visibleError = error.localizedDescription
                        self.subFailures = 0; self.kcFailures = 0
                    default:
                        if kc?.isTransient == true {
                            // Momentary Keychain unavailability (just after Claude Code rewrote the item).
                            // Retry fast and stay quiet; only note it if it persists for a couple of minutes.
                            self.kcFailures += 1
                            delay = self.subKeychainRetry
                            visibleError = self.kcFailures >= self.kcVisibleAfter
                                ? "Keychain busy — relaunch CDT Usage if this persists" : nil
                            self.subFailures = 0
                        } else if kc?.isLoggedOut == true {
                            delay = self.subError
                            visibleError = "Claude Code not logged in — open it to sign in"
                            self.kcFailures = 0
                        } else {
                            self.subFailures += 1
                            delay = min(self.subNormal, self.subError * pow(2, Double(self.subFailures - 1)))
                            visibleError = self.subFailures >= 3 ? error.localizedDescription : nil
                            self.kcFailures = 0
                        }
                    }
                    // Keep the badge current from the status-line cache during any outage (no Keychain needed).
                    self.reseedFromCache(force: true)
                    self.applySubscription(nil, error: visibleError, retryAt: retryAt)
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

    /// Refresh the displayed % from the on-disk cache (`~/.claude/.cdt-usage.json`), which the status line
    /// keeps live WITHOUT the Keychain. At launch (no reading yet) this avoids a blank first paint; with
    /// `force` (our own fetch just failed — e.g. a transient Keychain blip) it keeps the badge current
    /// during the outage instead of showing an error. The reading is marked `seeded` (grayed) and is
    /// replaced the instant a live fetch lands. Preserves the last-good plan label / Sonnet % if present.
    private func reseedFromCache(force: Bool = false) {
        guard force || snapshot.subscription == nil else { return }
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.cdt-usage.json")
        guard let data = try? Data(contentsOf: url), let c = parseUsageCache(data) else { return }
        snapshot.subscription = SubscriptionUsage(
            sessionPct: c.session, weeklyPct: c.weekly,
            sonnetPct: snapshot.subscription?.sonnetPct,
            sessionResetIn: nil, weeklyResetIn: nil,
            planLabel: snapshot.subscription?.planLabel)
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
