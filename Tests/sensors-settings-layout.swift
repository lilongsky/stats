// This file is compiled together with the unchanged production Sensors
// settings, popup, notifications, fan-curve settings and value model sources.
// It creates no Sensors module, telemetry reader, fan controller, application
// delegate, visible window, notification request, or hardware command.
import Cocoa
import Kit

private func sensorDescendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(sensorDescendants)
}

private func sensorVisible(_ view: NSView) -> Bool {
    !view.isHidden && (view.superview.map(sensorVisible) ?? true)
}

private func sensorAlignmentFrame(_ view: NSView, in target: NSView) -> NSRect {
    guard let parent = view.superview else { return view.convert(view.bounds, to: target) }
    return parent.convert(view.alignmentRect(forFrame: view.frame), to: target)
}

private final class SensorPreviewHost: NSView {
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(rect: self.bounds).fill()
    }
}

private class SensorFormFixture {
    let form: NSView
    let kind: String
    let width: CGFloat
    let window: NSWindow
    let host: SensorPreviewHost
    private(set) var scroll: ScrollableStackView

    init(width: CGFloat, form: NSView, kind: String) {
        self.width = width
        self.form = form
        self.kind = kind
        let host = SensorPreviewHost(frame: NSRect(x: 0, y: 0, width: width + 40, height: 940))
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        self.host = host
        self.window = window
        self.scroll = ScrollableStackView()
        window.isReleasedWhenClosed = false
        window.contentView = host
        self.mount()
    }

    private func mount() {
        self.scroll.translatesAutoresizingMaskIntoConstraints = false
        self.scroll.stackView.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        self.host.addSubview(self.scroll)
        NSLayoutConstraint.activate([
            self.scroll.widthAnchor.constraint(equalToConstant: self.width + 40),
            self.scroll.leadingAnchor.constraint(equalTo: self.host.leadingAnchor),
            self.scroll.trailingAnchor.constraint(equalTo: self.host.trailingAnchor),
            self.scroll.topAnchor.constraint(equalTo: self.host.topAnchor),
            self.scroll.bottomAnchor.constraint(equalTo: self.host.bottomAnchor)
        ])
        self.scroll.stackView.addArrangedSubview(self.form)
        self.layout()
    }

    func remount() {
        self.scroll.stackView.removeArrangedSubview(self.form)
        self.form.removeFromSuperview()
        self.scroll.removeFromSuperview()
        self.scroll = ScrollableStackView()
        self.mount()
    }

    func layout() {
        self.host.layoutSubtreeIfNeeded()
        self.scroll.stackView.layoutSubtreeIfNeeded()
        self.form.layoutSubtreeIfNeeded()
    }

    var cards: [PreferencesSection] {
        sensorDescendants(self.form).compactMap { $0 as? PreferencesSection }.filter(sensorVisible)
    }

    func verify(_ checks: Checks, stage: String, minimumCards: Int = 2) {
        self.layout()
        let prefix = "\(self.kind) \(Int(self.width))pt \(stage): "
        let expected = self.scroll.stackView.bounds.width - 40
        checks.check(abs(self.host.bounds.width - self.width - 40) < 0.75 &&
                     abs(expected - self.width) < 0.75 && abs(self.form.bounds.width - expected) < 0.75,
                     prefix + "the real module and viewport retain the requested test width" +
                     " [host=\(self.host.bounds.width), viewport=\(expected), form=\(self.form.bounds.width)]")
        let cards = self.cards
        let rects = cards.map { $0.convert($0.bounds, to: self.form) }
        let badEdges = cards.indices.filter {
            abs(rects[$0].minX) > 0.75 || abs(rects[$0].maxX - expected) > 0.75 || rects[$0].height <= 0
        }
        checks.check(cards.count >= minimumCards && badEdges.isEmpty,
                     prefix + "all static and dynamic cards share both form edges" +
                     badEdges.map { " [\(cards[$0].identifier?.rawValue ?? "card"): \(rects[$0])]" }.joined())
        var overlapping = false
        for first in rects.indices {
            for second in rects.indices where second > first {
                let intersection = rects[first].intersection(rects[second])
                if !intersection.isNull && intersection.width > 0.75 && intersection.height > 0.75 { overlapping = true }
            }
        }
        checks.check(!overlapping, prefix + "separate settings cards do not overlap")

        var badLabels: [String] = []
        var controlEdges: [CGFloat] = []
        var badControls: [String] = []
        for card in cards {
            let container = card.bounds.insetBy(dx: -1, dy: -1)
            for field in sensorDescendants(card).compactMap({ $0 as? NSTextField })
                where sensorVisible(field) && !field.stringValue.isEmpty && !field.isEditable {
                let rect = field.convert(field.bounds, to: card)
                let size = field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0,
                    width: field.bounds.width, height: 10000)) ?? field.intrinsicContentSize
                if field.bounds.width <= 0 || field.bounds.height <= 0 || !container.contains(rect) ||
                    size.height > field.bounds.height + 2 {
                    badLabels.append("\(field.stringValue): frame=\(rect), needed-height=\(size.height)")
                }
            }
            for row in sensorDescendants(card).compactMap({ $0 as? PreferencesRow }) where sensorVisible(row) {
                guard let control = row.arrangedSubviews.last,
                      !(control is NSTextField) else { continue }
                let frame = sensorAlignmentFrame(control, in: card)
                if frame.isEmpty || !container.contains(frame) {
                    badControls.append("\(type(of: control)): \(frame)")
                }
                if row.arrangedSubviews.count > 1, let text = row.arrangedSubviews.first {
                    let intersection = text.convert(text.bounds, to: row).intersection(sensorAlignmentFrame(control, in: row))
                    if !intersection.isNull && intersection.width > 0.75 && intersection.height > 0.75 {
                        badControls.append("label/control overlap")
                    }
                }
                controlEdges.append(sensorAlignmentFrame(control, in: self.form).maxX)
            }
        }
        checks.check(badLabels.isEmpty, prefix + "real section headings, sensor names and explanations are not clipped" +
                     (badLabels.isEmpty ? "" : ": " + badLabels.joined(separator: "; ")))
        checks.check(badControls.isEmpty && !controlEdges.isEmpty &&
                     controlEdges.allSatisfy { abs($0 - controlEdges[0]) < 0.75 },
                     prefix + "native switches and selectors are visible, do not overlap text and share a trailing edge" +
                     (badControls.isEmpty ? "" : ": " + badControls.joined(separator: "; ")))
        self.verifyCompositeControls(checks, prefix: prefix)
    }

    private func verifyCompositeControls(_ checks: Checks, prefix: String) {
        let rows = sensorDescendants(self.form).compactMap { $0 as? PreferencesRow }.filter(sensorVisible)
        if self.kind == "sensors-popup" {
            let shortcuts = rows.filter { $0.arrangedSubviews.last is KeyboardShartcutView }
            let aligned = shortcuts.count == 1 && shortcuts.allSatisfy { row in
                guard let shortcut = row.arrangedSubviews.last as? KeyboardShartcutView,
                      let record = shortcut.arrangedSubviews.last as? NSButton else { return false }
                let edge = row.bounds.maxX - row.edgeInsets.right
                return sensorVisible(record) && !record.bounds.isEmpty &&
                    abs(sensorAlignmentFrame(record, in: row).maxX - edge) < 0.75
            }
            checks.check(aligned,
                         prefix + "the real shortcut record button itself aligns with the row's trailing edge")
        }
        if self.kind == "sensors-notifications" {
            let durations = rows.filter { $0.arrangedSubviews.last is StepperInput }
            let aligned = durations.count == 1 && durations.allSatisfy { row in
                guard let stepper = row.arrangedSubviews.last as? StepperInput,
                      let unit = stepper.arrangedSubviews.last as? NSTextField, !unit.isEditable else { return false }
                let edge = row.bounds.maxX - row.edgeInsets.right
                return sensorVisible(unit) && !unit.bounds.isEmpty &&
                    abs(sensorAlignmentFrame(unit, in: row).maxX - edge) < 0.75
            }
            checks.check(aligned,
                         prefix + "the duration's actual unit label shares the row's trailing edge")
            let compact = durations.count == 1 && durations.allSatisfy { row in
                guard let stepper = row.arrangedSubviews.last as? StepperInput,
                      let number = stepper.arrangedSubviews.compactMap({ $0 as? NSTextField }).first(where: { $0.isEditable })
                    else { return false }
                // A short numeric value should retain enough room for its
                // native text metrics while occupying only a small fraction
                // of the form. The test sets no production pixel dimensions.
                let natural = number.cell?.cellSize.width ?? number.intrinsicContentSize.width
                return number.bounds.width > 0 && number.bounds.width + 0.75 >= natural &&
                    number.bounds.width < row.bounds.width * 0.35 && stepper.bounds.width < row.bounds.width * 0.5
            }
            checks.check(compact,
                         prefix + "the duration's numeric field fits its text without stretching across the row")
        }
    }

    func save(appearance: NSAppearance, theme: String, path: String, output: URL) throws {
        NSApp.appearance = appearance
        self.window.appearance = appearance
        self.host.appearance = appearance
        self.layout()
        var bitmap: NSBitmapImageRep?
        appearance.performAsCurrentDrawingAppearance {
            self.window.backgroundColor = .windowBackgroundColor
            for view in sensorDescendants(self.host) {
                view.needsDisplay = true
                if view.wantsLayer { view.updateLayer() }
            }
            bitmap = self.host.bitmapImageRepForCachingDisplay(in: self.host.bounds)
            if let bitmap { self.host.cacheDisplay(in: self.host.bounds, to: bitmap) }
        }
        guard let data = bitmap?.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "SensorsSettingsChecks", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not render the real Sensors settings view"])
        }
        let url = output.appendingPathComponent("settings-\(self.kind)-checked-\(theme)-\(Int(self.width))-\(path).png")
        try data.write(to: url, options: .atomic)
        print("Real Sensors production view PNG: \(url.path)")
    }
}

private final class SensorSettingsFixture: SensorFormFixture {
    // Compile and instantiate the internal production class. Its static cards
    // are created before a window or form host exists.
    let settings: Settings

    init(width: CGFloat, beforeMount: ((Settings) -> Void)?) {
        let settings = Settings(.sensors)
        self.settings = settings
        beforeMount?(settings)
        super.init(width: width, form: settings, kind: "sensors")
    }

    var dynamicSections: [PreferencesSection] {
        self.settings.arrangedSubviews.compactMap { $0 as? PreferencesSection }
            .filter { $0.identifier?.rawValue == "sensor" }
    }
}

enum SensorsSettingsChecks {
    static func run(checks: Checks, output: URL) throws {
        // Load the matching app's named model artwork through Bundle's public image
        // API and register it only in this short-lived helper's image cache.
        // This satisfies SystemKit's resource prerequisite without replacing
        // production artwork or launching the app that supplies the resources.
        if let index = CommandLine.arguments.firstIndex(of: "--resource-app"),
           CommandLine.arguments.indices.contains(index + 1),
           let bundle = Bundle(path: CommandLine.arguments[index + 1]) {
            for name in ["imacPro", "macMini2024", "macMini2020", "macMini", "macStudio", "macPro2019", "macPro",
                         "imac", "macbookAir", "macbookNeo", "macbookAir4thGen", "macbookPro5thGen", "macbookPro"] {
                if let image = bundle.image(forResource: NSImage.Name(name)) {
                    image.setName(NSImage.Name(name))
                }
            }
        }
        guard NSImage(named: NSImage.Name("imacPro")) != nil else {
            throw NSError(domain: "SensorsSettingsChecks", code: 2,
                userInfo: [NSLocalizedDescriptionKey:
                    "The real Sensors settings require --resource-app with the matching app's model artwork"])
        }
        let sensors: [Sensor_p] = [
            Sensor(key: "ui-temperature-airport", name: "Airport", group: .system,
                   type: .temperature, platforms: Platform.all),
            Sensor(key: "ui-temperature-long", name: "CPU performance core with a detailed custom sensor name · 性能核心温度",
                   group: .CPU, type: .temperature, platforms: Platform.all),
            Sensor(key: "Average System Total", name: "System Total", group: .system,
                   type: .power, platforms: Platform.all)
        ]
        let fan = Fan(id: 90, key: "ui-fan", name: "Fixture Fan", minSpeed: 1000, maxSpeed: 7000,
                      value: 2000, mode: .automatic)
        for width: CGFloat in [420, 540, 680] {
            for beforeMount in [true, false] {
                for (theme, name) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
                    guard let appearance = NSAppearance(named: name) else { continue }
                    NSApp.appearance = appearance
                    let path = beforeMount ? "list-before-mount" : "list-after-mount"
                    let fixture = SensorSettingsFixture(width: width, beforeMount: { settings in
                        checks.check(settings.superview == nil && settings.arrangedSubviews.count >= 3,
                                     "Sensors constructs real static cards before a window or form host exists")
                        settings.load(widgets: [.mini])
                        if beforeMount { settings.setList(sensors) }
                    })
                    defer { fixture.window.close() }
                    fixture.window.appearance = appearance
                    fixture.host.appearance = appearance
                    fixture.verify(checks, stage: "\(theme), \(path), initial")
                    if !beforeMount { fixture.settings.setList(sensors) }
                    checks.check(fixture.dynamicSections.count == 2,
                                 "Sensors \(path) creates one real section per available sensor type")
                    fixture.verify(checks, stage: "\(theme), \(path), populated")
                    for iteration in 1...3 {
                        fixture.settings.setList(sensors)
                        checks.check(fixture.dynamicSections.count == 2,
                                     "Sensors repeated reader-list refresh \(iteration) keeps exactly two dynamic sections")
                    }
                    fixture.verify(checks, stage: "\(theme), \(path), repeated")
                    let active = fixture.cards.first { $0.identifier?.rawValue == "sensor-monitoring" }?
                        .findRow("active_sensor")
                    fixture.settings.load(widgets: [.barChart])
                    checks.check(active?.isHidden == true,
                                 "the real Sensor to show row hides for widgets that do not select a single sensor")
                    fixture.settings.load(widgets: [.mini])
                    checks.check(active?.isHidden == false,
                                 "the same real Sensor to show row reappears for the Mini widget")
                    fixture.verify(checks, stage: "\(theme), \(path), widget changed")

                    fixture.settings.setList(sensors + [fan])
                    checks.check(fixture.dynamicSections.count == 3 &&
                                 sensorDescendants(fixture.settings).contains { ($0 as? NSPopUpButton)?.numberOfItems == FanValues.count },
                                 "real Fan models reveal a Fans section and contextual fan controls")
                    fixture.verify(checks, stage: "\(theme), \(path), fans")
                    fixture.settings.setList([])
                    checks.check(fixture.dynamicSections.isEmpty &&
                                 !sensorDescendants(fixture.settings).contains { $0.identifier?.rawValue == "ui-fan" ||
                                     $0.identifier?.rawValue == "ui-temperature-airport" },
                                 "an empty reader list removes all previous sensor sections and switches")
                    fixture.verify(checks, stage: "\(theme), \(path), empty")
                    fixture.settings.setList(nil)
                    checks.check(fixture.dynamicSections.isEmpty,
                                 "a missing reader list leaves the current empty form intact")
                    fixture.settings.setList(sensors)
                    fixture.remount()
                    checks.check(fixture.dynamicSections.count == 2,
                                 "remounting the existing real module preserves exactly its current sensor groups")
                    fixture.verify(checks, stage: "\(theme), \(path), remounted")
                    try fixture.save(appearance: appearance, theme: theme, path: path, output: output)
                }
            }
        }
        try self.verifySecondaryForms(sensors: sensors, checks: checks, output: output)
    }

    private static func verifySecondaryForms(sensors: [Sensor_p], checks: Checks, output: URL) throws {
        // No Fan models are passed to Popup.setup. FanView and the fan curve
        // controller have real hardware side effects, so those paths are not
        // instantiated and no settings actions are fired in these checks.
        precondition(sensors.allSatisfy { !($0 is Fan) && $0.type != .fan })
        for width: CGFloat in [420, 540, 680] {
            for beforeMount in [true, false] {
                for (theme, name) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
                    guard let appearance = NSAppearance(named: name) else { continue }
                    NSApp.appearance = appearance
                    let path = beforeMount ? "list-before-mount" : "list-after-mount"
                    let popup = Popup()
                    guard let form = popup.settings() as? NSStackView else {
                        throw NSError(domain: "SensorsSettingsChecks", code: 3,
                            userInfo: [NSLocalizedDescriptionKey: "The real Sensors Popup did not provide its settings form"])
                    }
                    checks.check(form.superview == nil && form.arrangedSubviews.count == 2,
                                 "the real Sensors Popup constructs shortcut and fan-value settings before mounting")
                    if beforeMount { popup.setup(sensors) }
                    let fixture = SensorFormFixture(width: width, form: form, kind: "sensors-popup")
                    defer { fixture.window.close() }
                    fixture.window.appearance = appearance
                    fixture.host.appearance = appearance
                    fixture.verify(checks, stage: "\(theme), \(path), initial")
                    if !beforeMount { popup.setup(sensors) }
                    let populatedCount = fixture.cards.count
                    func groups() -> Int {
                        form.arrangedSubviews.filter { $0.identifier?.rawValue == "sensor" }.count
                    }
                    checks.check(groups() == 2 && populatedCount == 4,
                                 "real Popup.setup adds exactly its two sensor types beside its two static settings cards")
                    fixture.verify(checks, stage: "\(theme), \(path), populated")
                    for iteration in 1...2 {
                        popup.setup(sensors)
                        checks.check(groups() == 2 && fixture.cards.count == populatedCount &&
                                     form.arrangedSubviews.filter { $0.identifier?.rawValue == "fan-curve-settings" }.count == 1,
                                     "real Popup.setup refresh \(iteration) replaces sensor groups and keeps one fan-curve settings container")
                        fixture.verify(checks, stage: "\(theme), \(path), refresh \(iteration)")
                    }
                    popup.setup(reload: true)
                    checks.check(groups() == 2 && fixture.cards.count == populatedCount,
                                 "the real Popup's cached-list reload preserves its settings groups without duplicates")
                    fixture.remount()
                    fixture.verify(checks, stage: "\(theme), \(path), remounted")
                    try fixture.save(appearance: appearance, theme: theme, path: path, output: output)

                    // This is the actual Notifications subclass and setup path.
                    // initIDs only removes matching delivered notifications in
                    // this runner's distinct temporary app domain. Never call
                    // usageCallback, checkDouble, or any authorization method.
                    let notifications = Notifications(.sensors)
                    checks.check(notifications.superview == nil && notifications.arrangedSubviews.count == 1,
                                 "the real Sensors Notifications constructs its Alert Rules before mounting")
                    if beforeMount { notifications.setup(sensors) }
                    let alerts = SensorFormFixture(width: width, form: notifications, kind: "sensors-notifications")
                    defer { alerts.window.close() }
                    alerts.window.appearance = appearance
                    alerts.host.appearance = appearance
                    alerts.verify(checks, stage: "\(theme), \(path), initial", minimumCards: beforeMount ? 2 : 1)
                    if !beforeMount { notifications.setup(sensors) }
                    checks.check(alerts.cards.count == 2 &&
                                 sensorDescendants(notifications).compactMap { $0 as? NSPopUpButton }.count == 2,
                                 "real Notifications.setup includes the duration card and two temperature threshold selectors")
                    alerts.verify(checks, stage: "\(theme), \(path), populated")
                    for iteration in 1...2 {
                        notifications.setup(sensors)
                        checks.check(alerts.cards.count == 2,
                                     "real Notifications.setup refresh \(iteration) does not accumulate duration or threshold cards")
                        alerts.verify(checks, stage: "\(theme), \(path), refresh \(iteration)")
                    }
                    notifications.setup([])
                    checks.check(alerts.cards.count == 1 &&
                                 sensorDescendants(notifications).compactMap { $0 as? NSPopUpButton }.isEmpty,
                                 "real Notifications.setup removes all sensor thresholds when the list becomes empty")
                    alerts.verify(checks, stage: "\(theme), \(path), empty", minimumCards: 1)
                    notifications.setup(sensors)
                    alerts.remount()
                    alerts.verify(checks, stage: "\(theme), \(path), remounted")
                    try alerts.save(appearance: appearance, theme: theme, path: path, output: output)
                }
            }
        }
    }
}
