import AppKit

final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    var onRefresh: (() -> Void)?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.button?.title = "CDT …"
    }

    private func color(for pct: Int) -> NSColor {
        if pct >= 90 { return .systemRed }
        if pct >= 80 { return .systemOrange }
        return .labelColor
    }

    // Renders "CDT" (left, centered) + two stacked lines (session % over weekly %) into a narrow image.
    private func stackedImage(brand: String, top: String, topColor: NSColor,
                              bottom: String, bottomColor: NSColor) -> NSImage {
        let numFont = NSFont.systemFont(ofSize: 9, weight: .semibold)
        let brandStr = NSAttributedString(string: brand, attributes: [
            .font: NSFont.boldSystemFont(ofSize: 9), .foregroundColor: NSColor.secondaryLabelColor])
        let topStr = NSAttributedString(string: top, attributes: [.font: numFont, .foregroundColor: topColor])
        let botStr = NSAttributedString(string: bottom, attributes: [.font: numFont, .foregroundColor: bottomColor])
        let h = NSStatusBar.system.thickness                       // menu bar height (~22pt)
        let gap: CGFloat = 3
        let numW = ceil(max(topStr.size().width, botStr.size().width))
        let brandW = ceil(brandStr.size().width)
        let w = brandW + gap + numW + 2
        let image = NSImage(size: NSSize(width: w, height: h))
        image.lockFocus()
        brandStr.draw(at: NSPoint(x: 0, y: (h - brandStr.size().height) / 2))   // CDT, vertically centered
        topStr.draw(at: NSPoint(x: brandW + gap, y: h / 2))                     // session % (upper)
        botStr.draw(at: NSPoint(x: brandW + gap, y: 0))                         // weekly % (lower)
        image.unlockFocus()
        image.isTemplate = false   // colored, not a template image
        return image
    }

    func render(_ snap: UsageSnapshot) {
        // --- compact menu bar item: two STACKED lines — session % on top, weekly % on bottom — so the
        //     item is only as wide as "48%" and survives a crowded / notched menu bar. Labels in dropdown.
        if let sub = snap.subscription {
            statusItem.button?.title = ""
            statusItem.button?.image = stackedImage(
                brand: "CDT",
                top: "\(sub.sessionPct)%", topColor: color(for: sub.sessionPct),
                bottom: "\(sub.weeklyPct)%", bottomColor: color(for: sub.weeklyPct))
        } else {
            // No subscription data → a small single line with today's tokens.
            statusItem.button?.image = nil
            statusItem.button?.attributedTitle = NSAttributedString(
                string: "CDT \(formatTokens(snap.local.todayTotal))",
                attributes: [.foregroundColor: NSColor.labelColor, .font: NSFont.systemFont(ofSize: 11)])
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

        // Dev-team config + activity (the mode line always shows; activity lines when present)
        menu.addItem(.separator())
        header("claude-dev-team")
        line("  \("mode".padding(toLength: 16, withPad: " ", startingAt: 0)) \(readCDTConfig())")
        if snap.team.sessions > 0 {
            line("  \("sessions (7d)".padding(toLength: 16, withPad: " ", startingAt: 0)) \(snap.team.sessions)")
        }
        if !snap.team.tasksByTier.isEmpty {
            line("  tasks: " + snap.team.tasksByTier.map { "\($0.tier)×\($0.count)" }.joined(separator: " "))
        }
        // Subagent dispatches (specialists) — rare by design; only when the orchestrator delegates.
        for run in snap.team.agentRuns.prefix(6) {
            line("  \(run.role.padding(toLength: 18, withPad: " ", startingAt: 0)) ×\(run.count)")
        }

        menu.addItem(.separator())
        let updated = DateFormatter()
        updated.dateFormat = "h:mm:ss a"   // 12-hour, e.g. 1:50:23 PM
        updated.amSymbol = "AM"
        updated.pmSymbol = "PM"
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
