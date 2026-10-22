import Cocoa
import Kit

internal final class FanCurveController: NSObject {
    static let shared = FanCurveController()
    private var owned: Set<Int> = []
    private var baselines: [Int: Double] = [:]
    private var lastTargets: [Int: Double] = [:]
    private var lastWrites: [Int: TimeInterval] = [:]
    private var lastSample: TimeInterval = 0
    private var timer: Timer?
    private var sleeping = false

    override private init() {
        super.init()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        self.timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if ProcessInfo.processInfo.systemUptime - self.lastSample > 10 { self.restoreAll() }
        }
    }
    static func key(_ fan: Int) -> String { "Sensors_fanCurve_\(fan)" }
    func configuration(_ fan: Int) -> FanCurveConfiguration {
        guard let data = Store.shared.data(key: Self.key(fan)),
              let config = try? JSONDecoder().decode(FanCurveConfiguration.self, from: data) else { return FanCurveConfiguration() }
        return config
    }
    func save(_ configuration: FanCurveConfiguration, fan: Int) {
        if let data = try? JSONEncoder().encode(configuration) { Store.shared.set(key: Self.key(fan), value: data) }
        if !configuration.enabled || !configuration.isValid { self.restore(fan) }
    }
    func disable(fan: Int) {
        var configuration = self.configuration(fan)
        guard configuration.enabled || self.owned.contains(fan) else { return }
        configuration.enabled = false
        self.save(configuration, fan: fan)
    }
    func update(_ sensors: [Sensor_p]) {
        precondition(Thread.isMainThread)
        self.lastSample = ProcessInfo.processInfo.systemUptime
        guard !self.sleeping, SMCHelper.shared.isInstalled else { self.restoreAll(); return }
        let fans = sensors.compactMap { $0 as? Fan }
        let present = Set(fans.map { $0.id })
        for id in self.owned.subtracting(present) { self.restore(id) }
        for fan in fans {
            let config = self.configuration(fan.id)
            guard config.enabled, config.isValid,
                  let sensor = sensors.first(where: { $0.key == config.sensorKey && $0.type == .temperature }),
                  let desired = config.targetRPM(temperature: sensor.value, minimum: fan.minSpeed, maximum: fan.maxSpeed) else {
                self.restore(fan.id); continue
            }
            if !self.owned.contains(fan.id) {
                self.baselines[fan.id] = fan.value
                self.owned.insert(fan.id)
                self.lastTargets[fan.id] = max(fan.minSpeed, fan.value)
                SMCHelper.shared.setFanMode(fan.id, mode: FanMode.forced.rawValue)
            }
            let now = ProcessInfo.processInfo.systemUptime
            let elapsed = max(0, now - (self.lastWrites[fan.id] ?? (now - 2)))
            guard elapsed >= 2 else { continue }
            // Keep at least the automatic speed observed when control started.
            let target = max(desired, min(fan.maxSpeed, self.baselines[fan.id] ?? fan.minSpeed))
            let previous = self.lastTargets[fan.id] ?? fan.value
            let step = 300 * min(5, elapsed)
            let limited = min(fan.maxSpeed, max(fan.minSpeed, min(previous + step, max(previous - step, target))))
            if abs(limited - previous) >= 50 || self.lastWrites[fan.id] == nil {
                SMCHelper.shared.setFanSpeed(fan.id, speed: Int(limited.rounded()))
                self.lastTargets[fan.id] = limited
                self.lastWrites[fan.id] = now
            }
        }
    }
    private func restore(_ fan: Int) {
        guard self.owned.remove(fan) != nil else { return }
        SMCHelper.shared.setFanMode(fan, mode: FanMode.automatic.rawValue)
        self.baselines.removeValue(forKey: fan)
        self.lastTargets.removeValue(forKey: fan)
        self.lastWrites.removeValue(forKey: fan)
    }
    private func restoreAll() { for fan in Array(self.owned) { self.restore(fan) } }
    func shutdown() { self.restoreAll(); self.timer?.invalidate() }
    @objc private func willSleep() { self.sleeping = true; self.restoreAll() }
    @objc private func didWake() { self.sleeping = false; self.lastSample = 0 }
}

internal final class FanCurveSettingsView: NSStackView {
    private let fans: [Fan]
    private let sensors: [Sensor_p]
    init(sensors: [Sensor_p]) {
        self.fans = sensors.compactMap { $0 as? Fan }.filter { $0.maxSpeed > $0.minSpeed }
        self.sensors = sensors.filter { $0.type == .temperature }
        super.init(frame: .zero)
        self.orientation = .vertical
        self.spacing = Constants.Settings.margin
        self.identifier = NSUserInterfaceItemIdentifier("fan-curve-settings")
        self.reload()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func reload() {
        self.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard !self.fans.isEmpty else {
            self.addArrangedSubview(PreferencesSection(title: "温度风扇曲线", [
                localFeatureLabel("当前机型没有可控制风扇。")
            ]))
            return
        }
        for fan in self.fans {
            var configuration = FanCurveController.shared.configuration(fan.id)
            if configuration.sensorKey.isEmpty {
                configuration.sensorKey = self.sensors.first(where: { $0.key == "Hottest CPU" })?.key ?? self.sensors.first?.key ?? ""
            }
            let status = localFeatureLabel("")
            func updateStatus() {
                status.stringValue = !configuration.isValid ? "请选择温度传感器，并将温度点和转速设为递增。" :
                    (configuration.enabled ? "曲线已启用；改用手动或系统自动模式会停用曲线。" : "曲线未启用。")
            }
            updateStatus()
            let enabled = LocalToggle(configuration.enabled) { [weak self] value in
                configuration.enabled = value
                if value && !configuration.isValid { configuration.enabled = false }
                FanCurveController.shared.save(configuration, fan: fan.id)
                self?.reload()
            }
            enabled.isEnabled = SMCHelper.shared.isInstalled && !self.sensors.isEmpty
            var rows: [NSView] = [PreferencesRow("启用曲线", component: enabled)]
            if !SMCHelper.shared.isInstalled {
                rows.append(localFeatureLabel("请先在传感器弹窗的风扇控制中安装并授权控制服务。"))
            }
            let selected = self.sensors.firstIndex(where: { $0.key == configuration.sensorKey }) ?? 0
            rows.append(PreferencesRow("温度传感器", component: LocalChoice(
                self.sensors.map { $0.name }, selected: selected
            ) { [weak self] index in
                guard let self, self.sensors.indices.contains(index) else { return }
                configuration.sensorKey = self.sensors[index].key
                FanCurveController.shared.save(configuration, fan: fan.id)
                updateStatus()
            }))
            for index in configuration.points.indices {
                let controls = NSStackView()
                controls.orientation = .horizontal
                controls.spacing = 8
                controls.addArrangedSubview(StepperInput(Int(configuration.points[index].temperature),
                    range: NSRange(location: 10, length: 100), unit: "°C") { value in
                    configuration.points[index].temperature = Double(value)
                    FanCurveController.shared.save(configuration, fan: fan.id)
                    updateStatus()
                })
                controls.addArrangedSubview(StepperInput(Int(configuration.points[index].percent),
                    range: NSRange(location: 0, length: 100), unit: "%") { value in
                    configuration.points[index].percent = Double(value)
                    FanCurveController.shared.save(configuration, fan: fan.id)
                    updateStatus()
                })
                rows.append(PreferencesRow("温度点 \(index+1)", component: controls))
            }
            rows.append(localFeatureLabel("转速百分比按风扇可调范围计算；温度位于两点之间时逐步调速。"))
            rows.append(status)
            self.addArrangedSubview(PreferencesSection(title: fan.name + " · 温度曲线", rows))
        }
    }
}
