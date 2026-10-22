import Cocoa

public final class HistoryWindow: NSWindowController {
    private static var windows: [String: HistoryWindow] = [:]
    private let module: String
    private let metricChoice = NSPopUpButton()
    private let rangeChoice = NSPopUpButton()
    private let chart = ArchiveChartView()
    private let status = NSTextField(wrappingLabelWithString: "")
    private var series: [HistorySeries] = []
    private var timer: Timer?
    private let ranges: [TimeInterval] = [3600, 86400, 7 * 86400, 28 * 86400]

    public static func show(module: String) {
        let controller = self.windows[module] ?? HistoryWindow(module: module)
        self.windows[module] = controller
        controller.refresh()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private init(module: String) {
        self.module = module
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "\(localizedString(module)) · 历史回看"
        window.minSize = NSSize(width: 620, height: 330)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        let body = NSView()
        window.contentView = body
        let controls = NSStackView()
        controls.orientation = .horizontal
        controls.spacing = 10
        controls.translatesAutoresizingMaskIntoConstraints = false
        self.metricChoice.target = self
        self.metricChoice.action = #selector(selectionChanged)
        self.rangeChoice.addItems(withTitles: ["1 小时", "24 小时", "7 天", "28 天"])
        self.rangeChoice.target = self
        self.rangeChoice.action = #selector(selectionChanged)
        let peaks = LocalToggle(true) { [weak self] value in
            self?.chart.showPeaks = value; self?.chart.needsDisplay = true
        }
        controls.addArrangedSubview(self.metricChoice)
        controls.addArrangedSubview(self.rangeChoice)
        controls.addArrangedSubview(peaks)
        controls.addArrangedSubview(NSTextField(labelWithString: "峰值"))
        controls.addArrangedSubview(NSView())
        controls.addArrangedSubview(LocalActionButton("导出 CSV") { [weak self] in self?.exportCSV() })
        self.chart.translatesAutoresizingMaskIntoConstraints = false
        self.status.translatesAutoresizingMaskIntoConstraints = false
        self.status.textColor = .secondaryLabelColor
        self.status.font = .systemFont(ofSize: 11)
        body.addSubview(controls)
        body.addSubview(self.chart)
        body.addSubview(self.status)
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 18),
            controls.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -18),
            controls.topAnchor.constraint(equalTo: body.topAnchor, constant: 16),
            self.chart.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 12),
            self.chart.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -12),
            self.chart.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 12),
            self.chart.bottomAnchor.constraint(equalTo: self.status.topAnchor, constant: -10),
            self.status.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 18),
            self.status.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -18),
            self.status.bottomAnchor.constraint(equalTo: body.bottomAnchor, constant: -14)
        ])
        window.center()
        self.timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            if self?.window?.isVisible == true { self?.refresh() }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { self.timer?.invalidate() }
    @objc private func selectionChanged() { self.refresh() }
    private func refresh() {
        let chosenID = self.series.indices.contains(self.metricChoice.indexOfSelectedItem) ?
            self.series[self.metricChoice.indexOfSelectedItem].id : nil
        self.series = HistoryArchive.shared.availableSeries(module: self.module)
        let titles = self.series.map { $0.name }
        if self.metricChoice.itemTitles != titles {
            self.metricChoice.removeAllItems()
            self.metricChoice.addItems(withTitles: titles)
            let preferred = chosenID ?? ["CPU": "usage", "RAM": "usage", "GPU": "usage", "Network": "download", "Disk": "read", "Battery": "level", "Sensors": "Average CPU"][self.module]
            if let preferred, let index = self.series.firstIndex(where: { $0.id == preferred }) {
                self.metricChoice.selectItem(at: index)
            }
        }
        let range = self.ranges[max(0, self.rangeChoice.indexOfSelectedItem)]
        let end = Date()
        self.chart.end = end.timeIntervalSince1970
        self.chart.range = range
        self.chart.resolution = HistoryArchive.resolution(for: range)
        if self.series.indices.contains(self.metricChoice.indexOfSelectedItem) {
            let series = self.series[self.metricChoice.indexOfSelectedItem]
            self.chart.unit = series.unit
            self.chart.samples = HistoryArchive.shared.samples(module: self.module, series: series.id, range: range, endingAt: end)
        } else {
            self.chart.samples = []
        }
        let interval = self.chart.resolution
        let time = self.chart.samples.first.map {
            DateFormatter.localizedString(from: Date(timeIntervalSince1970: $0.firstSample), dateStyle: .short, timeStyle: .short)
        }
        self.status.stringValue = HistoryArchive.shared.storageError ??
            (time.map { "本窗口最早记录：\($0)  ·  每 \(interval) 秒聚合均值与峰值；未采集的时段留空。" } ??
             "尚无历史数据。记录从此版本启动后开始，启用对应指标后会自动采集。")
        self.chart.needsDisplay = true
    }
    private func exportCSV() {
        guard self.series.indices.contains(self.metricChoice.indexOfSelectedItem) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(self.module)-history.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var text = "timestamp,mean,minimum,maximum,samples\n"
        let formatter = ISO8601DateFormatter()
        for bucket in self.chart.samples {
            text += "\(formatter.string(from: Date(timeIntervalSince1970: bucket.firstSample))),\(bucket.mean),\(bucket.minimum),\(bucket.maximum),\(bucket.count)\n"
        }
        do { try text.write(to: url, atomically: true, encoding: .utf8) }
        catch { NSAlert(error: error).runModal() }
    }
}

private final class ArchiveChartView: NSView {
    var samples: [HistoryBucket] = []
    var end: TimeInterval = Date().timeIntervalSince1970
    var range: TimeInterval = 3600
    var resolution: Int = 5
    var unit: String = "%"
    var showPeaks = true
    private var cursor: NSPoint?
    override var isFlipped: Bool { true }
    override func updateTrackingAreas() {
        self.trackingAreas.forEach(self.removeTrackingArea)
        self.addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited], owner: self))
        super.updateTrackingAreas()
    }
    override func mouseMoved(with event: NSEvent) {
        self.cursor = self.convert(event.locationInWindow, from: nil)
        self.needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) { self.cursor = nil; self.needsDisplay = true }
    private func formatted(_ value: Double) -> String {
        if self.unit == "B" || self.unit == "B/s" {
            let text = ByteCountFormatter.string(fromByteCount: Int64(min(Double(Int64.max-1), max(0, value))), countStyle: .binary)
            return text + (self.unit == "B/s" ? "/s" : "")
        }
        return String(format: self.unit == "%" ? "%.1f %@" : "%.2f %@", value, self.unit)
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        self.bounds.fill()
        let plot = self.bounds.insetBy(dx: 65, dy: 32)
        guard plot.width > 0, plot.height > 0 else { return }
        let maximum = max(1, self.samples.map { self.showPeaks ? $0.maximum : $0.mean }.max() ?? 1)
        let yMax = self.unit == "%" ? max(100, maximum) : maximum * 1.1
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor]
        for i in 0...4 {
            let y = plot.minY + plot.height * CGFloat(i) / 4
            let grid = NSBezierPath()
            grid.move(to: NSPoint(x: plot.minX, y: y))
            grid.line(to: NSPoint(x: plot.maxX, y: y))
            NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
            grid.stroke()
            self.formatted(yMax * Double(4-i) / 4).draw(at: NSPoint(x: 2, y: y - 6), withAttributes: attrs)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = self.range > 86400 ? "MM-dd HH:mm" : "HH:mm"
        for i in 0...4 {
            let timestamp = self.end - self.range + self.range * Double(i) / 4
            let label = formatter.string(from: Date(timeIntervalSince1970: timestamp))
            let x = plot.minX + plot.width * CGFloat(i) / 4
            label.draw(at: NSPoint(x: min(self.bounds.width - 70, max(0, x - 24)), y: plot.maxY + 10), withAttributes: attrs)
        }
        func point(_ bucket: HistoryBucket, peak: Bool) -> NSPoint {
            let x = plot.minX + CGFloat((bucket.timestamp - (self.end - self.range)) / self.range) * plot.width
            let value = peak ? bucket.maximum : bucket.mean
            return NSPoint(x: min(plot.maxX, max(plot.minX, x)), y: plot.maxY - CGFloat(value / yMax) * plot.height)
        }
        for peak in (self.showPeaks ? [true, false] : [false]) {
            let path = NSBezierPath()
            var last: HistoryBucket?
            for sample in self.samples {
                let p = point(sample, peak: peak)
                if let previous = last, sample.firstSample - previous.lastSample <= Double(self.resolution) * 2.5 {
                    path.line(to: p)
                } else {
                    path.move(to: p)
                    (peak ? NSColor.systemOrange : NSColor.controlAccentColor).setFill()
                    NSBezierPath(ovalIn: NSRect(x: p.x-1.5, y: p.y-1.5, width: 3, height: 3)).fill()
                }
                last = sample
            }
            (peak ? NSColor.systemOrange.withAlphaComponent(0.6) : NSColor.controlAccentColor).setStroke()
            path.lineWidth = peak ? 1 : 1.8
            path.stroke()
        }
        if self.samples.isEmpty {
            "此时间范围暂无记录".draw(at: NSPoint(x: plot.midX - 58, y: plot.midY), withAttributes: attrs)
        }
        if let cursor = self.cursor, plot.contains(cursor),
           let closest = self.samples.min(by: { abs(point($0, peak: false).x - cursor.x) < abs(point($1, peak: false).x - cursor.x) }) {
            let p = point(closest, peak: false)
            guard abs(cursor.x-p.x) < max(12, plot.width * CGFloat(self.resolution) / CGFloat(self.range) * 2) else { return }
            let line = NSBezierPath()
            line.move(to: NSPoint(x: p.x, y: plot.minY))
            line.line(to: NSPoint(x: p.x, y: plot.maxY))
            NSColor.secondaryLabelColor.setStroke()
            line.stroke()
            formatter.dateFormat = "MM-dd HH:mm:ss"
            let text = "\(formatter.string(from: Date(timeIntervalSince1970: closest.firstSample)))  均值 \(self.formatted(closest.mean))  峰值 \(self.formatted(closest.maximum))"
            text.draw(at: NSPoint(x: plot.minX, y: 6), withAttributes: attrs)
        }
    }
}
