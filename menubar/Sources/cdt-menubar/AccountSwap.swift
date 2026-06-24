import Foundation

// MARK: - Data model

/// A single cswap-managed account, decoded from `cswap --list --json` output.
/// All quota fields are optional: older cswap versions (pre-0.14) lack --json entirely;
/// even 0.14+ may evolve the schema. Parse defensively; tolerate missing keys.
struct CswapAccount {
    let number: Int
    let email: String
    let active: Bool
    // Usage: percentage values (0-100), derived from the pct field (0.0–100.0 float).
    let fiveHourPct: Int?
    let sevenDayPct: Int?
    // ISO-8601 reset timestamps, forwarded as opaque strings for display.
    let fiveHourResetsAt: String?
    let sevenDayResetsAt: String?
    // "ok" | "rate_limited" | "unavailable" — or any future string; derive rateLimited from this.
    let usageStatus: String?
    var rateLimited: Bool { usageStatus == "rate_limited" }
    /// A short human-readable reset label, if available (e.g. "7d resets Jul 1").
    var resetIn: String? {
        if let r = sevenDayResetsAt { return r }
        if let r = fiveHourResetsAt { return r }
        return nil
    }
}

// MARK: - Private Codable structs (internal to parseList)
// These mirror the cswap 0.14+ JSON schema exactly.  All fields optional for forward-compat.

private struct CswapListPayload: Decodable {
    let schemaVersion: Int?
    let activeAccountNumber: Int?
    let accounts: [CswapAccountPayload]?
    let error: CswapErrorPayload?
}

private struct CswapAccountPayload: Decodable {
    let number: Int?
    let email: String?
    let active: Bool?
    let usageStatus: String?
    let usage: CswapUsagePayload?
}

private struct CswapUsagePayload: Decodable {
    let fiveHour: CswapWindowPayload?
    let sevenDay: CswapWindowPayload?
}

private struct CswapWindowPayload: Decodable {
    let pct: Double?
    let resetsAt: String?
}

private struct CswapErrorPayload: Decodable {
    let message: String?
}

// MARK: - AccountSwap namespace

/// Wrapper around the `cswap` CLI (claude-swap, https://github.com/realiti4/claude-swap).
/// All credential mutation is delegated to cswap — this wrapper NEVER touches the Keychain
/// (no SecItemAdd / SecItemUpdate / SecItemDelete, ever).
///
/// Security constraints:
///  - Binary is resolved to an absolute path; `isExecutableFile` is checked before every run.
///  - Process is invoked via `executableURL` + `arguments:[String]` (never /bin/sh -c).
///  - Only a strict allow-list of non-destructive operations is exposed.
///  - cswap stdout is treated as untrusted data: size-capped, decoded via Codable, never eval'd.
///  - No tokens/secrets are logged, printed, or persisted.
enum AccountSwap {

    // MARK: - cswap discovery

    /// Known absolute install locations, in preference order.
    /// cswap is a uv-tools symlink and is NOT on the launchd-inherited PATH of a GUI app.
    private static let knownPaths: [String] = [
        NSHomeDirectory() + "/.local/bin/cswap",            // uv tool install (most common)
        NSHomeDirectory() + "/.cargo/bin/cswap",            // cargo install (unlikely but listed)
        "/opt/homebrew/bin/cswap",                          // Homebrew arm64
        "/usr/local/bin/cswap",                             // Homebrew x86_64 / manual
    ]

    /// Maximum bytes read from cswap stdout to prevent an unbounded-pipe DoS.
    private static let maxOutputBytes = 256 * 1024   // 256 KB

    /// Returns the absolute path to the cswap binary, or nil when it isn't installed.
    /// Searches the allow-listed paths first, then asks `which` as a last resort.
    static func locate() -> String? {
        let fm = FileManager.default
        for path in knownPaths where fm.isExecutableFile(atPath: path) {
            return path
        }
        // Fallback: ask /usr/bin/which (it is on the launchd PATH).
        if let found = runCapture(binary: "/usr/bin/which", arguments: ["cswap"])?.trimmingCharacters(in: .whitespacesAndNewlines),
           !found.isEmpty, fm.isExecutableFile(atPath: found) {
            return found
        }
        return nil
    }

    // MARK: - Public API

    /// True when cswap is installed and executable on this machine.
    static var isAvailable: Bool { locate() != nil }

    /// Returns all managed accounts, or [] when cswap is absent or the call fails.
    static func list() -> [CswapAccount] {
        guard let bin = locate() else { return [] }
        guard let data = runCaptureData(binary: bin, arguments: ["--list", "--json"]) else { return [] }
        return parseList(data)
    }

    /// Switches to the account with the given number.
    /// Returns true on success (cswap exit 0 + "switched":true).
    /// NEVER touches the Keychain; all credential mutation delegated to cswap.
    @discardableResult
    static func switchTo(number: Int) -> Bool {
        guard let bin = locate() else { return false }
        return runSwitch(binary: bin, arguments: ["--switch-to", "\(number)", "--json"])
    }

    /// Switches to the account with the most remaining quota (--strategy best).
    @discardableResult
    static func switchBest() -> Bool {
        guard let bin = locate() else { return false }
        return runSwitch(binary: bin, arguments: ["--switch", "--strategy", "best", "--json"])
    }

    // MARK: - Pure parser (unit-tested)

    /// Decodes the raw bytes emitted by `cswap --list --json` into account models.
    /// PURE: takes Data, returns [CswapAccount]. Tolerates missing/unknown fields.
    /// Called by `list()` and by unit tests (no process execution).
    static func parseList(_ json: Data) -> [CswapAccount] {
        guard let payload = try? JSONDecoder().decode(CswapListPayload.self, from: json) else { return [] }
        // If cswap signals an error via {"error":{...}}, treat it as an empty list.
        guard payload.error == nil else { return [] }
        guard let rawAccounts = payload.accounts else { return [] }
        return rawAccounts.compactMap { a in
            guard let number = a.number, let email = a.email else { return nil }
            let fiveHourPct = a.usage?.fiveHour?.pct.map { Int($0.rounded()) }
            let sevenDayPct = a.usage?.sevenDay?.pct.map { Int($0.rounded()) }
            return CswapAccount(
                number: number,
                email: email,
                active: a.active ?? false,
                fiveHourPct: fiveHourPct,
                sevenDayPct: sevenDayPct,
                fiveHourResetsAt: a.usage?.fiveHour?.resetsAt,
                sevenDayResetsAt: a.usage?.sevenDay?.resetsAt,
                usageStatus: a.usageStatus
            )
        }
    }

    // MARK: - Private helpers

    /// Runs a cswap switch command and interprets the JSON result.
    /// Returns true iff exit code 0 AND ("switched":true OR JSON decode fails but exit was 0).
    private static func runSwitch(binary: String, arguments: [String]) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: binary) else { return false }
        let (data, exitCode) = runProcess(binary: binary, arguments: arguments)
        guard exitCode == 0 else { return false }
        // If the output is parseable JSON check "switched"; if not parseable but exit 0 => treat as success.
        guard let data = data else { return true }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Check for error field first.
            if obj["error"] != nil { return false }
            if let switched = obj["switched"] as? Bool { return switched }
        }
        return true   // exit 0 with non-JSON or unrecognized payload → success
    }

    /// Runs a binary, captures stdout as a String (UTF-8), nil on error or timeout.
    private static func runCapture(binary: String, arguments: [String]) -> String? {
        guard let data = runCaptureData(binary: binary, arguments: arguments) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Runs a binary, captures stdout as Data (capped at maxOutputBytes), nil on error or timeout.
    private static func runCaptureData(binary: String, arguments: [String]) -> Data? {
        let (data, _) = runProcess(binary: binary, arguments: arguments)
        return data
    }

    /// Core Process runner: argument-array invocation (NEVER /bin/sh), bounded output, explicit timeout.
    /// Returns (stdout data, exit code).  On timeout or error, returns (nil, -1).
    private static func runProcess(binary: String, arguments: [String]) -> (Data?, Int32) {
        guard FileManager.default.isExecutableFile(atPath: binary) else { return (nil, -1) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binary)
        p.arguments = arguments
        // Pass a minimal environment — do NOT inherit the full parent env (which may carry tokens).
        // HOME is needed so cswap can find its data at ~/.local/share/claude-swap.
        p.environment = [
            "HOME": NSHomeDirectory(),
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        ]
        let stdout = Pipe()
        let stderr = Pipe()
        p.standardOutput = stdout
        p.standardError = stderr

        do { try p.run() } catch { return (nil, -1) }

        // Bounded read: drain stdout in a background thread with a cap.
        var outputData = Data()
        let readGroup = DispatchGroup()
        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            defer { readGroup.leave() }
            var remaining = maxOutputBytes
            let fh = stdout.fileHandleForReading
            while remaining > 0 {
                let chunk = fh.availableData
                if chunk.isEmpty { break }
                let take = min(chunk.count, remaining)
                outputData.append(chunk.prefix(take))
                remaining -= take
            }
        }

        // Bounded timeout: 10 seconds — prevents a hung or interactive cswap from freezing the menu bar.
        let deadline = DispatchTime.now() + .seconds(10)
        if readGroup.wait(timeout: deadline) == .timedOut {
            p.terminate()
            return (nil, -1)
        }
        p.waitUntilExit()
        return (outputData.isEmpty ? nil : outputData, p.terminationStatus)
    }
}
