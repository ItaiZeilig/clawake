import Foundation

public struct BatteryConfig: Codable {
    public var min_percent: Int
    public var only_on_ac: Bool

    public init(min_percent: Int, only_on_ac: Bool) {
        self.min_percent = min_percent
        self.only_on_ac = only_on_ac
    }
}

public struct ThermalConfig: Codable {
    public var protect: Bool
    public var cutoff: String   // "serious" | "critical"

    public init(protect: Bool, cutoff: String) {
        self.protect = protect
        self.cutoff = cutoff
    }
}

public struct Config: Codable {
    public var mode: Mode
    public var lidClosed: Bool          // keep awake with the lid shut (needs the helper)
    public var preventLock: Bool        // also keep the display on so the screen never locks
    public var pauseOnLowBattery: Bool  // whether the battery floor applies at all
    public var battery: BatteryConfig
    public var thermal: ThermalConfig
    public var notifications: Bool
    public var didOnboard: Bool         // has the welcome screen been shown once

    public static let defaults = Config(
        mode: .on,
        lidClosed: false,   // opt-in: the app works out of the box with no approval
        preventLock: true,
        pauseOnLowBattery: true,
        battery: BatteryConfig(min_percent: 15, only_on_ac: false),
        thermal: ThermalConfig(protect: true, cutoff: "serious"),
        notifications: true,
        didOnboard: false
    )

    // Tolerate configs written by older builds that lacked the newer keys.
    enum CodingKeys: String, CodingKey {
        case mode, lidClosed, preventLock, pauseOnLowBattery, battery, thermal, notifications, didOnboard
    }

    public init(mode: Mode, lidClosed: Bool, preventLock: Bool, pauseOnLowBattery: Bool,
                battery: BatteryConfig, thermal: ThermalConfig, notifications: Bool, didOnboard: Bool) {
        self.mode = mode
        self.lidClosed = lidClosed
        self.preventLock = preventLock
        self.pauseOnLowBattery = pauseOnLowBattery
        self.battery = battery
        self.thermal = thermal
        self.notifications = notifications
        self.didOnboard = didOnboard
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.defaults
        mode = try c.decodeIfPresent(Mode.self, forKey: .mode) ?? d.mode
        lidClosed = try c.decodeIfPresent(Bool.self, forKey: .lidClosed) ?? d.lidClosed
        preventLock = try c.decodeIfPresent(Bool.self, forKey: .preventLock) ?? d.preventLock
        pauseOnLowBattery = try c.decodeIfPresent(Bool.self, forKey: .pauseOnLowBattery) ?? d.pauseOnLowBattery
        battery = try c.decodeIfPresent(BatteryConfig.self, forKey: .battery) ?? d.battery
        thermal = try c.decodeIfPresent(ThermalConfig.self, forKey: .thermal) ?? d.thermal
        notifications = try c.decodeIfPresent(Bool.self, forKey: .notifications) ?? d.notifications
        didOnboard = try c.decodeIfPresent(Bool.self, forKey: .didOnboard) ?? d.didOnboard
    }
}

public enum Paths {
    public static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    public static var configDir: URL { home.appendingPathComponent(".claude/plugins/clawake", isDirectory: true) }
    public static var configFile: URL { configDir.appendingPathComponent("config.json") }
    public static var socketPath: String { configDir.appendingPathComponent("control.sock").path }
    public static var settingsFile: URL { home.appendingPathComponent(".claude/settings.json") }
}

public func loadConfig() -> Config {
    guard let data = try? Data(contentsOf: Paths.configFile),
          let cfg = try? JSONDecoder().decode(Config.self, from: data)
    else {
        return Config.defaults
    }
    return cfg
}

public func saveConfig(_ cfg: Config) {
    try? FileManager.default.createDirectory(at: Paths.configDir, withIntermediateDirectories: true)
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? enc.encode(cfg) {
        try? data.write(to: Paths.configFile)
    }
}
