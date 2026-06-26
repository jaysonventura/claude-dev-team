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

    /// Read the account usage %s from the status-line cache and re-render. Marks the reading stale (grayed)
    /// when it's older than `usageFreshWindow`; clears `usage` to nil when nothing has been written yet (the
    /// dropdown then prompts the user to enable the CDT status line).
    private func refreshUsage() {
        if let c = readUsageCache() {
            snapshot.usage = UsageReading(sessionPct: c.session, weeklyPct: c.weekly)
            snapshot.usageAsOf = c.ts.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            snapshot.usageStale = usageReadingIsStale(ts: c.ts)
        } else {
            snapshot.usage = nil
            snapshot.usageAsOf = nil
            snapshot.usageStale = false
        }
        snapshot.lastUpdated = Date()
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
