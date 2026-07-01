import AppKit

/// Parses the persisted usage cache (`~/.claude/.cdt-usage.json`) into the displayable %s. Returns nil when
/// the file lacks both `session` and `weekly`. Tolerates the extra sibling fields other writers merge in
/// (context size, session age, subagent count). PURE (takes Data) so it is unit-tested.
func parseUsageCache(_ data: Data) -> (session: Int, weekly: Int, ts: Int?)? {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let session = obj["session"] as? Int, let weekly = obj["weekly"] as? Int else { return nil }
    return (session, weekly, obj["ts"] as? Int)
}

/// Coordinates the two data sources, both cheap local reads with no rate limit:
///  - usage % (session/weekly): read from the CLI status line's shared cache (`~/.claude/.cdt-usage.json`),
///    which Claude Code's native `rate_limits` payload keeps fresh. The menu bar NO LONGER fetches the
///    `/api/oauth/usage` endpoint itself — that token-shared burst was the sole cause of the 429 storms,
///    and there is no Keychain read here at all anymore.
///  - local token usage: summed from `~/.claude/projects/*/*.jsonl`.
///
/// Both run off **repeating** timers in `.common` run-loop mode, and we also re-read on wake-from-sleep so a
/// reading from hours ago can't linger after the lid was closed overnight.
final class UsageStore {
    private let controller: MenuBarController
    private var snapshot = UsageSnapshot()

    private var localTimer: Timer?
    private var usageTimer: Timer?

    private let localInterval: TimeInterval = 60   // 1 min — local token files
    private let usageInterval: TimeInterval = 30   // 30 s — re-read the (local, cheap) status-line cache

    // --- Opt-in realtime usage (network) state. Every field is inert unless CDT_REALTIME_USAGE is on; the
    //     gate short-circuits on realtime-off so none of this ever reads the Keychain or hits the network.
    private var lastCacheTs: Int?               // ts of the last cache reading (drives the staleness gate)
    private var lastRealtimeAttempt: Date?      // last fetch attempt (10-min hard floor is measured from here)
    private var cooldownUntil: Date?            // 429 back-off end — cleared ONLY by a successful fetch
    private var tokenErrorRetryAt: Date?        // 401/403 short-retry deadline (~45s); nil = not recovering
    private var lastTokenFingerprint: String?   // failing token's fp — a change means Claude Code rotated it
    private var fetchError: String?             // subtle status line for the dropdown (nil = quiet)
    private var fetchInFlight = false           // one in-flight fetch at a time

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

        // Honor a 429 back-off persisted before a restart — a relaunch mid-cooldown must not immediately re-hit.
        cooldownUntil = readPersistedCooldown()

        refreshUsage()   // first paint from the on-disk cache (never blank)
        refreshLocal()

        let ut = Timer(timeInterval: usageInterval, repeats: true) { [weak self] _ in self?.refreshUsage() }
        RunLoop.main.add(ut, forMode: .common)
        usageTimer = ut

        let lt = Timer(timeInterval: localInterval, repeats: true) { [weak self] _ in self?.refreshLocal() }
        RunLoop.main.add(lt, forMode: .common)
        localTimer = lt

        // Timers don't fire while the machine is asleep — refresh the instant it wakes.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshNow() }
    }

    /// Manual "Refresh now" / wake / account-swap: just re-read both local sources. Everything here is a
    /// cheap local read with no rate limit, so there's nothing to throttle or back off.
    func refreshNow() {
        refreshUsage()
        refreshLocal()
    }

    /// Read the account usage %s from the status-line cache and re-render (UNCHANGED pure-reader behavior).
    /// Marks the reading stale (grayed) when it's older than `usageFreshWindow`; clears `usage` to nil when
    /// nothing has been written yet. THEN, only when realtime is opted in, considers one throttled network
    /// refresh via the pure gate. When realtime is OFF this method touches neither the Keychain nor network.
    private func refreshUsage() {
        let realtimeOn = readCDTConfig().realtimeUsage
        snapshot.realtimeEnabled = realtimeOn

        if let c = readUsageCache() {
            snapshot.usage = UsageReading(sessionPct: c.session, weeklyPct: c.weekly)
            snapshot.usageAsOf = c.ts.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            snapshot.usageStale = usageReadingIsStale(ts: c.ts)
            lastCacheTs = c.ts
        } else {
            snapshot.usage = nil
            snapshot.usageAsOf = nil
            snapshot.usageStale = false
            lastCacheTs = nil
        }

        let now = Date()
        // Surface the live-refresh status (only while realtime is on): a future cooldown → "paused" line,
        // otherwise the subtle fetch-error reason. Both are calm, gray, disabled lines in the dropdown.
        snapshot.usageRetryAt = (realtimeOn && cooldownUntil.map { $0 > now } == true) ? cooldownUntil : nil
        snapshot.usageFetchError = realtimeOn ? fetchError : nil
        snapshot.lastUpdated = now
        controller.render(snapshot)

        maybeFetchRealtime(realtimeOn: realtimeOn, now: now)
    }

    /// Considers ONE throttled network fetch. Realtime OFF short-circuits FIRST — no Keychain, no request —
    /// so default users stay a pure reader. When on, the pure gate decides the normal cadence; a separate
    /// fast-recovery path handles an expired token (retry ~45s, or immediately on token rotation) without
    /// ever overriding the 429 cooldown.
    private func maybeFetchRealtime(realtimeOn: Bool, now: Date) {
        guard realtimeOn else {
            // Pure-reader mode: drop any lingering live-refresh state so nothing stale renders if toggled off.
            cooldownUntil = nil; tokenErrorRetryAt = nil; fetchError = nil
            return
        }
        guard !fetchInFlight else { return }

        let standard = shouldFetchRealtimeUsage(
            realtimeOn: true, cacheTs: lastCacheTs,
            lastAttempt: lastRealtimeAttempt, cooldownUntil: cooldownUntil, now: now)

        // Fast recovery from an expired token: retry ~45s, and the instant Claude Code rotates its token
        // (fingerprint change) refetch immediately — never wait the 10-min floor to recover. This NEVER
        // overrides a 429 cooldown (that server back-off is honored everywhere). The Keychain fingerprint
        // is read ONLY while recovering, so the healthy path never touches the Keychain on a fresh cache.
        var recovery = false
        if cooldownUntil == nil || now >= cooldownUntil!, let errAt = tokenErrorRetryAt {
            let fp = claudeTokenFingerprint()
            if (fp != nil && fp != lastTokenFingerprint) || now >= errAt { recovery = true }
        }

        guard standard || recovery else { return }

        fetchInFlight = true
        lastRealtimeAttempt = now
        // Off the main thread: Keychain read → network → parse run on a utility queue (the blocking bridge
        // owns the async work and captures no `self`), then results are applied back on main.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let outcome = fetchSubscriptionUsageBlocking()
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                switch outcome {
                case .success(let reading): self.onRealtimeSuccess(reading, at: now)
                case .failure(let error):   self.onRealtimeError(error, at: now)
                }
            }
        }
    }

    /// Live fetch succeeded: adopt the reading, clear ALL back-off/error state, and merge {session, weekly,
    /// ts} into the shared cache (preserving every sibling field). Clearing the cooldown here is the ONLY
    /// place it's cleared — never on a manual refresh (that was the old 429-storm bug).
    private func onRealtimeSuccess(_ reading: UsageReading, at now: Date) {
        fetchInFlight = false
        cooldownUntil = nil
        tokenErrorRetryAt = nil
        lastTokenFingerprint = nil
        fetchError = nil

        let ts = Int(now.timeIntervalSince1970)
        writeUsageCacheMerging(session: reading.sessionPct, weekly: reading.weeklyPct, ts: ts)
        writeCooldownMerging(until: nil)   // recovered → drop any persisted 429 back-off
        lastCacheTs = ts

        snapshot.usage = reading
        snapshot.usageAsOf = now
        snapshot.usageStale = false
        snapshot.usageRetryAt = nil
        snapshot.usageFetchError = nil
        snapshot.lastUpdated = now
        controller.render(snapshot)
    }

    /// Live fetch failed: back off appropriately and keep the last good (cached) reading. UI stays calm —
    /// a subtle one-line reason at most, never an alarm.
    private func onRealtimeError(_ error: Error, at now: Date) {
        fetchInFlight = false

        if let ue = error as? UsageError {
            switch ue {
            case .rateLimited(let retryAfter):
                // Honor the server's back-off, clamped to a sane [60s, 30m]. Cleared ONLY by success.
                // Persist it so a relaunch — and the separate --refresh-usage CLI — honor the same back-off.
                cooldownUntil = now.addingTimeInterval(clampedCooldownSeconds(retryAfter))
                writeCooldownMerging(until: cooldownUntil)
                fetchError = nil
            case .http(401), .http(403):
                // Token expired — Claude Code refreshes it in ~60s. Retry soon; a fingerprint change
                // (rotation) triggers an immediate refetch. Keep the last reading, note it subtly.
                tokenErrorRetryAt = now.addingTimeInterval(45)
                lastTokenFingerprint = claudeTokenFingerprint()
                fetchError = "token expired — Claude Code will refresh it"
            default:
                fetchError = ue.errorDescription
            }
        } else if let ke = error as? KeychainError {
            if ke.isTransient {
                // Momentary Keychain lock (ACL reset after Claude Code rewrote the item). Keep the cached
                // reading, no scary UI, and allow a next-tick retry (don't burn the 10-min floor on a blip).
                lastRealtimeAttempt = nil
                fetchError = nil
            } else if ke.isLoggedOut {
                fetchError = "not logged in to Claude Code"
            } else {
                fetchError = nil
            }
        } else {
            // Network/timeout — stay quiet and retry on the next eligible tick.
            fetchError = nil
        }

        snapshot.usageRetryAt = (cooldownUntil.map { $0 > now } == true) ? cooldownUntil : nil
        snapshot.usageFetchError = fetchError
        controller.render(snapshot)
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
}
