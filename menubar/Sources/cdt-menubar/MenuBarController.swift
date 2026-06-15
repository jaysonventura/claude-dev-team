import AppKit

final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    var onRefresh: (() -> Void)?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.button?.title = "CDT …"
    }

    private func color(forWorst pct: Int) -> NSColor {
        if pct >= 90 { return .systemRed }
        if pct >= 80 { return .systemOrange }
        return .labelColor
    }

    func render(_ snap: UsageSnapshot) {
        // --- compact menu bar title ---
        if let sub = snap.subscription {
            let worst = max(sub.sessionPct, sub.weeklyPct)
            let title = "▓ \(worst)%"
            statusItem.button?.attributedTitle = NSAttributedString(
                string: title, attributes: [.foregroundColor: color(forWorst: worst)])
        } else {
            statusItem.button?.attributedTitle = NSAttributedString(
                string: "⏱ \(formatTokens(snap.local.todayTotal))",
                attributes: [.foregroundColor: NSColor.labelColor])
        }

        // --- dropdown menu ---
        let menu = NSMenu()
        func header(_ t: String) {
            let i = NSMenuItem(title: t, action: nil, keyEquivalent: "")
            i.isEnabled = false
            menu.addItem(i)
        }
        func line(_ t: String) {
            let i = NSMenuItem(title: t, action: nil, keyEquivalent: "")
            i.isEnabled = false
            i.attributedTitle = NSAttributedString(
                string: t, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)])
            menu.addItem(i)
        }

        // Subscription section
        header("Subscription (Claude Max)")
        if let sub = snap.subscription {
            line("  Session  \(textBar(sub.sessionPct)) \(sub.sessionPct)%" +
                 (sub.sessionResetIn.map { "  resets \($0)" } ?? ""))
            line("  Weekly   \(textBar(sub.weeklyPct)) \(sub.weeklyPct)%" +
                 (sub.weeklyResetIn.map { "  resets \($0)" } ?? ""))
            if let s = sub.sonnetPct {
                line("  Sonnet   \(textBar(s)) \(s)%")
            }
        } else {
            line("  unavailable — " + (snap.subscriptionError ?? "endpoint/login"))
        }

        menu.addItem(.separator())

        // Local token usage (accurate)
        header("Tokens — today (local)")
        if snap.local.today.isEmpty {
            line("  none yet today")
        } else {
            for (model, mt) in snap.local.today.sorted(by: { $0.value.total > $1.value.total }) {
                line("  \(shortModelName(model).padding(toLength: 7, withPad: " ", startingAt: 0)) " +
                     "\(formatTokens(mt.total))  (cache \(formatTokens(mt.cacheRead)))")
            }
            line("  total    \(formatTokens(snap.local.todayTotal))   · week \(formatTokens(snap.local.weekTotal))")
        }

        // Dev-team activity
        if !snap.team.agentRuns.isEmpty || !snap.team.tasksByTier.isEmpty {
            menu.addItem(.separator())
            header("claude-dev-team (7d)")
            if !snap.team.tasksByTier.isEmpty {
                line("  tasks: " + snap.team.tasksByTier.map { "\($0.tier)×\($0.count)" }.joined(separator: " "))
            }
            for run in snap.team.agentRuns.prefix(6) {
                line("  \(run.role.padding(toLength: 18, withPad: " ", startingAt: 0)) ×\(run.count)")
            }
        }

        menu.addItem(.separator())
        let updated = DateFormatter()
        updated.dateFormat = "HH:mm:ss"
        line("updated \(updated.string(from: snap.lastUpdated))")

        let refresh = NSMenuItem(title: "Refresh now", action: #selector(refreshClicked), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let quit = NSMenuItem(title: "Quit", action: #selector(quitClicked), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func refreshClicked() { onRefresh?() }
    @objc private func quitClicked() { NSApp.terminate(nil) }
}
