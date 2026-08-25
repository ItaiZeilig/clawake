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
    let oData = out.fileHandleForReading.readDataToEndOfFile()
    let eData = err.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return ShellResult(
        ok: p.terminationStatus == 0,
        stdout: String(data: oData, encoding: .utf8) ?? "",
        stderr: String(data: eData, encoding: .utf8) ?? ""
    )
}
