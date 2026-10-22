import Foundation

@main
struct FeatureModelTests {
    static func main() throws {
        var assertions = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            assertions += 1
        }
        var rule = SustainedCondition()
        check(!rule.evaluate(true, now: 100, duration: 30, maximumGap: 10), "rule must wait")
        for second in 101..<130 {
            check(!rule.evaluate(true, now: Double(second), duration: 30, maximumGap: 10), "sampling must not shorten wall-clock duration")
        }
        check(rule.evaluate(true, now: 130, duration: 30, maximumGap: 10), "fire after actual duration")
        check(!rule.evaluate(true, now: 131, duration: 30, maximumGap: 10), "do not repeatedly notify")
        check(!rule.evaluate(false, now: 132, duration: 30, maximumGap: 10), "normal sample resets")
        check(!rule.evaluate(true, now: 133, duration: 30, maximumGap: 10), "fresh interval starts")
        check(!rule.evaluate(true, now: 200, duration: 30, maximumGap: 10), "sleep or missing samples reset continuity")
        check(rule.evaluate(true, now: 201, duration: 0, maximumGap: 10), "zero duration is immediate")
        check(!rule.evaluate(true, now: 202, duration: 5, maximumGap: 10), "changing duration starts a new interval")
        check(!rule.evaluate(true, now: 190, duration: 5, maximumGap: 10), "backward time resets")
        check(!rule.evaluate(true, now: .nan, duration: 5, maximumGap: 10), "invalid time resets")
        check(!rule.evaluate(true, now: 300, duration: 10, maximumGap: 20, signature: "75"), "start threshold interval")
        check(!rule.evaluate(true, now: 310, duration: 10, maximumGap: 20, signature: "90"), "changing threshold starts a new interval")
        check(rule.evaluate(true, now: 320, duration: 10, maximumGap: 20, signature: "90"), "new threshold needs its own full duration")

        var curve = FanCurveConfiguration()
        curve.sensorKey = "cpu"
        curve.points = [FanCurvePoint(40, 0), FanCurvePoint(60, 50), FanCurvePoint(80, 100)]
        check(curve.isValid, "valid rising curve")
        check(curve.targetRPM(temperature: 30, minimum: 1000, maximum: 5000) == 1000, "low endpoint clamps")
        check(curve.targetRPM(temperature: 50, minimum: 1000, maximum: 5000) == 2000, "interpolate intermediate temperature")
        check(curve.targetRPM(temperature: 90, minimum: 1000, maximum: 5000) == 5000, "high endpoint clamps")
        check(curve.targetRPM(temperature: .nan, minimum: 1000, maximum: 5000) == nil, "invalid sensor rejects control")
        check(curve.targetRPM(temperature: 50, minimum: 5000, maximum: 1000) == nil, "invalid hardware limits reject")
        curve.points[1].temperature = 40
        check(!curve.isValid, "duplicate temperatures reject")
        curve.points = [FanCurvePoint(40, 90), FanCurvePoint(60, 50)]
        check(!curve.isValid, "falling target speeds reject")
        curve.points = [FanCurvePoint(40, 0), FanCurvePoint(80, 120)]
        check(!curve.isValid, "out-of-range speeds reject")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("stats-history-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / 300) * 300)
        let archive = HistoryArchive(directory: directory)
        archive.record(module: "CPU", metrics: [HistoryMetric("usage", "CPU", "%", 20)], at: now)
        archive.record(module: "CPU", metrics: [HistoryMetric("usage", "CPU", "%", 80)], at: now.addingTimeInterval(1))
        archive.record(module: "CPU", metrics: [HistoryMetric("usage", "CPU", "%", .nan)], at: now.addingTimeInterval(2))
        archive.flush()
        let samples = archive.samples(module: "CPU", series: "usage", range: 3600, endingAt: now.addingTimeInterval(3))
        check(samples.count == 1, "nearby samples aggregate")
        check(samples[0].mean == 50 && samples[0].minimum == 20 && samples[0].maximum == 80 && samples[0].count == 2, "mean and peak retain different meaning")
        let reopened = HistoryArchive(directory: directory)
        check(reopened.availableSeries(module: "CPU").count == 1, "persisted data loads after restart")
        check(reopened.samples(module: "CPU", series: "usage", range: 3600, endingAt: now.addingTimeInterval(3))[0].mean == 50, "restart preserves mean")
        archive.record(module: "CPU", metrics: [HistoryMetric("usage", "CPU", "%", 40)], at: now.addingTimeInterval(600))
        archive.flush()
        check(archive.samples(module: "CPU", series: "usage", range: 3600, endingAt: now.addingTimeInterval(601)).count == 2, "missing intervals remain absent")
        archive.record(module: "CPU", metrics: [HistoryMetric("usage", "CPU", "%", 60)], at: now.addingTimeInterval(29 * 86400))
        archive.flush()
        let retained = archive.samples(module: "CPU", series: "usage", range: 28 * 86400, endingAt: now.addingTimeInterval(29 * 86400))
        check(retained.count == 1 && retained[0].mean == 60, "28-day retention prunes expired buckets")
        check(HistoryArchive.resolution(for: 3600) == 5, "hour resolution")
        check(HistoryArchive.resolution(for: 86400) == 60, "day resolution")
        check(HistoryArchive.resolution(for: 7 * 86400) == 300, "week resolution")
        check(archive.storageError == nil, "storage reports successful writes")
        print("Passed \(assertions) model, timing, aggregation, restart and retention checks")
    }
}
