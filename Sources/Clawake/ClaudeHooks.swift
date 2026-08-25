import Foundation

let hookHint = "plugins/clawake/control.sock"

private func post(_ route: String) -> String {
    "curl -s -m 2 --unix-socket \"$HOME/.claude/plugins/clawake/control.sock\" "
        + "-X POST --data-binary @- http://clawake/\(route) >/dev/null 2>&1 || true"
}

private let caffeinateEvents = ["UserPromptSubmit", "PreToolUse", "PostToolUse"]
private let uncaffeinateEvents = ["Notification", "Stop", "SessionEnd"]
private let matcherEvents: Set<String> = ["PreToolUse", "PostToolUse"]

private func groupIsOurs(_ group: [String: Any]) -> Bool {
    guard let hooks = group["hooks"] as? [[String: Any]] else { return false }
    return hooks.contains { ($0["command"] as? String)?.contains(hookHint) ?? false }
}

private func readSettings() -> [String: Any] {
    guard let data = try? Data(contentsOf: Paths.settingsFile),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }
    return obj
}

private func writeSettings(_ obj: [String: Any]) -> Bool {
    do {
        try FileManager.default.createDirectory(
            at: Paths.settingsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: Paths.settingsFile)
        return true
    } catch {
        return false
    }
}

func claudeHooksInstalled() -> Bool {
    guard let hooks = readSettings()["hooks"] as? [String: Any] else { return false }
    for (_, value) in hooks {
        if let arr = value as? [[String: Any]], arr.contains(where: groupIsOurs) { return true }
    }
    return false
}

@discardableResult
func installClaudeHooks() -> Bool {
    var obj = readSettings()
    // One-time backup before the first edit.
    if let data = try? Data(contentsOf: Paths.settingsFile) {
        let backup = Paths.settingsFile.path + ".clawake-backup"
        if !FileManager.default.fileExists(atPath: backup) {
            try? data.write(to: URL(fileURLWithPath: backup))
        }
    }
    var hooks = (obj["hooks"] as? [String: Any]) ?? [:]
    func add(_ event: String, _ command: String) {
        var arr = (hooks[event] as? [[String: Any]]) ?? []
        if arr.contains(where: groupIsOurs) { return }
        var group: [String: Any] = ["hooks": [["type": "command", "command": command]]]
        if matcherEvents.contains(event) { group["matcher"] = "*" }
        arr.append(group)
        hooks[event] = arr
    }
    for e in caffeinateEvents { add(e, post("caffeinate")) }
    for e in uncaffeinateEvents { add(e, post("uncaffeinate")) }
    obj["hooks"] = hooks
    return writeSettings(obj)
}

@discardableResult
func uninstallClaudeHooks() -> Bool {
    var obj = readSettings()
    if var hooks = obj["hooks"] as? [String: Any] {
        for (event, value) in hooks {
            guard let arr = value as? [[String: Any]] else { continue }
            let kept = arr.filter { !groupIsOurs($0) }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        obj["hooks"] = hooks
    }
    return writeSettings(obj)
}
