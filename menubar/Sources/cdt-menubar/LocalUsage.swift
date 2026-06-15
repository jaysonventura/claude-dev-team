import Foundation

// One transcript line we care about. Token usage lives at message.usage; model at message.model.
private struct TranscriptLine: Decodable {
    struct Message: Decodable {
        let model: String?
        let usage: Usage?
    }
    struct Usage: Decodable {
        let input_tokens: Int?
        let output_tokens: Int?
        let cache_read_input_tokens: Int?
        let cache_creation_input_tokens: Int?
    }
    let timestamp: String?
    let message: Message?
}

/// Sums accurate token usage by model for today and the last 7 days from local transcripts.
/// Reads only files modified within the last week (the rest can't contain in-window data).
func readLocalUsage() -> LocalUsage {
    var result = LocalUsage()
    let fm = FileManager.default
    let projects = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    guard let walker = fm.enumerator(at: projects,
                                     includingPropertiesForKeys: [.contentModificationDateKey],
                                     options: [.skipsHiddenFiles]) else {
        return result
    }

    let now = Date()
    let weekAgo = now.addingTimeInterval(-7 * 24 * 3600)
    let cal = Calendar.current
    let isoFull = ISO8601DateFormatter()
    isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let isoPlain = ISO8601DateFormatter()
    let decoder = JSONDecoder()

    for case let url as URL in walker {
        guard url.pathExtension == "jsonl" else { continue }
        if let mod = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           mod < weekAgo {
            continue
        }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }

        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = rawLine.data(using: .utf8),
                  let parsed = try? decoder.decode(TranscriptLine.self, from: lineData),
                  let msg = parsed.message,
                  let usage = msg.usage,
                  let model = msg.model else { continue }

            let when = parsed.timestamp.flatMap { isoFull.date(from: $0) ?? isoPlain.date(from: $0) }
            guard let stamp = when, stamp >= weekAgo else { continue }

            func add(into bucket: inout [String: ModelTokens]) {
                var mt = bucket[model] ?? ModelTokens()
                mt.input += usage.input_tokens ?? 0
                mt.output += usage.output_tokens ?? 0
                mt.cacheRead += usage.cache_read_input_tokens ?? 0
                mt.cacheCreate += usage.cache_creation_input_tokens ?? 0
                bucket[model] = mt
            }
            add(into: &result.week)
            if cal.isDate(stamp, inSameDayAs: now) { add(into: &result.today) }
        }
    }
    return result
}

/// The claude-dev-team on/off switch + defaults, read from the env file + settings.json.
struct CDTConfig {
    var enabled = true
    var effort = "—"
    var model = "—"          // raw, e.g. "claude-opus-4-8"
    var eco = "auto"
}

func readCDTConfig() -> CDTConfig {
    var c = CDTConfig()
    let home = FileManager.default.homeDirectoryForCurrentUser
    if let env = try? String(contentsOf: home.appendingPathComponent(".claude/claude-dev-team.env"), encoding: .utf8) {
        for raw in env.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("CDT_ENABLED=") {
                c.enabled = line.dropFirst("CDT_ENABLED=".count).trimmingCharacters(in: .whitespaces) != "0"
            } else if line.hasPrefix("CDT_ECO=") {
                c.eco = String(line.dropFirst("CDT_ECO=".count)).trimmingCharacters(in: .whitespaces)
            }
        }
    }
    if let data = try? Data(contentsOf: home.appendingPathComponent(".claude/settings.json")),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        c.effort = (obj["effortLevel"] as? String) ?? "—"
        c.model = (obj["model"] as? String) ?? "—"
    }
    return c
}

/// Reads claude-dev-team activity (last 7 days) from the SQLite DB via the sqlite3 CLI.
func readTeamActivity() -> TeamActivity {
    var activity = TeamActivity()
    let dbPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/claude-dev-team.db").path
    guard FileManager.default.fileExists(atPath: dbPath),
          FileManager.default.isExecutableFile(atPath: "/usr/bin/sqlite3") else {
        return activity
    }

    // Cutoff in the same format the DB stores (YYYY-MM-DDTHH:MM:SSZ) so string comparison is valid.
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime]
    let cutoff = iso.string(from: Date().addingTimeInterval(-7 * 24 * 3600))

    func query(_ sql: String) -> [String] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        proc.arguments = [dbPath, sql]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run(); proc.waitUntilExit() } catch { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.split(separator: "\n").map(String.init)
    }

    func pairs(_ rows: [String]) -> [(String, Int)] {
        rows.compactMap { row in
            let parts = row.split(separator: "|", maxSplits: 1)
            guard parts.count == 2, let n = Int(parts[1].trimmingCharacters(in: .whitespaces)) else { return nil }
            return (String(parts[0]), n)
        }
    }

    activity.sessions = Int(query(
        "SELECT COUNT(*) FROM sessions WHERE started >= '\(cutoff)';").first ?? "") ?? 0
    // Exclude any stray 'unknown'/empty rows (a SubagentStop with no identifiable agent type) so the
    // display is always clean, even if an older in-session hook logged one before the skip-unknown fix.
    // Strip the "claude-dev-team:" namespace prefix so roles read as "backend-engineer", not truncated.
    activity.agentRuns = pairs(query(
        "SELECT agent || '|' || COUNT(*) FROM agent_runs WHERE started >= '\(cutoff)' AND agent NOT IN ('unknown','') GROUP BY agent ORDER BY COUNT(*) DESC;"))
        .map { (shortRole($0.0), $0.1) }
    activity.tasksByTier = pairs(query(
        "SELECT COALESCE(tier,'?') || '|' || COUNT(*) FROM tasks WHERE started >= '\(cutoff)' GROUP BY tier ORDER BY tier;"))
    return activity
}
