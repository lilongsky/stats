// Appended to the production Battery value records and popup. No readers or
// application module are instantiated, and the probe owns a separate domain.
private extension Popup {
    func cachedSample(_ value: Battery_Usage) -> Bool {
        self.usageCache.value?.cycles == value.cycles
    }

    func hasProcessRows(_ count: Int) -> Bool {
        self.processesView === self.popupSection("processes") && (self.processes?.count ?? 0) == count
    }

    func verifyLayout(_ label: String, connected: Bool, _ check: (Bool, String) -> Void) {
        let expectedHeights: [String: CGFloat] = [
            "dashboard": 160, "details": 30 + 2 * 22,
            "battery": 30 + 52 + 6 * 22, "adapter": connected ? 30 + 4 * 22 : 0,
            "processes": self.processesHeight
        ]
        let visible = self.arrangedSubviews.filter { !$0.isHidden }
        let expected = visible.reduce(CGFloat(0)) {
            $0 + (expectedHeights[String(($1.identifier?.rawValue ?? "").dropFirst("popup-section:".count))] ?? 0)
        }
        func verify(_ condition: Bool, _ message: String) { check(condition, "\(label): \(message)") }
        verify(self.arrangedSubviews.count == 5 && self.arrangedSubviews.allSatisfy {
            $0.identifier?.rawValue.hasPrefix("popup-section:") == true
        }, "every section, including the adapter, participates in customization exactly once")
        verify(abs(self.frame.height - expected) < 0.5, "document height includes every visible section")
        verify(visible.allSatisfy {
            let id = String(($0.identifier?.rawValue ?? "").dropFirst("popup-section:".count))
            return abs($0.frame.height - (expectedHeights[id] ?? -1)) < 0.5
        }, "sections keep their full content heights")
        let byPosition = visible.filter { $0.frame.height > 0 }.sorted { $0.frame.minY < $1.frame.minY }
        verify(zip(byPosition, byPosition.dropFirst()).allSatisfy { abs($0.frame.maxY - $1.frame.minY) < 0.5 },
               "adjacent sections have no gaps or overlaps")
        verify(byPosition.allSatisfy { $0.frame.minY >= -0.5 && $0.frame.maxY <= self.bounds.maxY + 0.5 },
               "every section fits inside the scroll document")
        verify(abs((byPosition.last?.frame.maxY ?? 0) - self.bounds.maxY) < 0.5,
               "no content is stranded above the registered sections")
        verify(abs(self.barView.frame.height - 10) < 0.5, "health bar keeps its own ten-point row")
        if let battery = self.popupSection("battery"), !battery.isHidden {
            let bounds = battery.convert(battery.bounds, to: self).insetBy(dx: -0.5, dy: -0.5)
            let content: [NSView] = [self.barView] + [self.maxCapacityField, self.designedCapacityField,
                self.powerField, self.currentField, self.voltageField, self.healthField,
                self.cyclesField, self.temperatureField].compactMap { $0 }
            verify(content.allSatisfy { bounds.contains($0.convert($0.bounds, to: self)) },
                   "all health content stays inside its own section")
            let fields = [self.powerField, self.currentField, self.voltageField, self.healthField,
                          self.cyclesField, self.temperatureField].compactMap { $0 }
            let bar = self.barView.convert(self.barView.bounds, to: self)
            verify(fields.allSatisfy { !bar.intersects($0.convert($0.bounds, to: self)) },
                   "health bar never covers a battery detail row")
            if let details = self.popupSection("details"), !details.isHidden {
                verify(!bar.intersects(details.convert(details.bounds, to: self)),
                       "health bar never covers the source or time rows")
            }
        }
        if connected {
            verify(self.adapterView != nil && self.adapterView === self.popupSection("adapter"),
                   "connected adapter uses its registered section")
            if let adapter = self.adapterView, !adapter.isHidden {
                let bounds = adapter.convert(adapter.bounds, to: self).insetBy(dx: -0.5, dy: -0.5)
                let fields: [NSView] = [self.chargingStateField, self.adapterPowerField,
                                       self.adapterCurrentField, self.adapterVoltageField].compactMap { $0 }
                verify(fields.count == 4 && fields.allSatisfy { bounds.contains($0.convert($0.bounds, to: self)) },
                       "all four adapter values remain inside the adapter section")
            }
        } else {
            verify(self.adapterView == nil && self.popupSection("adapter")?.frame.height == 0,
                   "battery power leaves a configurable zero-height adapter slot")
        }
    }
}

@main
private struct BatteryPopupLayoutChecks {
    static func main() {
        setbuf(stdout, nil)
        let domain = Bundle.main.bundleIdentifier ?? ""
        guard domain.hasPrefix("local.statscompact.battery-popup-checks.") else {
            fatalError("Battery checks require a dedicated probe bundle and preference domain")
        }
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let language = CommandLine.arguments[3]
        UserDefaults.standard.set([language], forKey: "AppleLanguages")
        UserDefaults.standard.set(language == "en" ? "en_US" : "zh_CN", forKey: "AppleLocale")
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let assets = URL(fileURLWithPath: CommandLine.arguments[1])
        var deviceImages: [NSImage] = []
        for directory in try! FileManager.default.contentsOfDirectory(at: assets, includingPropertiesForKeys: nil)
            where directory.pathExtension == "imageset" {
            if let file = try! FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .first(where: { ["png", "pdf"].contains($0.pathExtension) }),
               let image = NSImage(contentsOf: file) {
                image.setName(NSImage.Name(directory.deletingPathExtension().lastPathComponent))
                deviceImages.append(image)
            }
        }
        var checks = 0
        var failures = 0
        func check(_ condition: Bool, _ label: String) {
            checks += 1
            if !condition { failures += 1; print("FAIL: \(label)") }
        }
        func awaitMainUpdate(_ label: String, until ready: () -> Bool) {
            let deadline = Date().addingTimeInterval(3)
            let marker = DispatchGroup()
            marker.enter()
            DispatchQueue.main.async { marker.leave() }
            while Date() < deadline {
                if marker.wait(timeout: .now()) == .success && ready() { return }
                _ = RunLoop.current.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.01)))
            }
            check(false, "\(label): queued update completed")
        }
        Store.shared.set(key: "Battery_processes", value: 8)
        Store.shared.set(key: "Battery_popup_sectionOrder", value: [String]())
        Store.shared.set(key: "Battery_popup_hiddenSections", value: [String]())
        let popup = Popup(.battery)
        let host = PopupWindow(title: "Battery", module: .battery, view: popup, visibilityCallback: { _ in })
        var connected = false
        var sampleID = 0
        func layout(_ label: String) {
            popup.applySectionLayout()
            host.contentView?.layoutSubtreeIfNeeded()
            popup.layoutSubtreeIfNeeded()
            popup.verifyLayout(label, connected: connected, check)
        }
        func update(_ isConnected: Bool, charged: Bool = false, charging: Bool = false) {
            sampleID += 1
            var sample = Battery_Usage()
            sample.powerSource = isConnected ? "AC Power" : "Battery Power"
            sample.isBatteryPowered = !isConnected
            sample.isCharged = charged
            sample.isCharging = charging
            sample.level = charged ? 1 : 0.73
            sample.cycles = sampleID
            sample.health = 88
            sample.designedCapacity = 4561
            sample.maxCapacity = 4013
            sample.currentCapacity = 4009
            sample.current = isConnected ? 0 : -666
            sample.voltage = 12.89
            sample.temperature = 38
            sample.batteryPower = 1.01
            sample.ACwatts = 30
            sample.adapterPower = 13.33
            sample.adapterVoltage = 20
            sample.timeToEmpty = 200
            sample.timeToCharge = 30
            popup.usageCallback(sample)
            awaitMainUpdate("usage sample \(sampleID)") { popup.cachedSample(sample) }
            connected = isConnected
            popup.appear()
        }
        func snapshot(_ name: String) {
            let path = CommandLine.arguments[2]
            guard !path.isEmpty else { return }
            let directory = URL(fileURLWithPath: path)
            try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard let bitmap = popup.bitmapImageRepForCachingDisplay(in: popup.bounds) else { return }
            popup.cacheDisplay(in: popup.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name + ".png"))
        }
        layout("before first sample")
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            popup.appearance = NSAppearance(named: appearance)
            update(false)
            layout("\(appearance.rawValue) battery power")
            update(true, charged: true)
            layout("\(appearance.rawValue) connected and full")
            check(popup.orderedSectionIDs() == ["dashboard", "details", "battery", "adapter", "processes"],
                  "adapter keeps its default position between battery health and processes")
            snapshot("battery-\(language)-\(appearance.rawValue)")
            for _ in 0..<5 { popup.appear(); popup.disappear() }
            layout("\(appearance.rawValue) cached reopen")
            update(true, charging: true)
            layout("\(appearance.rawValue) charging")
            update(false)
            layout("\(appearance.rawValue) unplugged")
            update(true, charged: true)
            layout("\(appearance.rawValue) reconnected")
        }
        let custom = ["processes", "adapter", "details", "dashboard", "battery"]
        Store.shared.set(key: "Battery_popup_sectionOrder", value: custom)
        layout("custom order")
        check(popup.arrangedSubviews.compactMap { $0.identifier?.rawValue } == custom.map { "popup-section:" + $0 },
              "saved order includes the adapter and is applied to every section")
        Store.shared.set(key: "Battery_popup_hiddenSections", value: ["battery", "adapter"])
        layout("hidden health and adapter")
        update(false)
        layout("hidden unplugged")
        update(true)
        layout("hidden reconnected")
        check(popup.popupSection("adapter")?.isHidden == true, "adapter replacement preserves its saved hidden state")
        Store.shared.set(key: "Battery_popup_hiddenSections", value: [String]())
        layout("restored sections")
        for count in [0, 3, 13, 8] {
            Store.shared.set(key: "Battery_processes", value: count)
            popup.numberOfProcessesUpdated()
            awaitMainUpdate("\(count) processes") { popup.hasProcessRows(count) }
            layout("\(count) process rows")
        }
        print("Battery popup AppKit checks (\(language)): \(checks) checks, \(failures) failures")
        if failures > 0 { exit(1) }
        withExtendedLifetime((host, deviceImages)) {}
    }
}
