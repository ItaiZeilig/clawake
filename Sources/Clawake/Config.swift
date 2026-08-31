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
    var lidClosed: Bool          // keep awake with the lid shut (needs the helper)
    var pauseOnLowBattery: Bool  // whether the battery floor applies at all
    var battery: BatteryConfig
    var thermal: ThermalConfig
    var notifications: Bool
    var didOnboard: Bool         // has the welcome screen been shown once

    static let defaults = Config(
        mode: .on,
        lidClosed: true,
        pauseOnLowBattery: true,
        battery: BatteryConfig(min_percent: 15, only_on_ac: false),
        thermal: ThermalConfig(protect: true, cutoff: "serious"),
        notifications: true,
        didOnboard: false
    )

    // Tolerate configs written by older builds that lacked the newer keys.
    enum CodingKeys: String, CodingKey {
        case mode, lidClosed, pauseOnLowBattery, battery, thermal, notifications, didOnboard
    }

    init(mode: Mode, lidClosed: Bool, pauseOnLowBattery: Bool, battery: BatteryConfig,
         thermal: ThermalConfig, notifications: Bool, didOnboard: Bool) {
        self.mode = mode
        self.lidClosed = lidClosed
        self.pauseOnLowBattery = pauseOnLowBattery
        self.battery = battery
        self.thermal = thermal
        self.notifications = notifications
        self.didOnboard = didOnboard
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.defaults
        mode = try c.decodeIfPresent(Mode.self, forKey: .mode) ?? d.mode
        lidClosed = try c.decodeIfPresent(Bool.self, forKey: .lidClosed) ?? d.lidClosed
        pauseOnLowBattery = try c.decodeIfPresent(Bool.self, forKey: .pauseOnLowBattery) ?? d.pauseOnLowBattery
        battery = try c.decodeIfPresent(BatteryConfig.self, forKey: .battery) ?? d.battery
        thermal = try c.decodeIfPresent(ThermalConfig.self, forKey: .thermal) ?? d.thermal
        notifications = try c.decodeIfPresent(Bool.self, forKey: .notifications) ?? d.notifications
        didOnboard = try c.decodeIfPresent(Bool.self, forKey: .didOnboard) ?? d.didOnboard
    }
}

enum Paths {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var configDir: URL { home.appendingPathComponent(".claude/plugins/clawake", isDirectory: true) }
    static var configFile: URL { configDir.appendingPathComponent("config.json") }
    static var socketPath: String { configDir.appendingPathComponent("control.sock").path }
    static var settingsFile: URL { home.appendingPathComponent(".claude/settings.json") }
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
