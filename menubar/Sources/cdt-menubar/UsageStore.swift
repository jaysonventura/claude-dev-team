import AppKit

/// Coordinates fetching (subscription async + local on a background queue) and renders into the menu bar.
final class UsageStore {
    private let controller: MenuBarController
    private var snapshot = UsageSnapshot()
    private var timer: Timer?
    private let interval: TimeInterval = 60   // refresh every 60s

    init(controller: MenuBarController) {
        self.controller = controller
        controller.onRefresh = { [weak self] in self?.refresh() }
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        // #2 local (accurate) — off the main thread, then render.
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

        // #1 subscription (real) — async; fail-soft.
        Task {
            do {
                let sub = try await fetchSubscriptionUsage()
                await MainActor.run { self.applySubscription(sub, error: nil) }
            } catch {
                let message = error.localizedDescription
                await MainActor.run { self.applySubscription(nil, error: message) }
            }
        }
    }

    private func applySubscription(_ sub: SubscriptionUsage?, error: String?) {
        snapshot.subscription = sub
        snapshot.subscriptionError = error
        snapshot.lastUpdated = Date()
        controller.render(snapshot)
    }
}
