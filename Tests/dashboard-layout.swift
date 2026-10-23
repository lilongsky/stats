// Compile with the actual Stats/Views/Dashboard.swift and matching Kit. Every
// displayed value is synthetic; no SystemKit instance or real serial is read.
import Cocoa
import Kit

private struct DashboardCheckError: LocalizedError {
    let message: String
    var errorDescription: String? { self.message }
}

private final class DashboardChecks {
    var count = 0
    var failures = 0

    func check(_ result: Bool, _ message: String) {
        self.count += 1
        if !result {
            self.failures += 1
            print("FAIL: " + message)
        }
    }
}

private func dashboardDescendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(dashboardDescendants)
}

private func dashboardView<T: NSView>(_ root: NSView, _ id: String, _ type: T.Type) throws -> T {
    guard let value = dashboardDescendants(root).first(where: { $0.identifier?.rawValue == id }) as? T else {
        throw DashboardCheckError(message: "Missing production Dashboard view: " + id)
    }
    return value
}

private func dashboardOverlaps(_ first: NSRect, _ second: NSRect) -> Bool {
    let rect = first.intersection(second)
    return !rect.isNull && rect.width > 0.75 && rect.height > 0.75
}

// AppKit aligns native text fields using their alignment rects. Their raw
// frames include two points of transparent horizontal padding on each side.
private func dashboardAlignmentFrame(_ view: NSView, in target: NSView) -> NSRect {
    guard let parent = view.superview else { return view.convert(view.bounds, to: target) }
    return parent.convert(view.alignmentRect(forFrame: view.frame), to: target)
}

private final class DashboardPreviewHost: NSView {
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(rect: self.bounds).fill()
    }
}

private final class DashboardFixture {
    let width: CGFloat
    let dashboard: Dashboard
    let window: NSWindow
    let host: DashboardPreviewHost

    init(width: CGFloat, constructBeforeHost: Bool, make: () -> Dashboard) {
        let early = constructBeforeHost ? make() : nil
        self.width = width
        let host = DashboardPreviewHost(frame: NSRect(x: 0, y: 0, width: width, height: 560))
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        self.window = window
        self.host = host
        window.isReleasedWhenClosed = false
        window.contentView = host
        self.dashboard = early ?? make()
        self.attach()
    }

    private func attach() {
        self.host.addSubview(self.dashboard)
        NSLayoutConstraint.activate([
            self.dashboard.widthAnchor.constraint(equalToConstant: self.width),
            self.dashboard.leadingAnchor.constraint(equalTo: self.host.leadingAnchor),
            self.dashboard.trailingAnchor.constraint(equalTo: self.host.trailingAnchor),
            self.dashboard.topAnchor.constraint(equalTo: self.host.topAnchor),
            self.dashboard.bottomAnchor.constraint(equalTo: self.host.bottomAnchor)
        ])
        self.layout()
    }

    func remount() {
        self.dashboard.removeFromSuperview()
        self.attach()
    }

    func layout() {
        self.host.layoutSubtreeIfNeeded()
        self.dashboard.layoutSubtreeIfNeeded()
    }

    func scrollView() throws -> NSScrollView {
        let wrapper = try dashboardView(self.dashboard, "dashboard-scroll", NSView.self)
        guard let scroll = dashboardDescendants(wrapper).compactMap({ $0 as? NSScrollView }).first else {
            throw DashboardCheckError(message: "Dashboard has no real native scroll view")
        }
        return scroll
    }

    func verify(_ checks: DashboardChecks, expected: [String: String], stage: String) throws {
        self.layout()
        let prefix = "Dashboard \(Int(self.width))pt \(stage): "
        let scroll = try self.scrollView()
        let form = try dashboardView(self.dashboard, "dashboard-form", NSStackView.self)
        let scrollRect = scroll.convert(scroll.bounds, to: self.dashboard)
        checks.check(abs(self.host.bounds.width - self.width) < 0.75 &&
                     abs(self.dashboard.bounds.width - self.width) < 0.75 &&
                     abs(scrollRect.minX) < 0.75 && abs(scrollRect.maxX - self.width) < 0.75,
                     prefix + "the real view and native scroll viewport retain the requested width")
        checks.check(!scroll.hasHorizontalScroller && scroll.hasVerticalScroller &&
                     abs(form.bounds.width - scroll.contentView.bounds.width) < 0.75,
                     prefix + "the scroll document follows its viewport without horizontal scrolling")

        let components = ["dashboard-header", "dashboard-hardware", "dashboard-device"].map {
            try? dashboardView(self.dashboard, $0, NSView.self)
        }.compactMap { $0 }
        let frames = components.map { $0.convert($0.bounds, to: form) }
        checks.check(components.count == 3 && frames.allSatisfy {
            abs($0.minX - form.edgeInsets.left) < 0.75 &&
                abs($0.maxX - form.bounds.maxX + form.edgeInsets.right) < 0.75 && $0.height > 0
        }, prefix + "the header and both information groups share their document margins")
        checks.check(zip(frames, frames.dropFirst()).allSatisfy { !dashboardOverlaps($0.0, $0.1) },
                     prefix + "the header and information groups do not overlap")

        let labels = dashboardDescendants(self.dashboard).compactMap { $0 as? NSTextField }
            .filter { $0.identifier?.rawValue.hasPrefix("dashboard-label-") == true }
        checks.check(labels.count == expected.count,
                     prefix + "all expected production information rows are present")
        var labelEdges: [CGFloat] = []
        var valueEdges: [CGFloat] = []
        var rowFrames: [NSRect] = []
        for key in expected.keys.sorted() {
            let row = try dashboardView(self.dashboard, "dashboard-row-" + key, NSView.self)
            let label = try dashboardView(self.dashboard, "dashboard-label-" + key, NSTextField.self)
            let value = try dashboardView(self.dashboard, "dashboard-value-" + key, NSTextField.self)
            let labelRect = dashboardAlignmentFrame(label, in: row)
            let valueRect = dashboardAlignmentFrame(value, in: row)
            let font = label.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let natural = ceil((label.stringValue as NSString).size(withAttributes: [.font: font]).width)
            checks.check(label.maximumNumberOfLines == 1 && label.cell?.wraps == false &&
                         labelRect.width + 0.75 >= natural && !label.bounds.isEmpty,
                         prefix + key + " label remains a complete horizontal line")
            let textSize = value.cell?.cellSize(forBounds: NSRect(x: 0, y: 0,
                width: value.bounds.width, height: 10000)) ?? value.intrinsicContentSize
            checks.check(value.stringValue == expected[key] && value.isSelectable &&
                         value.maximumNumberOfLines == 0 && value.lineBreakMode == .byWordWrapping &&
                         value.bounds.width > 0 && value.bounds.height + 2 >= textSize.height,
                         prefix + key + " value remains complete and wraps to its actual available width")
            checks.check(!dashboardOverlaps(labelRect, valueRect) && valueRect.minX > labelRect.maxX &&
                         row.bounds.insetBy(dx: -1, dy: -1).contains(labelRect) &&
                         row.bounds.insetBy(dx: -1, dy: -1).contains(valueRect),
                         prefix + key + " label and value fit inside their row without overlap" +
                         " [row=\(row.bounds), label=\(labelRect), value=\(valueRect)]")
            labelEdges.append(dashboardAlignmentFrame(label, in: form).minX)
            valueEdges.append(dashboardAlignmentFrame(value, in: form).minX)
            rowFrames.append(row.convert(row.bounds, to: form))
        }
        checks.check(labelEdges.allSatisfy { abs($0 - labelEdges[0]) < 0.75 } &&
                     valueEdges.allSatisfy { abs($0 - valueEdges[0]) < 0.75 },
                     prefix + "labels and values each share one consistent leading edge across both groups")
        var overlap = false
        for first in rowFrames.indices {
            for second in rowFrames.indices where second > first {
                if dashboardOverlaps(rowFrames[first], rowFrames[second]) { overlap = true }
            }
        }
        checks.check(!overlap, prefix + "multiline values do not overlap adjacent rows")

        let header = try dashboardView(self.dashboard, "dashboard-header", NSView.self)
        for id in ["dashboard-device-name", "dashboard-operating-system"] {
            let field = try dashboardView(self.dashboard, id, NSTextField.self)
            let size = field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0,
                width: field.bounds.width, height: 10000)) ?? field.intrinsicContentSize
            checks.check(field.bounds.width > 0 && field.bounds.height + 2 >= size.height &&
                         header.bounds.insetBy(dx: -1, dy: -1).contains(dashboardAlignmentFrame(field, in: header)),
                         prefix + id + " stays fully readable inside the header" +
                         " [header=\(header.bounds), field=\(field.convert(field.bounds, to: header)), needed=\(size.height)]")
        }
    }

    func scrollToBottom(_ checks: DashboardChecks, stage: String) throws {
        let scroll = try self.scrollView()
        guard let document = scroll.documentView else {
            throw DashboardCheckError(message: "Dashboard scroll document is missing")
        }
        let start = document.visibleRect
        let maximum = max(0, document.bounds.height - scroll.contentView.bounds.height)
        checks.check(maximum > 0, stage + ": long synthetic content requires native vertical scrolling")
        scroll.contentView.scroll(to: NSPoint(x: 0, y: maximum))
        scroll.reflectScrolledClipView(scroll.contentView)
        self.layout()
        let end = document.visibleRect
        let uptime = try dashboardView(self.dashboard, "dashboard-value-uptime", NSTextField.self)
        checks.check(end.minY > start.minY &&
                     uptime.convert(uptime.bounds, to: document).intersects(end),
                     stage + ": native scrolling reaches the final uptime row")
    }

    func scrollToTop() throws {
        let scroll = try self.scrollView()
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        self.layout()
    }

    func save(appearance: NSAppearance, name: String, output: URL, path: String) throws {
        self.layout()
        var bitmap: NSBitmapImageRep?
        appearance.performAsCurrentDrawingAppearance {
            for view in dashboardDescendants(self.host) {
                view.needsDisplay = true
                if view.wantsLayer { view.updateLayer() }
            }
            bitmap = self.host.bitmapImageRepForCachingDisplay(in: self.host.bounds)
            if let bitmap { self.host.cacheDisplay(in: self.host.bounds, to: bitmap) }
        }
        guard let data = bitmap?.representation(using: .png, properties: [:]) else {
            throw DashboardCheckError(message: "Could not render synthetic production Dashboard")
        }
        let url = output.appendingPathComponent("dashboard-\(name)-\(Int(self.width))-\(path).png")
        try data.write(to: url, options: .atomic)
        print("Synthetic production Dashboard PNG: " + url.path)
    }
}

@main
private struct DashboardLayoutChecks {
    static func main() {
        do { try self.run() }
        catch {
            print("Dashboard checks failed: " + error.localizedDescription)
            exit(1)
        }
    }

    private static func run() throws {
        setbuf(stdout, nil)
        let process = ProcessInfo.processInfo.processName
        guard let domain = Bundle.main.bundleIdentifier,
              domain.hasPrefix("local.stats.dashboard-checks."), process.hasPrefix("stats-dashboard-checks-") else {
            throw DashboardCheckError(message: "Dashboard checks require a distinct randomly named helper app")
        }
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        guard let index = CommandLine.arguments.firstIndex(of: "--output-dir"),
              CommandLine.arguments.indices.contains(index + 1) else {
            throw DashboardCheckError(message: "--output-dir is required")
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        print("Dashboard checks locale: \(Locale.current.identifier); languages: \(Locale.preferredLanguages)")
        print("Dashboard helper localizations: \(Bundle.main.preferredLocalizations)")
        let image = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: "Synthetic device") ?? NSImage(size: NSSize(width: 72, height: 72))
        let data = Dashboard.DisplayData(
            deviceName: "Synthetic Mac with a deliberately long device model name · 合成测试设备名称",
            modelIdentifier: "SYNTHETIC-MODEL-ABCDEFGHIJKLMNOPQRSTUVWXYZ-1234567890",
            productionYear: "2026",
            serialNumber: "SYNTHETIC-DO-NOT-READ-A-REAL-SERIAL-ABCDEFGHIJKLMNOPQRSTUVWXYZ",
            operatingSystem: "macOS Synthetic Release with a deliberately long product name · 测试系统名称",
            operatingSystemBuild: "SYNTHETIC-BUILD-TEST-ONLY",
            processor: "Synthetic Processor with a deliberately long name\n128 cores, 256 threads\n64 efficiency cores and 64 performance cores",
            memory: "128 GB synthetic unified memory with a long module description\nSlot 1 / channel 2 · 合成内存规格",
            graphics: "Synthetic GPU with a long localized product name (128 cores, 64 GB)\nSecond Synthetic Graphics Device with another long description",
            disks: "Synthetic Internal Storage with a long device name (8 TB)\nSynthetic External Backup Array with a long device name (16 TB)",
            displays: "Synthetic External Display with a long name (32 inches)\n7680 × 4320, 144 Hz\nSecond Synthetic Display with a long name, 6016 × 3384, 120 Hz",
            uptime: "123 days, 22 hours, 59 minutes · 合成运行时间",
            image: image)
        let checks = DashboardChecks()
        for width: CGFloat in [420, 540, 760] {
            for beforeHost in [true, false] {
                for (theme, name) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
                    guard let appearance = NSAppearance(named: name) else { continue }
                    app.appearance = appearance
                    var refreshes = 0
                    var refreshed = "124 days, 1 hour · refreshed synthetic uptime"
                    let fixture = DashboardFixture(width: width, constructBeforeHost: beforeHost) {
                        Dashboard(data: data, refreshUptime: { refreshes += 1; return refreshed })
                    }
                    defer { fixture.window.close() }
                    fixture.window.appearance = appearance
                    fixture.host.appearance = appearance
                    let path = beforeHost ? "view-before-host" : "host-before-view"
                    var expected = ["processor": data.processor, "memory": data.memory, "graphics": data.graphics,
                                    "disks": data.disks, "displays": data.displays, "model": data.modelIdentifier,
                                    "year": data.productionYear, "serial": data.serialNumber, "uptime": data.uptime]
                    try fixture.verify(checks, expected: expected, stage: "\(theme), \(path), initial")
                    let title = try dashboardView(fixture.dashboard, "dashboard-device-name", NSTextField.self)
                    let system = try dashboardView(fixture.dashboard, "dashboard-operating-system", NSTextField.self)
                    checks.check(title.stringValue == data.deviceName && system.stringValue == data.operatingSystem &&
                                 system.toolTip == data.operatingSystemBuild,
                                 "the actual header preserves all injected formatted device and system values")
                    checks.check(refreshes == 0, "constructing the injected Dashboard does not invoke its refresh provider")
                    NotificationCenter.default.post(name: .openModuleSettings, object: nil, userInfo: ["module": "CPU"])
                    checks.check(refreshes == 0, "opening a different module does not refresh this Dashboard")
                    NotificationCenter.default.post(name: .openModuleSettings, object: nil, userInfo: ["module": "Dashboard"])
                    expected["uptime"] = refreshed
                    checks.check(refreshes == 1, "opening Dashboard invokes only its injected uptime provider")
                    try fixture.verify(checks, expected: expected, stage: "\(theme), \(path), refreshed")
                    refreshed = "125 days, 2 hours, 30 minutes · a longer refreshed synthetic uptime description"
                    NotificationCenter.default.post(name: .toggleSettings, object: nil, userInfo: ["module": "Combined modules"])
                    expected["uptime"] = refreshed
                    checks.check(refreshes == 2, "the real settings notification refreshes the injected uptime again")
                    fixture.remount()
                    try fixture.verify(checks, expected: expected, stage: "\(theme), \(path), remounted")
                    try fixture.scrollToTop()
                    try fixture.save(appearance: appearance, name: theme, output: output, path: path + "-top")
                    try fixture.scrollToBottom(checks, stage: "\(Int(width))pt \(theme), \(path)")
                    try fixture.save(appearance: appearance, name: theme, output: output, path: path + "-bottom")
                }
            }
        }
        let noProvider = DashboardFixture(width: 540, constructBeforeHost: true) { Dashboard(data: data) }
        defer { noProvider.window.close() }
        NotificationCenter.default.post(name: .toggleSettings, object: nil, userInfo: ["module": "Dashboard"])
        let uptime = try dashboardView(noProvider.dashboard, "dashboard-value-uptime", NSTextField.self)
        checks.check(uptime.stringValue == data.uptime, "a synthetic Dashboard without an uptime provider leaves its injected value intact")
        print("Dashboard AppKit checks: \(checks.count) checks, \(checks.failures) failures")
        if checks.failures > 0 { throw DashboardCheckError(message: "Dashboard layout checks failed") }
    }
}
