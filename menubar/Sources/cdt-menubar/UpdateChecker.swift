import Foundation
import AppKit
import UserNotifications

/// A newer release the app found on GitHub (notify-only; the app never self-installs).
struct ReleaseInfo: Equatable {
    let version: String   // semver, "v" stripped, e.g. "1.49.0"
    let url: String       // the release's html_url (opened when the user clicks "Get vX.Y.Z")
}

/// Parses GitHub's `releases/latest` JSON into a `ReleaseInfo`. PURE (takes Data) so it is unit-tested.
/// Returns nil if the body has no usable `tag_name`.
func parseLatestRelease(_ data: Data) -> ReleaseInfo? {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let tag = (obj["tag_name"] as? String)?.trimmingCharacters(in: .whitespaces), !tag.isEmpty
    else { return nil }
    let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    guard !version.isEmpty else { return nil }
    let url = (obj["html_url"] as? String)
        ?? "https://github.com/jaysonventura/claude-dev-team/releases/latest"
    return ReleaseInfo(version: version, url: url)
}

/// True when `latest` is a strictly higher semver than `current` (numeric-aware; tolerates a "v" prefix and
/// missing/garbage components). "1.10.0" > "1.9.0"; equal or older → false.
func isNewerVersion(_ latest: String, than current: String) -> Bool {
    func parts(_ s: String) -> [Int] {
        let v = s.hasPrefix("v") ? String(s.dropFirst()) : s
        return v.split(separator: ".").map { seg in Int(seg.prefix { $0.isNumber }) ?? 0 }
    }
    let a = parts(latest), b = parts(current)
    for i in 0..<max(a.count, b.count) {
        let x = i < a.count ? a[i] : 0
        let y = i < b.count ? b[i] : 0
        if x != y { return x > y }
    }
    return false
}

/// Periodically checks GitHub for a newer release of CDT Usage and notifies — it does NOT install anything
/// (installs stay the plugin's `cdt-menubar auto_update` path). Fail-soft: any error leaves the last state
/// untouched and never disrupts the app. The repeating timer + ephemeral session mirror UsageStore's
/// resilience (a single failed check can't break the chain).
final class UpdateChecker {
    private let repo = "jaysonventura/claude-dev-team"
    let currentVersion: String
    private let session: URLSession
    private var timer: Timer?
    private let interval: TimeInterval = 6 * 3600     // re-check every 6h (+ once shortly after launch)

    private(set) var available: ReleaseInfo?          // a newer release, or nil when up to date / unknown
    private(set) var lastChecked: Date?

    /// Called on the main thread after every check (success or failure) so the menu can re-render.
    var onResult: (() -> Void)?

    private let notifiedKey = "cdtLastNotifiedUpdateVersion"
    private let enabledKey = "cdtUpdateCheckEnabled"

    init(currentVersion: String) {
        self.currentVersion = currentVersion
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForResource = 20
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = URLSession(configuration: cfg)
        UserDefaults.standard.register(defaults: [enabledKey: true])   // auto-check on by default
    }

    /// Whether auto-checking is enabled (user toggle, default on). A disabled checker still allows a manual
    /// "Check Now" (force).
    var autoCheckEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            if newValue {
                start()
            } else {
                timer?.invalidate(); timer = nil   // stop the periodic check; manual "Check Now" still works
            }
        }
    }

    func start() {
        guard timer == nil, autoCheckEnabled else { return }
        checkNow()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.checkNow() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Run a check now. `force` (the manual "Check Now") bypasses the auto-check toggle.
    func checkNow(force: Bool = false) {
        guard force || autoCheckEnabled else { return }
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("CDT-Usage/\(currentVersion)", forHTTPHeaderField: "User-Agent")  // GitHub requires a UA
        session.dataTask(with: req) { [weak self] data, resp, _ in
            guard let self = self else { return }
            var newer: ReleaseInfo? = nil
            if let data = data, let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let info = parseLatestRelease(data),
               isNewerVersion(info.version, than: self.currentVersion) {
                newer = info
            }
            DispatchQueue.main.async {
                self.lastChecked = Date()
                self.available = newer
                if let newer = newer { self.notifyOnce(newer) }
                self.onResult?()
            }
        }.resume()
    }

    /// Best-effort system notification, at most once per new version. Guarded so it can never crash a
    /// non-bundled run (e.g. `swift run` / tests, where UNUserNotificationCenter has no bundle proxy).
    private func notifyOnce(_ info: ReleaseInfo) {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: notifiedKey) != info.version else { return }
        defaults.set(info.version, forKey: notifiedKey)
        // Only post from a real .app bundle — UNUserNotificationCenter.current() ABORTS (no bundle proxy)
        // under `swift run` / xctest, where Bundle.main is a CLI/test binary, not an app.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "CDT Usage — update available"
            content.body = "Version \(info.version) is available. Open the menu to get it."
            let req = UNNotificationRequest(identifier: "cdt-update-\(info.version)", content: content, trigger: nil)
            center.add(req)
        }
    }
}
