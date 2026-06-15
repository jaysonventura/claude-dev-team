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
    private let subNormal: TimeInterval = 300        // 5 min (endpoint)
    private let subBackoff: TimeInterval = 900       // 15 min after HTTP 429

    init(controller: MenuBarController) {
        self.controller = controller
        controller.onRefresh = { [weak self] in self?.refreshNow() }
    }

    func start() {
        refreshLocal()
        fetchSubscription()
        localTimer = Timer.scheduledTimer(withTimeInterval: localInterval, repeats: true) { [weak self] _ in
            self?.refreshLocal()
        }
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
        Task {
            var nextDelay = subNormal
            do {
                let sub = try await fetchSubscriptionUsage()
                await MainActor.run { self.applySubscription(sub, error: nil) }
            } catch let e as NSError {
                if e.code == 429 {
                    nextDelay = subBackoff   // endpoint rate-limited us — wait 15 min
                    await MainActor.run { self.applySubscription(nil, error: "rate limited — retrying in 15m") }
                } else {
                    await MainActor.run { self.applySubscription(nil, error: e.localizedDescription) }
                }
            }
            await MainActor.run { self.scheduleSubscription(after: nextDelay) }
        }
    }

    private func scheduleSubscription(after delay: TimeInterval) {
        subTimer?.invalidate()
        subTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.fetchSubscription()
        }
    }

    private func applySubscription(_ sub: SubscriptionUsage?, error: String?) {
        // Keep the last good subscription reading visible if a refresh fails (don't blank it out on error).
        if let sub = sub {
            snapshot.subscription = sub
            snapshot.subscriptionError = nil
        } else {
            snapshot.subscriptionError = error
        }
        snapshot.lastUpdated = Date()
        controller.render(snapshot)
    }
}
