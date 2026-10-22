// Appended to the real CPU popup source so dynamic frequency and process
// callbacks are exercised without exporting test-only production APIs.
private extension Popup {
    func verifyLayout(_ label: String, _ check: (Bool, String) -> Void) {
        let expectedHeights: [String: CGFloat] = [
            "dashboard": self.dashboardHeight, "history": self.chartHeight,
            "details": self.detailsHeight, "average": self.averageHeight,
            "frequency": self.coresFreqField == nil ? 0 : self.frequencyHeight, "processes": self.processesHeight
        ]
        let visible = self.arrangedSubviews.filter { !$0.isHidden }
        let expected = visible.reduce(CGFloat(0)) {
            $0 + (expectedHeights[String(($1.identifier?.rawValue ?? "").dropFirst("popup-section:".count))] ?? 0)
        }
        check(abs(self.frame.height - expected) < 0.5, "\(label): document height includes every visible section")
        check(self.arrangedSubviews.allSatisfy { $0.identifier?.rawValue.hasPrefix("popup-section:") == true },
              "\(label): every CPU section participates in customization")
        check(visible.allSatisfy {
            let id = String(($0.identifier?.rawValue ?? "").dropFirst("popup-section:".count))
            return abs($0.frame.height - (expectedHeights[id] ?? -1)) < 0.5
        }, "\(label): sections retain their content heights")
        let byPosition = visible.filter { $0.frame.height > 0 }.sorted { $0.frame.minY < $1.frame.minY }
        check(zip(byPosition, byPosition.dropFirst()).allSatisfy { abs($0.frame.maxY - $1.frame.minY) < 0.5 },
              "\(label): adjacent sections have no gaps or overlaps")
        check(byPosition.allSatisfy { $0.frame.minY >= -0.5 && $0.frame.maxY <= self.bounds.maxY + 0.5 },
              "\(label): all sections fit inside the scroll document")
        check(abs((byPosition.last?.frame.maxY ?? 0) - self.bounds.maxY) < 0.5,
              "\(label): no blank area above the content")
    }
}

@main
private struct CPUPopupLayoutChecks {
    static func main() {
        setbuf(stdout, nil)
        print("Starting isolated CPU popup checks")
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let domain = ProcessInfo.processInfo.processName
        guard Bundle.main.bundleIdentifier == nil, domain.hasPrefix("stats-cpu-popup-checks-") else {
            fatalError("CPU layout checks require an isolated test executable")
        }
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        // SystemKit resolves device artwork through NSImage's name registry.
        // A command-line test has no compiled asset catalog, so register the
        // actual upstream assets before constructing the real CPU popup.
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
        func drain() { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        Store.shared.set(key: "CPU_processes", value: 10)
        print("Creating the production CPU popup")
        let popup = Popup(.CPU)
        print("Creating the hidden popup window")
        let host = PopupWindow(title: "CPU", module: .CPU, view: popup, visibilityCallback: { _ in })
        func layout(_ label: String) {
            print("Checking \(label)")
            popup.applySectionLayout()
            host.contentView?.layoutSubtreeIfNeeded()
            popup.layoutSubtreeIfNeeded()
            popup.verifyLayout(label, check)
        }
        layout("before frequency")
        check(popup.popupSection("frequency")?.frame.height == 0,
              "frequency is configurable before telemetry arrives without reserving empty space")
        popup.frequencyCallback(CPU_Frequency(value: 2301, eCore: 2495, pCore: 2009))
        drain()
        layout("first frequency sample")
        check(popup.popupSection("frequency") != nil, "frequency registers as a configurable section")
        let defaultOrder = ["dashboard", "history", "details", "average", "frequency", "processes"]
        check(popup.orderedSectionIDs() == defaultOrder, "frequency keeps its default position before processes")
        for _ in 0..<20 { popup.appear(); popup.disappear() }
        layout("repeated cached replay")
        check(popup.arrangedSubviews.count == 6, "reopening never duplicates the frequency section")

        let savedOrder = ["processes", "average", "details", "history", "dashboard", "frequency"]
        Store.shared.set(key: "CPU_popup_sectionOrder", value: savedOrder)
        layout("custom order")
        check(popup.arrangedSubviews.compactMap { $0.identifier?.rawValue } == savedOrder.map { "popup-section:" + $0 },
              "saved ordering applies to every CPU section")
        Store.shared.set(key: "CPU_popup_hiddenSections", value: ["frequency", "history", "processes"])
        layout("hidden sections")
        for _ in 0..<5 { popup.appear() }
        layout("cached replay while hidden")
        Store.shared.set(key: "CPU_popup_hiddenSections", value: [String]())
        layout("restored sections")

        for count in [0, 3, 20, 8, 10] {
            Store.shared.set(key: "CPU_processes", value: count)
            popup.numberOfProcessesUpdated()
            drain()
            layout("\(count) process rows")
            check(popup.arrangedSubviews.count == 6, "replacing processes keeps exactly six sections")
        }

        // A saved order created before frequency becomes available must survive.
        Store.shared.set(key: "CPU_popup_sectionOrder", value: ["processes", "dashboard", "history", "details", "average"])
        let restored = Popup(.CPU)
        let secondHost = PopupWindow(title: "CPU", module: .CPU, view: restored, visibilityCallback: { _ in })
        restored.frequencyCallback(CPU_Frequency(value: 2100, eCore: 2200, pCore: 1950))
        drain()
        restored.applySectionLayout()
        secondHost.contentView?.layoutSubtreeIfNeeded()
        restored.layoutSubtreeIfNeeded()
        restored.verifyLayout("saved layout after late frequency arrival", check)
        check(Array(restored.orderedSectionIDs().prefix(5)) == ["processes", "dashboard", "history", "details", "average"],
              "late frequency arrival preserves the existing saved order")
        print("CPU popup AppKit checks: \(checks) checks, \(failures) failures")
        if failures > 0 { exit(1) }
        withExtendedLifetime((host, secondHost, deviceImages)) {}
    }
}
