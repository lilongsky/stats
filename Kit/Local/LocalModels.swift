import Foundation

// A rule fires once per continuous interval. Missing samples break continuity.
public struct SustainedCondition {
    private var started: TimeInterval?
    private var lastSeen: TimeInterval?
    private var fired = false
    private var previousDuration: TimeInterval?
    private var previousSignature: String?
    public init() {}
    public mutating func evaluate(_ satisfied: Bool, now: TimeInterval,
                                  duration: TimeInterval, maximumGap: TimeInterval, signature: String? = nil) -> Bool {
        let duration = max(0, duration)
        if !satisfied || !now.isFinite {
            self = SustainedCondition()
            return false
        }
        if self.previousDuration != duration || self.previousSignature != signature ||
            self.lastSeen.map({ now < $0 || now - $0 > maximumGap }) == true {
            self = SustainedCondition()
        }
        self.previousDuration = duration
        self.previousSignature = signature
        self.lastSeen = now
        if self.started == nil { self.started = now }
        guard !self.fired, now - (self.started ?? now) >= duration else { return false }
        self.fired = true
        return true
    }
}

public struct FanCurvePoint: Codable, Equatable {
    public var temperature: Double
    public var percent: Double
    public init(_ temperature: Double, _ percent: Double) {
        self.temperature = temperature
        self.percent = percent
    }
}

public struct FanCurveConfiguration: Codable {
    public var enabled: Bool = false
    public var sensorKey: String = ""
    public var points: [FanCurvePoint] = [
        FanCurvePoint(40, 20), FanCurvePoint(65, 55), FanCurvePoint(85, 100)
    ]
    public init() {}
    public var isValid: Bool {
        guard self.points.count >= 2, !self.sensorKey.isEmpty else { return false }
        for (index, point) in self.points.enumerated() {
            guard point.temperature.isFinite, point.percent.isFinite,
                  (0...120).contains(point.temperature), (0...100).contains(point.percent) else { return false }
            if index > 0 {
                guard point.temperature > self.points[index-1].temperature,
                      point.percent >= self.points[index-1].percent else { return false }
            }
        }
        return true
    }
    public func targetRPM(temperature: Double, minimum: Double, maximum: Double) -> Double? {
        guard self.isValid, temperature.isFinite, temperature > 0, temperature <= 125,
              minimum.isFinite, maximum.isFinite, minimum >= 0, maximum > minimum else { return nil }
        var percent = self.points.last!.percent
        if temperature <= self.points.first!.temperature {
            percent = self.points.first!.percent
        } else {
            for index in 1..<self.points.count where temperature <= self.points[index].temperature {
                let lower = self.points[index-1], upper = self.points[index]
                let fraction = (temperature - lower.temperature) / (upper.temperature - lower.temperature)
                percent = lower.percent + (upper.percent - lower.percent) * fraction
                break
            }
        }
        return min(maximum, max(minimum, minimum + (maximum - minimum) * percent / 100))
    }
}
