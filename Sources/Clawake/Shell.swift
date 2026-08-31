import Foundation

struct ShellResult {
    let ok: Bool
    let stdout: String
    let stderr: String
}

/// Run a command to completion and capture output. Blocking: call off the main
/// thread for anything that can prompt (osascript admin).
@discardableResult
func runProcess(_ launchPath: String, _ args: [String]) -> ShellResult {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: launchPath)
    p.arguments = args
    let out = Pipe()
    let err = Pipe()
    p.standardOutput = out
    p.standardError = err
    do {
        try p.run()
    } catch {
        return ShellResult(ok: false, stdout: "", stderr: "\(error)")
    }
    // Drain stderr on a background queue while draining stdout here, so a command
    // that fills one pipe buffer can never deadlock against the other.
    var eData = Data()
    let sem = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        eData = err.fileHandleForReading.readDataToEndOfFile()
        sem.signal()
    }
    let oData = out.fileHandleForReading.readDataToEndOfFile()
    sem.wait()
    p.waitUntilExit()
    return ShellResult(
        ok: p.terminationStatus == 0,
        stdout: String(data: oData, encoding: .utf8) ?? "",
        stderr: String(data: eData, encoding: .utf8) ?? ""
    )
}
