import AppKit

final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    var onRefresh: (() -> Void)?
    var onCheckUpdate: (() -> Void)?        // "Check Now" in the Updates submenu
    var onToggleAutoCheck: (() -> Void)?    // toggle "Auto-check on launch"
    private var lastSnap: UsageSnapshot?   // so config changes can rebuild the menu in place
    private var updateURL: String?         // release page to open for "Get vX.Y.Z"
    private lazy var versionString: String? = cdtVersion()   // installed version (constant per run)

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
        lastSnap = snap
        // --- compact menu bar item: two STACKED lines — session % on top, weekly % on bottom — so the
        //     item is only as wide as "48%" and survives a crowded / notched menu bar. Labels in dropdown.
        if let sub = snap.subscription {
            statusItem.button?.title = ""
            // When the reading is stale (last fetch failed, e.g. expired token) gray the numbers out so a
            // frozen value never masquerades as live; otherwise color-code by threshold (80/90).
            let stale = snap.subscriptionStale
            statusItem.button?.image = stackedImage(
                brand: "CDT",
                top: "\(sub.sessionPct)%", topColor: stale ? .tertiaryLabelColor : color(for: sub.sessionPct),
                bottom: "\(sub.weeklyPct)%", bottomColor: stale ? .tertiaryLabelColor : color(for: sub.weeklyPct))
        } else {
            // No subscription data yet → a small single line. While the first fetch is still in flight show
            // an ellipsis (not token counts) so the bar doesn't look "done"; afterwards show today's tokens.
            statusItem.button?.image = nil
            let title = snap.subscriptionLoading ? "CDT …" : "CDT \(formatTokens(snap.local.todayTotal))"
            statusItem.button?.attributedTitle = NSAttributedString(
                string: title,
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

        // Update banner (top, prominent) — only when a newer release was found. Click → open the release page.
        updateURL = snap.update?.url
        if let up = snap.update {
            let item = NSMenuItem(title: "⬆  Update available — get v\(up.version)",
                                  action: #selector(getUpdateClicked), keyEquivalent: "")
            item.target = self
            item.attributedTitle = NSAttributedString(string: "⬆  Update available — get v\(up.version)",
                attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                             .foregroundColor: NSColor.systemBlue])
            menu.addItem(item)
            menu.addItem(.separator())
        }

        // Subscription section
        // Plan tier (Pro/Max) comes from the Keychain credential fields, not the usage endpoint; show it
        // when present ("Subscription · Max 5x"), else a neutral "Subscription" — never a guessed tier.
        let planSuffix = snap.subscription?.planLabel.map { " · \($0)" } ?? ""
        header("Subscription\(planSuffix)" + (snap.subscriptionStale ? "  —  stale" : ""))
        if let sub = snap.subscription {
            line("  Session  \(textBar(sub.sessionPct)) \(sub.sessionPct)%" +
                 (sub.sessionResetIn.map { "  resets \($0)" } ?? ""))
            line("  Weekly   \(textBar(sub.weeklyPct)) \(sub.weeklyPct)%" +
                 (sub.weeklyResetIn.map { "  resets \($0)" } ?? ""))
            if let s = sub.sonnetPct {
                line("  Sonnet   \(textBar(s)) \(s)%")
            }
            if snap.subscriptionStale {
                // Explain WHY the reading is grayed: a rate-limit countdown, a "refreshing the cached value"
                // note on cold start, or the underlying error — so a stale value never looks broken/frozen.
                let note: String
                if let retryAt = snap.subscriptionRetryAt, retryAt > Date() {
                    note = "rate limited · retry \(formatCountdown(to: retryAt))"
                } else if snap.subscriptionSeeded && snap.subscriptionError == nil {
                    note = "cached · refreshing…"
                } else {
                    note = snap.subscriptionError ?? "usage stale"
                }
                let asOf = snap.subscriptionAsOf.map { "  (as of \(clockTime($0)))" } ?? ""
                line("  ⚠ \(note)\(asOf)")
            }
        } else if snap.subscriptionLoading {
            line("  loading usage…")
        } else {
            line("  unavailable — " + (snap.subscriptionError ?? "endpoint/login"))
        }

        menu.addItem(.separator())

        // Accounts section — powered by cswap (claude-swap). Hidden when cswap is absent.
        // The menu bar NEVER writes the Keychain; all account switching is delegated to cswap.
        buildAccountsSection(menu: menu, header: header, line: line)

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

        // Dev-team config (interactive) + activity
        menu.addItem(.separator())
        header("claude-dev-team")
        let cfg = readCDTConfig()

        // Enable / disable core CDT — clicking flips it (cdt-config on|off).
        let enabledItem = NSMenuItem(title: "Enabled (core CDT)", action: #selector(applyConfig(_:)), keyEquivalent: "")
        enabledItem.target = self
        enabledItem.state = cfg.enabled ? .on : .off
        enabledItem.representedObject = [cfg.enabled ? "off" : "on"]
        menu.addItem(enabledItem)

        // Toolkit engine — a SEPARATE on/off from core CDT (cdt-config toolkit on|off).
        let toolkitItem = NSMenuItem(title: "Toolkit engine", action: #selector(applyConfig(_:)), keyEquivalent: "")
        toolkitItem.target = self
        toolkitItem.state = cfg.toolkitEnabled ? .on : .off
        toolkitItem.representedObject = ["toolkit", cfg.toolkitEnabled ? "off" : "on"]
        menu.addItem(toolkitItem)

        // Prompt enhancement mode (cdt-config prompt-mode auto|always|off).
        menu.addItem(optionSubmenu("Prompt enhance", key: "prompt-mode", current: cfg.promptMode,
            options: [("Auto (default)", "auto"), ("Always", "always"), ("Off", "off")]))

        menu.addItem(optionSubmenu("Eco mode", key: "eco", current: cfg.eco,
            options: [("Auto", "auto"), ("On", "on"), ("Off (default)", "off")]))
        menu.addItem(optionSubmenu("Effort", key: "effort", current: cfg.effort,
            options: [("Low", "low"), ("Medium", "medium"), ("High", "high"), ("Xhigh (default)", "xhigh")]))
        menu.addItem(optionSubmenu("Model", key: "model", current: cfg.model,
            options: [("Opus 4.8 (default)", "claude-opus-4-8"), ("Opus", "opus"),
                      ("Sonnet", "sonnet"), ("Haiku", "haiku")]))
        let applyNote = NSMenuItem(title: "effort / model apply next session", action: nil, keyEquivalent: "")
        applyNote.isEnabled = false
        menu.addItem(applyNote)

        // Activity (7d)
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

        // Updates submenu (Settings → Updates): status, Get/Check Now, and the auto-check toggle.
        menu.addItem(.separator())
        let updates = NSMenuItem(title: "Updates", action: nil, keyEquivalent: "")
        let usub = NSMenu()
        func uinfo(_ t: String) {
            let i = NSMenuItem(title: t, action: nil, keyEquivalent: ""); i.isEnabled = false; usub.addItem(i)
        }
        if let up = snap.update {
            uinfo("⬆  v\(up.version) available  (on v\(versionString ?? "?"))")
            let get = NSMenuItem(title: "Get v\(up.version)…", action: #selector(getUpdateClicked), keyEquivalent: "")
            get.target = self; usub.addItem(get)
        } else {
            uinfo("✓  Up to date" + (versionString.map { "  (v\($0))" } ?? ""))
        }
        let checkNow = NSMenuItem(title: "Check Now", action: #selector(checkUpdateClicked), keyEquivalent: "")
        checkNow.target = self; usub.addItem(checkNow)
        let autoCheck = NSMenuItem(title: "Auto-check on launch", action: #selector(toggleAutoCheckClicked), keyEquivalent: "")
        autoCheck.target = self; autoCheck.state = snap.updateAutoCheck ? .on : .off; usub.addItem(autoCheck)
        usub.addItem(.separator())
        uinfo(snap.updateLastChecked.map { "Last checked: \(clockTime($0))" } ?? "Not checked yet")
        updates.submenu = usub
        menu.addItem(updates)

        menu.addItem(.separator())
        let stamp = clockTime(snap.lastUpdated, seconds: true)
        // Footer: installed version + last refresh (version omitted if it can't be resolved).
        line(versionString.map { "v\($0)  ·  updated \(stamp)" } ?? "updated \(stamp)")

        let refresh = NSMenuItem(title: "Refresh now", action: #selector(refreshClicked), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let quit = NSMenuItem(title: "Quit", action: #selector(quitClicked), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // MARK: - Accounts section (cswap integration)

    /// Builds the Accounts NSMenu section. Gracefully degrades: when cswap is absent, shows a single
    /// disabled install-hint item. Never touches the Keychain — all switching delegated to cswap.
    private func buildAccountsSection(menu: NSMenu,
                                      header: (String) -> Void,
                                      line: (String) -> Void) {
        guard AccountSwap.isAvailable else {
            let hint = NSMenuItem(
                title: "Multi-account: install claude-swap — `uv tool install claude-swap`",
                action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
            menu.addItem(.separator())
            return
        }

        let accounts = AccountSwap.list()

        header("Accounts")

        if accounts.isEmpty {
            line("  no accounts configured")
        } else {
            for account in accounts {
                let item = accountMenuItem(for: account)
                menu.addItem(item)
            }
            // Auto-pick best (most quota remaining)
            let bestItem = NSMenuItem(
                title: "  Auto-pick best account",
                action: #selector(switchBestClicked),
                keyEquivalent: "")
            bestItem.target = self
            menu.addItem(bestItem)
        }

        menu.addItem(.separator())
    }

    /// Builds a menu item for one cswap account: "  email  5h:25% / 7d:16%".
    private func accountMenuItem(for account: CswapAccount) -> NSMenuItem {
        var label = "  \(account.email)"
        // Append quota percentages if available.
        if let fh = account.fiveHourPct, let sd = account.sevenDayPct {
            label += "   \(fh)% / \(sd)%"
        }
        let item = NSMenuItem(title: label, action: #selector(switchAccountClicked(_:)), keyEquivalent: "")
        item.target = self
        // Encode the account number as the represented object (not email, to avoid free-form injection).
        item.representedObject = account.number
        item.state = account.active ? .on : .off
        // Dim rate-limited accounts.
        if account.rateLimited {
            item.attributedTitle = NSAttributedString(
                string: label + "  (rate limited)",
                attributes: [.foregroundColor: NSColor.tertiaryLabelColor,
                             .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)])
            item.isEnabled = false
        } else {
            item.attributedTitle = NSAttributedString(
                string: label,
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)])
        }
        return item
    }

    /// Handles an account menu item click: confirms with the user, then switches via cswap.
    /// Confirmation is REQUIRED — a single stray click must never silently change the active account.
    @objc private func switchAccountClicked(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? Int else { return }
        // Strip leading whitespace from title for display.
        let label = sender.title.trimmingCharacters(in: .whitespaces)
        confirmAndSwitch(to: number, label: label)
    }

    /// Handles "Auto-pick best account" click.
    @objc private func switchBestClicked() {
        let alert = NSAlert()
        alert.messageText = "Switch to best account?"
        alert.informativeText = "claude-swap will switch to the account with the most remaining quota."
        alert.addButton(withTitle: "Switch")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let success = AccountSwap.switchBest()
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if success {
                    // Trigger a usage refresh so the badge reflects the now-active account.
                    // Note: macOS Keychain cache is ~30s; badge may lag slightly.
                    self.onRefresh?()
                    if let snap = self.lastSnap { self.render(snap) }
                } else {
                    let err = NSAlert()
                    err.messageText = "Account switch failed"
                    err.informativeText = "claude-swap could not switch accounts. Check that accounts are configured."
                    err.runModal()
                }
            }
        }
    }

    /// Shows a confirmation alert then calls cswap --switch-to on a background thread.
    private func confirmAndSwitch(to number: Int, label: String) {
        let alert = NSAlert()
        alert.messageText = "Switch account?"
        alert.informativeText = "Switch to account \(number) (\(label))?\nNote: macOS Keychain cache may take ~30s to apply."
        alert.addButton(withTitle: "Switch")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let success = AccountSwap.switchTo(number: number)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if success {
                    // Trigger a usage refresh so the badge reflects the now-active account.
                    // Note: macOS Keychain cache is ~30s; badge may lag slightly after switch.
                    self.onRefresh?()
                    if let snap = self.lastSnap { self.render(snap) }
                } else {
                    let err = NSAlert()
                    err.messageText = "Account switch failed"
                    err.informativeText = "claude-swap could not switch to account \(number). Check cswap is installed and accounts are configured."
                    err.runModal()
                }
            }
        }
    }

    /// A submenu of mutually-exclusive options; the current value is checkmarked. Selecting one runs
    /// `cdt-config <key> <value>`.
    private func optionSubmenu(_ title: String, key: String, current: String,
                               options: [(String, String)]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (label, value) in options {
            let it = NSMenuItem(title: label, action: #selector(applyConfig(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = [key, value]
            it.state = (current == value) ? .on : .off
            sub.addItem(it)
        }
        parent.submenu = sub
        return parent
    }

    /// Runs `~/.claude/bin/cdt-config <args>` then rebuilds the menu so checkmarks reflect the change.
    @objc private func applyConfig(_ sender: NSMenuItem) {
        guard let args = sender.representedObject as? [String] else { return }
        let bin = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/bin/cdt-config").path
        guard FileManager.default.isExecutableFile(atPath: bin) else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = args
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
        if let snap = lastSnap { render(snap) }   // refresh the menu (updated checkmarks / mode)
    }

    @objc private func refreshClicked() { onRefresh?() }
    @objc private func checkUpdateClicked() { onCheckUpdate?() }
    @objc private func toggleAutoCheckClicked() { onToggleAutoCheck?() }
    @objc private func getUpdateClicked() {
        if let s = updateURL, let url = URL(string: s) { NSWorkspace.shared.open(url) }
    }
    @objc private func quitClicked() { NSApp.terminate(nil) }
}
