// Compile with the actual Clock sources and matching Kit. No main module,
// reader, NTP operation, production preferences or global time setting is used.
import Cocoa
import Kit

private struct ClockSettingsError: LocalizedError {
    let message: String
    var errorDescription: String? { self.message }
}

private final class ClockChecks {
    var count = 0
    var failures = 0
    func check(_ result: Bool, _ message: String) {
        self.count += 1
        if !result { self.failures += 1; print("FAIL: " + message) }
    }
}

private func clockDescendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(clockDescendants)
}

private func clockAlignmentFrame(_ view: NSView, in target: NSView) -> NSRect {
    guard let parent = view.superview else { return view.convert(view.bounds, to: target) }
    return parent.convert(view.alignmentRect(forFrame: view.frame), to: target)
}

private func clockOverlaps(_ first: NSRect, _ second: NSRect) -> Bool {
    let rect = first.intersection(second)
    return !rect.isNull && rect.width > 0.75 && rect.height > 0.75
}

private final class ClockPreviewHost: NSView {
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(rect: self.bounds).fill()
    }
}

private final class ClockSettingsFixture {
    let settings: Settings
    let host: ClockPreviewHost
    let window: NSWindow
    let scroll: NSScrollView
    let table: NSTableView
    private var widthConstraint: NSLayoutConstraint
    private var heightConstraint: NSLayoutConstraint?

    init(width: CGFloat, records: [Clock_t]) throws {
        Store.shared.set(key: "Clock_list", value: try JSONEncoder().encode(records))
        Store.shared.set(key: "Clock_ntpSync", value: false)
        let settings = Settings(.clock)
        let host = ClockPreviewHost(frame: NSRect(x: 0, y: 0, width: width + 48, height: 400))
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.addSubview(settings)
        guard let scroll = clockDescendants(settings).first(where: {
            $0.identifier?.rawValue == "clock-settings-scroll"
        }) as? NSScrollView, let table = scroll.documentView as? NSTableView else {
            throw ClockSettingsError(message: "Missing actual Clock settings table")
        }
        self.settings = settings
        self.host = host
        self.window = window
        self.scroll = scroll
        self.table = table
        self.widthConstraint = settings.widthAnchor.constraint(equalToConstant: width)
        NSLayoutConstraint.activate([
            self.widthConstraint,
            settings.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 24),
            settings.topAnchor.constraint(equalTo: host.topAnchor, constant: 24)
        ])
        settings.load(widgets: [])
        self.layout(width: width)
    }

    func layout(width: CGFloat) {
        self.widthConstraint.constant = width
        self.heightConstraint?.isActive = false
        self.host.layoutSubtreeIfNeeded()
        self.settings.layoutSubtreeIfNeeded()
        let height = max(1, ceil(self.settings.fittingSize.height))
        self.heightConstraint = self.settings.heightAnchor.constraint(equalToConstant: height)
        self.heightConstraint?.isActive = true
        self.window.setContentSize(NSSize(width: width + 48, height: height + 48))
        self.host.layoutSubtreeIfNeeded()
        self.scroll.tile()
        self.table.layoutSubtreeIfNeeded()
    }

    func control<T: NSControl>(_ type: T.Type, column: Int, row: Int) throws -> T {
        guard let cell = self.table.view(atColumn: column, row: row, makeIfNecessary: true) else {
            throw ClockSettingsError(message: "Missing native Clock table cell")
        }
        cell.layoutSubtreeIfNeeded()
        guard let control = clockDescendants(cell).compactMap({ $0 as? T }).first else {
            throw ClockSettingsError(message: "Missing native Clock cell control")
        }
        return control
    }

    func verify(_ checks: ClockChecks, records: [Clock_t], width: CGFloat, stage: String) throws {
        self.layout(width: width)
        let clip = self.scroll.contentView
        let prefix = "Clock \(Int(width))pt \(stage): "
        func visibleBody() -> NSRect {
            // Current native tables place the sticky header inside the clip.
            // Measure its actual rectangle again after each scroll; its area
            // is visible UI, rather than extra empty clock rows.
            let bounds = clip.bounds
            guard let header = self.table.headerView else { return bounds }
            let overlap = bounds.intersection(header.convert(header.bounds, to: clip))
            guard !overlap.isNull, overlap.height > 0, abs(overlap.minY - bounds.minY) < 0.75 else { return bounds }
            return NSRect(x: bounds.minX, y: overlap.maxY, width: bounds.width,
                          height: bounds.maxY - overlap.maxY)
        }
        checks.check(abs(self.scroll.bounds.width - width) < 0.75 &&
                     abs(self.table.bounds.width - clip.bounds.width) < 0.75 && !self.scroll.hasHorizontalScroller,
                     prefix + "the native table follows the full-width clip without horizontal scrolling")
        checks.check(self.table.tableColumns.map { $0.identifier } ==
                     [nameColumnID, formatColumnID, tzColumnID, calendarColumnID, statusColumnID],
                     prefix + "all five production columns remain in their original order")
        let columns = self.table.tableColumns.indices.map { self.table.convert(self.table.rect(ofColumn: $0), to: clip) }
        checks.check(columns.allSatisfy { $0.width > 0 && $0.minX >= clip.bounds.minX - 0.75 && $0.maxX <= clip.bounds.maxX + 0.75 },
                     prefix + "all five columns, including the last enabled column, fit completely in the visible clip")
        checks.check(self.table.tableColumns[0].width >= 72 - 0.75 && self.table.tableColumns[1].width >= 96 - 0.75,
                     prefix + "name and date format retain editable widths")
        checks.check(self.table.tableColumns[4].width >= 28 - 0.75,
                     prefix + "the checkbox column keeps a full native hit area")
        checks.check(self.table.numberOfRows == records.count,
                     prefix + "synthetic records are loaded by the real Settings class")

        for row in [0, records.count - 1] {
            self.table.scrollRowToVisible(row)
            self.table.layoutSubtreeIfNeeded()
            let controls: [NSControl] = [
                try self.control(NSTextField.self, column: 0, row: row),
                try self.control(NSTextField.self, column: 1, row: row),
                try self.control(NSPopUpButton.self, column: 2, row: row),
                try self.control(NSPopUpButton.self, column: 3, row: row),
                try self.control(NSButton.self, column: 4, row: row)
            ]
            let frames = controls.map { clockAlignmentFrame($0, in: clip) }
            let bodyViewport = visibleBody()
            if !frames.allSatisfy({ !$0.isEmpty && bodyViewport.insetBy(dx: -0.75, dy: -0.75).contains($0) }) {
                print(prefix + "row \(row) geometry clip=\(clip.bounds), body=\(bodyViewport), controls=\(frames)")
            }
            checks.check(frames.allSatisfy { !$0.isEmpty && bodyViewport.insetBy(dx: -0.75, dy: -0.75).contains($0) },
                         prefix + "row \(row) has five fully visible native controls, including its checkbox")
            checks.check(frames.indices.allSatisfy { first in
                frames.indices.filter { $0 > first }.allSatisfy { !clockOverlaps(frames[first], frames[$0]) }
            }, prefix + "row \(row) controls do not overlap adjacent columns")
            let rowRect = self.table.convert(self.table.rect(ofRow: row), to: clip)
            checks.check(frames.allSatisfy { abs($0.midY - rowRect.midY) < 0.75 },
                         prefix + "row \(row) text, native menus and checkbox are vertically centered")
            let name = controls[0] as! NSTextField
            let format = controls[1] as! NSTextField
            let zone = controls[2] as! NSPopUpButton
            let calendar = controls[3] as! NSPopUpButton
            let enabled = controls[4] as! NSButton
            checks.check(name.isEditable && format.isEditable && name.stringValue == records[row].name &&
                         format.stringValue == records[row].format && name.maximumNumberOfLines == 1 && format.maximumNumberOfLines == 1,
                         prefix + "row \(row) retains complete editable name and format strings")
            checks.check(zone.itemArray.compactMap { $0.representedObject as? String } == Clock.zones.filter { !$0.key.contains("separator") }.map { $0.key } &&
                         calendar.itemArray.compactMap { $0.representedObject as? String } == Clock.calendars.map { $0.key },
                         prefix + "row \(row) keeps every production time-zone and calendar option")
            checks.check(enabled.isEnabled && enabled.state == (records[row].enabled ? .on : .off),
                         prefix + "row \(row) retains its native enabled checkbox and saved state")
        }
        self.table.scrollRowToVisible(0)
        let rowsHeight = CGFloat(records.count) * (self.table.rowHeight + self.table.intercellSpacing.height)
        let bodyViewport = visibleBody()
        if records.count == 2 {
            checks.check(abs(bodyViewport.height - rowsHeight) < 2 && self.scroll.bounds.height < 150,
                         prefix + "a two-clock list fits its actual rows without a large empty table area")
        } else {
            checks.check(self.scroll.bounds.height <= 254.75 && rowsHeight > bodyViewport.height && self.scroll.hasVerticalScroller,
                         prefix + "long clock lists retain a bounded native internal scroll viewport")
        }
    }

    func save(_ output: URL, width: CGFloat, theme: String, checks: ClockChecks) throws {
        self.table.scrollRowToVisible(0)
        self.host.layoutSubtreeIfNeeded()
        for view in clockDescendants(self.host) { view.needsDisplay = true }
        guard let bitmap = self.host.bitmapImageRepForCachingDisplay(in: self.host.bounds) else {
            throw ClockSettingsError(message: "Could not create synthetic Clock settings image")
        }
        self.host.cacheDisplay(in: self.host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw ClockSettingsError(message: "Could not encode synthetic Clock settings image")
        }
        let path = output.appendingPathComponent("clock-settings-\(theme)-\(Int(width)).png")
        try png.write(to: path)
        checks.check(bitmap.pixelsWide >= Int(width) && bitmap.pixelsHigh > 100,
                     "synthetic production Clock settings rendered at \(Int(width))pt in \(theme)")
        print("Synthetic Clock settings PNG: " + path.path)
    }
}

private func clockRecords() throws -> [Clock_t] {
    guard let data = Store.shared.data(key: "Clock_list") else {
        throw ClockSettingsError(message: "Missing isolated Clock records")
    }
    return try JSONDecoder().decode([Clock_t].self, from: data)
}

@main
private struct ClockSettingsLayoutChecks {
    static func main() {
        do { try run() }
        catch { print("Clock settings checks failed: " + error.localizedDescription); exit(1) }
    }

    private static func run() throws {
        setbuf(stdout, nil)
        guard let domain = Bundle.main.bundleIdentifier, domain.hasPrefix("local.stats.clock-settings-checks."),
              ProcessInfo.processInfo.processName.hasPrefix("stats-clock-settings-checks-") else {
            throw ClockSettingsError(message: "Clock settings checks require a distinct randomly named helper app")
        }
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        guard let index = CommandLine.arguments.firstIndex(of: "--output-dir"), CommandLine.arguments.indices.contains(index + 1) else {
            throw ClockSettingsError(message: "--output-dir is required")
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let checks = ClockChecks()
        let records = [
            Clock_t(id: "synthetic-clock-one", enabled: true, name: "Synthetic Local Clock · 合成时钟一", format: "yy MM dd HH:mm:ss", tz: "8"),
            Clock_t(id: "synthetic-clock-two", enabled: false, name: "Synthetic Other Clock · 合成时钟二", format: "EEE HH:mm:ss z", tz: "0", calendar: "buddhist")
        ]
        print("Clock settings locale: \(Locale.current.identifier); languages: \(Locale.preferredLanguages)")
        for width: CGFloat in [420, 540, 680] {
            let fixture = try ClockSettingsFixture(width: width, records: records)
            defer { fixture.window.close() }
            let original = Store.shared.data(key: "Clock_list")
            var ntpCallbacks = 0
            fixture.settings.callback = { ntpCallbacks += 1 }
            for (theme, name) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
                guard let appearance = NSAppearance(named: name) else { continue }
                app.appearance = appearance
                fixture.window.appearance = appearance
                fixture.host.appearance = appearance
                try fixture.verify(checks, records: records, width: width, stage: theme)
                try fixture.save(output, width: width, theme: theme, checks: checks)
            }
            fixture.layout(width: 760)
            try fixture.verify(checks, records: records, width: width, stage: "after resizing back from 760pt")
            checks.check(Store.shared.data(key: "Clock_list") == original && !Store.shared.bool(key: "Clock_ntpSync", defaultValue: true) && ntpCallbacks == 0,
                         "layout, scrolling and resizing preserve the isolated clock settings without invoking NTP")

            let toggle = try fixture.control(NSButton.self, column: 4, row: 0)
            toggle.state = .off
            let toggled = toggle.sendAction(toggle.action, to: toggle.target)
            let toggledRecords = try clockRecords()
            checks.check(toggled && !toggledRecords[0].enabled && !toggledRecords[1].enabled,
                         "the visible enabled checkbox keeps its production record callback")
            let zone = try fixture.control(NSPopUpButton.self, column: 2, row: 0)
            guard let zoneItem = zone.itemArray.first(where: { ($0.representedObject as? String) == "1" }) else {
                throw ClockSettingsError(message: "Missing production zone menu choice")
            }
            zone.select(zoneItem)
            let selectedZone = zone.sendAction(zone.action, to: zone.target)
            let zoneRecords = try clockRecords()
            checks.check(selectedZone && zoneRecords[0].tz == "1" && zoneRecords[1].tz == "0",
                         "the native time-zone selector changes only its synthetic clock through the original callback")
            let calendar = try fixture.control(NSPopUpButton.self, column: 3, row: 0)
            guard let calendarItem = calendar.itemArray.first(where: { ($0.representedObject as? String) == "buddhist" }) else {
                throw ClockSettingsError(message: "Missing production calendar menu choice")
            }
            calendar.select(calendarItem)
            let selectedCalendar = calendar.sendAction(calendar.action, to: calendar.target)
            let calendarRecords = try clockRecords()
            checks.check(selectedCalendar && calendarRecords[0].calendar == "buddhist",
                         "the native calendar selector keeps its original synthetic-record callback")
            checks.check(ntpCallbacks == 0 && !Store.shared.bool(key: "Clock_ntpSync", defaultValue: true),
                         "clock option callbacks do not invoke the NTP switch or a clock reader")
        }
        let many = (0..<12).map { index in
            Clock_t(id: "synthetic-many-\(index)", name: "Synthetic Clock \(index)", format: "HH:mm:ss", tz: "0")
        }
        let long = try ClockSettingsFixture(width: 420, records: many)
        defer { long.window.close() }
        try long.verify(checks, records: many, width: 420, stage: "long list")
        print("Clock settings AppKit checks: \(checks.count) checks, \(checks.failures) failures")
        if checks.failures > 0 { throw ClockSettingsError(message: "Clock settings layout checks failed") }
    }
}
