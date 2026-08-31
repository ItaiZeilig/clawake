import Foundation

struct BatteryConfig: Codable {
    var min_percent: Int
    var only_on_ac: Bool
}

struct ThermalConfig: Codable {
    var protect: Bool
    var cutoff: String   // "serious" | "critical"
}

struct Config: Codable {
    var mode: Mode
    var battery: BatteryConfig
    var thermal: ThermalConfig
    var notifications: Bool

    static let defaults = Config(
        mode: .on,
        battery: BatteryConfig(min_percent: 15, only_on_ac: false),
        thermal: ThermalConfig(protect: true, cutoff: "serious"),
        notifications: true
    )
}

enum Paths {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var configDir: URL { home.appendingPathComponent(".claude/plugins/clawake", isDirectory: true) }
    static var configFile: URL { configDir.appendingPathComponent("config.json") }
    static var socketPath: String { configDir.appendingPathComponent("control.sock").path }
    static var settingsFile: URL { home.appendingPathComponent(".claude/settings.json") }
    static let sudoersFile = "/etc/sudoers.d/clawake"
}

func loadConfig() -> Config {
    guard let data = try? Data(contentsOf: Paths.configFile),
          let cfg = try? JSONDecoder().decode(Config.self, from: data)
    else {
        return Config.defaults
    }
    return cfg
}

func saveConfig(_ cfg: Config) {
    try? FileManager.default.createDirectory(at: Paths.configDir, withIntermediateDirectories: true)
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? enc.encode(cfg) {
        try? data.write(to: Paths.configFile)
    }
}
