import Foundation

// MARK: - Battery / power source reading

public struct PowerReading {
    public var onBattery: Bool
    public var percent: Int?

    public init(onBattery: Bool, percent: Int?) {
        self.onBattery = onBattery
        self.percent = percent
    }
}

public func parsePmsetBatt(_ output: String) -> PowerReading {
    let onBattery = output.contains("'Battery Power'")
    var percent: Int?
    if let range = output.range(of: #"[0-9]+%"#, options: .regularExpression) {
        let token = output[range].dropLast()  // strip the % sign
        if let v = Int(token) { percent = min(100, max(0, v)) }
    }
    return PowerReading(onBattery: onBattery, percent: percent)
}
