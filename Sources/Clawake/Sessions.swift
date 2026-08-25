import Foundation

struct SessionInfo {
    var lastActivity: Date
    var transcriptPath: String?
}

/// Active means recent activity AND, when we know it, a live transcript.
final class SessionManager {
    private var sessions: [String: SessionInfo] = [:]

    func add(id: String, transcriptPath: String?) {
        let now = Date()
        if var s = sessions[id] {
            s.lastActivity = now
            if let t = transcriptPath { s.transcriptPath = t }
            sessions[id] = s
        } else {
            sessions[id] = SessionInfo(lastActivity: now, transcriptPath: transcriptPath)
        }
    }

    func remove(id: String) { sessions[id] = nil }

    func activeCount(timeout: TimeInterval, now: Date = Date()) -> Int {
        var count = 0
        var stale: [String] = []
        for (id, s) in sessions {
            if isLive(s, timeout: timeout, now: now) { count += 1 } else { stale.append(id) }
        }
        for id in stale { sessions[id] = nil }
        return count
    }

    private func isLive(_ s: SessionInfo, timeout: TimeInterval, now: Date) -> Bool {
        if now.timeIntervalSince(s.lastActivity) >= timeout { return false }
        if let t = s.transcriptPath {
            guard let attr = try? FileManager.default.attributesOfItem(atPath: t),
                  let m = attr[.modificationDate] as? Date
            else {
                return false  // transcript gone => session gone
            }
            if now.timeIntervalSince(m) >= timeout { return false }
        }
        return true
    }
}
