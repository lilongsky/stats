// Import the real rebuilt Kit. No application delegate, module readers, live
// settings window or production preference domain is created by this helper.
import Cocoa
import Kit

private struct SettingsCheckError: LocalizedError {
    let message: String
    var errorDescription: String? { self.message }
}

private final class Checks {
    var count = 0
    var failures = 0

    func check(_ result: Bool, _ message: String) {
        self.count += 1
        if !result {
            self.failures += 1
            print("FAIL: \(message)")
        }
    }

    func fire(_ control: NSControl, _ message: String) throws {
        guard control.isEnabled, let action = control.action else {
            throw SettingsCheckError(message: "Action unavailable: " + message)
        }
        self.check(control.sendAction(action, to: control.target), message)
    }
}

private func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(descendants)
}

private func requiredView<T: NSView>(_ root: NSView, _ id: String, _ type: T.Type) throws -> T {
    guard let view = descendants(root).first(where: { $0.identifier?.rawValue == id }) as? T else {
        throw SettingsCheckError(message: "Missing production view: " + id)
    }
    return view
}

private func visible(_ view: NSView) -> Bool {
    if view.isHidden { return false }
    return view.superview.map(visible) ?? true
}

private func overlaps(_ first: NSRect, _ second: NSRect) -> Bool {
    let intersection = first.intersection(second)
    return !intersection.isNull && intersection.width > 0.6 && intersection.height > 0.6
}

private func alignmentFrame(_ view: NSView, in target: NSView) -> NSRect {
    guard let parent = view.superview else { return view.convert(view.bounds, to: target) }
    return parent.convert(view.alignmentRect(forFrame: view.frame), to: target)
}

// A solid semantic background is part of the exported image. No WindowServer
// capture, frontmost window, menu tracking or global input event is used.
private final class PreviewHost: NSView {
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(rect: self.bounds).fill()
    }
}

private final class SettingsFixture {
    let width: CGFloat
    let window: NSWindow
    let host: PreviewHost
    let caption: NSTextField
    let body: SettingsContainerView
    let popup: PopupWrapper
    let section: PreferencesSection
    let rows: [PreferencesRow]
    let controls: [NSControl]
    let customization: NSView
    let sectionIDs: [String]
    let subtitle: String
    private var bodyHeight: NSLayoutConstraint?

    init(width: CGFloat) {
        let host = PreviewHost(frame: NSRect(x: 0, y: 0, width: width + 32, height: 1200))
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        let body = SettingsContainerView()
        let caption = NSTextField(labelWithString: "Isolated production view")
        let popup = PopupWrapper(.CPU, frame: NSRect(x: 0, y: 0, width: 320, height: 0))
        let toggle = LocalToggle(false) { _ in }
        let choice = LocalChoice(["1 second", "5 seconds", "30 seconds"], selected: 1) { _ in }
        let button = LocalActionButton("Reset") {}
        let rows = [
            PreferencesRow("Show a compact indicator · 紧凑显示", id: "settings-row-first", component: toggle),
            PreferencesRow("Sampling interval · 更新间隔", "Values stay local to this isolated fixture.",
                           id: "settings-row-middle", component: choice),
            PreferencesRow("Restore this module · 恢复此指标", id: "settings-row-last", component: button)
        ]
        let subtitle = "These are isolated production settings views. A longer explanation must wrap below its heading and stay inside the card at either content width. 更改仅作用于当前指标，说明文字应完整换行显示，不与标题、控件或后面的设置卡片重叠。"
        let section = PreferencesSection(title: "Display and sampling · 显示与采样",
                                          subtitle: subtitle, id: "settings-fixture-section", rows)
        let ids = ["dashboard", "history", "details", "average", "frequency", "processes"]
        let sectionTitles = ["仪表", "负载历史", "详细信息", "平均负载", "频率", "高占用进程"]
        popup.orientation = .vertical
        popup.spacing = 4
        for (index, height) in [72, 48, 64, 40, 36, 88].enumerated() {
            let placeholder = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: CGFloat(height)))
            placeholder.heightAnchor.constraint(equalToConstant: CGFloat(height)).isActive = true
            popup.addPopupSection(placeholder, id: ids[index], title: sectionTitles[index])
        }
        popup.applySectionLayout()
        let customization = popup.customizationSettings()

        self.width = width
        self.host = host
        self.window = window
        self.caption = caption
        self.body = body
        self.popup = popup
        self.controls = [toggle, choice, button]
        self.rows = rows
        self.section = section
        self.customization = customization
        self.sectionIDs = ids
        self.subtitle = subtitle
        self.window.isReleasedWhenClosed = false
        self.body.addArrangedSubview(self.section)
        self.body.addArrangedSubview(self.customization)

        self.caption.font = .systemFont(ofSize: 12, weight: .medium)
        self.caption.translatesAutoresizingMaskIntoConstraints = false
        self.host.addSubview(self.caption)
        self.host.addSubview(self.body)
        self.window.contentView = self.host
        NSLayoutConstraint.activate([
            self.caption.leadingAnchor.constraint(equalTo: self.host.leadingAnchor, constant: 16),
            self.caption.topAnchor.constraint(equalTo: self.host.topAnchor, constant: 16),
            self.caption.widthAnchor.constraint(equalToConstant: width),
            self.caption.heightAnchor.constraint(equalToConstant: 24),
            self.body.leadingAnchor.constraint(equalTo: self.host.leadingAnchor, constant: 16),
            self.body.topAnchor.constraint(equalTo: self.caption.bottomAnchor, constant: 12),
            self.body.widthAnchor.constraint(equalToConstant: width)
        ])
        self.layout()
    }

    func layout() {
        self.bodyHeight?.isActive = false
        self.host.layoutSubtreeIfNeeded()
        let height = max(1, ceil(self.body.fittingSize.height))
        if let constraint = self.bodyHeight {
            constraint.constant = height
        } else {
            self.bodyHeight = self.body.heightAnchor.constraint(equalToConstant: height)
        }
        self.bodyHeight?.isActive = true
        self.window.setContentSize(NSSize(width: self.width + 32, height: height + 68))
        self.host.layoutSubtreeIfNeeded()
        // Materialize the six real table cells for layout and offscreen drawing;
        // the fallback by native type also works with an older baseline Kit.
        if let table = descendants(self.customization).compactMap({ $0 as? NSTableView }).first {
            for row in 0..<table.numberOfRows { _ = table.view(atColumn: 0, row: row, makeIfNecessary: true) }
            table.layoutSubtreeIfNeeded()
        }
    }

    func row(_ index: Int) throws -> NSView {
        let editor = try requiredView(self.customization, "popup-section-editor", NSView.self)
        let table = try requiredView(editor, "popup-sections-table", NSTableView.self)
        guard let row = table.view(atColumn: 0, row: index, makeIfNecessary: true) else {
            throw SettingsCheckError(message: "Missing production section row \(index)")
        }
        row.layoutSubtreeIfNeeded()
        return row
    }
}

private func verifyGeometry(_ fixture: SettingsFixture, _ checks: Checks) throws {
    let cards = [fixture.section,
        try requiredView(fixture.customization, "popup-settings-sections", PreferencesSection.self),
        try requiredView(fixture.customization, "popup-settings-tools", PreferencesSection.self)]
    let frames = cards.map { $0.convert($0.bounds, to: fixture.body) }
    checks.check(frames.allSatisfy { abs($0.minX) < 0.6 && abs($0.width - fixture.width) < 0.6 },
                 "\(Int(fixture.width))pt: production cards share the full content width and left/right edges")
    checks.check(zip(frames, frames.dropFirst()).allSatisfy { !overlaps($0.0, $0.1) },
                 "\(Int(fixture.width))pt: adjacent settings cards do not overlap")

    let controlFrames = fixture.controls.map { alignmentFrame($0, in: fixture.section) }
    checks.check(controlFrames.allSatisfy { abs($0.maxX - controlFrames[0].maxX) < 0.6 },
                 "\(Int(fixture.width))pt: differently sized row controls align at the right edge")
    checks.check(zip(fixture.rows, fixture.controls).allSatisfy { pair in
        let (row, control) = pair
        let component = control.convert(control.bounds, to: row)
        let hitArea = control.convert(control.bounds, to: fixture.section)
        let text = row.arrangedSubviews[0].convert(row.arrangedSubviews[0].bounds, to: row)
        return !component.isEmpty && fixture.section.bounds.insetBy(dx: -0.6, dy: -0.6).contains(hitArea) && !overlaps(text, component)
    }, "\(Int(fixture.width))pt: full control hit areas stay inside the card without overlapping row labels")

    guard let subtitle = descendants(fixture.section).compactMap({ $0 as? NSTextField })
        .first(where: { $0.stringValue == fixture.subtitle }) else {
        throw SettingsCheckError(message: "Missing production subtitle field")
    }
    let font = subtitle.font ?? .systemFont(ofSize: 11)
    let measured = (subtitle.stringValue as NSString).boundingRect(
        with: NSSize(width: max(1, subtitle.bounds.width), height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
    checks.check(subtitle.bounds.height > font.pointSize * 1.8 && subtitle.bounds.height + 2 >= measured.height &&
                 fixture.section.bounds.insetBy(dx: -0.6, dy: -0.6).contains(subtitle.convert(subtitle.bounds, to: fixture.section)),
                 "\(Int(fixture.width))pt: long section explanations wrap fully inside their card")
    checks.check(fixture.customization.identifier?.rawValue == "popup-customization",
                 "the production popup customization view is rendered")

    let editor = try requiredView(fixture.customization, "popup-tools-editor", NSStackView.self)
    let choices = try (0..<4).map {
        try requiredView(editor, "popup-tool-choice-\($0)", LocalChoice.self)
    }
    let choiceFrames = choices.map { $0.convert($0.bounds, to: fixture.customization) }
    let choiceAlignment = choices.map { alignmentFrame($0, in: fixture.customization) }
    checks.check(choiceAlignment.allSatisfy { abs($0.maxX - choiceAlignment[0].maxX) < 0.6 } &&
                 choiceFrames.allSatisfy {
                     !$0.isEmpty && fixture.customization.bounds.insetBy(dx: -0.6, dy: -0.6).contains($0)
                 }, "\(Int(fixture.width))pt: native tool choice alignment and full hit areas fit the flexible editor")

    let middle = try fixture.row(2)
    let toggle = try requiredView(middle, "popup-section-toggle-details", LocalToggle.self)
    let up = try requiredView(middle, "popup-section-up-details", LocalActionButton.self)
    let down = try requiredView(middle, "popup-section-down-details", LocalActionButton.self)
    let sectionControls: [NSControl] = [up, down, toggle]
    let rowControls = sectionControls.map { $0.convert($0.bounds, to: middle) }
    checks.check(rowControls.allSatisfy { !($0.isEmpty) && middle.bounds.insetBy(dx: -0.6, dy: -0.6).contains($0) } &&
                 rowControls[2].minX >= max(rowControls[0].maxX, rowControls[1].maxX) - 0.6 &&
                 !overlaps(rowControls[0], rowControls[1]),
                 "\(Int(fixture.width))pt: section actions fit their row with the visibility switch on the right")
    try verifyVisibleSectionRows(fixture, checks)
}

private func verifyVisibleSectionRows(_ fixture: SettingsFixture, _ checks: Checks) throws {
    let table = try requiredView(fixture.customization, "popup-sections-table", NSTableView.self)
    guard table.numberOfRows > 0 && table.numberOfRows <= 8, let scroll = table.enclosingScrollView else {
        throw SettingsCheckError(message: "The short section fixture requires a real enclosing scroll view")
    }
    let clip = scroll.contentView
    let indices = [0, table.numberOfRows - 1]
    let rows = try indices.map { try fixture.row($0) }
    let rowRects = indices.map { table.convert(table.rect(ofRow: $0), to: clip) }
    checks.check(!scroll.hasVerticalScroller,
                 "\(Int(fixture.width))pt: a short section list is shown without a vertical scrollbar")
    let visibleBounds = clip.bounds.insetBy(dx: -0.6, dy: -0.6)
    for position in indices.indices {
        let row = rows[position]
        let cellRect = row.convert(row.bounds, to: clip)
        let controls = descendants(row).compactMap { $0 as? NSControl }.filter { visible($0) }
        let controlRects = controls.map { $0.convert($0.bounds, to: clip) }
        let fits = !rowRects[position].isEmpty && visibleBounds.contains(rowRects[position]) &&
            visibleBounds.contains(cellRect) && !controlRects.isEmpty &&
            controlRects.allSatisfy { !$0.isEmpty && visibleBounds.contains($0) }
        if !fits {
            print("Clipped section row \(indices[position]): style=\(table.style.rawValue), " +
                  "clip=\(clip.bounds), row=\(rowRects[position]), cell=\(cellRect), controls=\(controlRects)")
        }
        checks.check(fits,
                     "\(Int(fixture.width))pt: section row \(indices[position]) and every control fit completely inside the visible clip bounds")
    }
}

private func verifySectionAPIs(_ fixture: SettingsFixture, _ checks: Checks) {
    let originalHeight = fixture.section.frame.height
    let short = "Only this isolated module is changed."
    fixture.section.setSubtitle(short)
    fixture.layout()
    checks.check(fixture.section.frame.height < originalHeight &&
                 descendants(fixture.section).compactMap { $0 as? NSTextField }.contains { $0.stringValue == short },
                 "setSubtitle replaces the text and reflows a shorter explanation")
    fixture.section.setSubtitle(fixture.subtitle)
    fixture.layout()
    checks.check(abs(fixture.section.frame.height - originalHeight) < 1,
                 "setSubtitle restores the wrapped section height")

    func separators() -> Int {
        descendants(fixture.section).filter { $0.identifier?.rawValue == "PreferencesSeparator" && visible($0) }.count
    }
    fixture.section.setRowVisibility(0, newState: false)
    fixture.layout()
    checks.check(fixture.rows[0].isHidden && !fixture.rows[1].isHidden && !fixture.rows[2].isHidden &&
                 separators() == 1 && fixture.section.frame.height < originalHeight,
                 "hiding row zero leaves other rows visible and removes its leading separator")
    fixture.section.setRowVisibility("settings-row-last", newState: false)
    fixture.layout()
    checks.check(fixture.rows[2].isHidden && !fixture.rows[1].isHidden && separators() == 0,
                 "hiding a later row by id leaves no dangling separators")
    fixture.section.setRowVisibility(fixture.rows[0], newState: true)
    fixture.section.setRowVisibility(2, newState: true)
    fixture.layout()
    checks.check(fixture.rows.allSatisfy { !$0.isHidden } && separators() == 2 &&
                 abs(fixture.section.frame.height - originalHeight) < 1,
                 "row and index visibility APIs restore all rows, separators and height")
}

private func verifyActions(_ fixture: SettingsFixture, _ checks: Checks) throws {
    var previews = 0
    fixture.popup.previewAction = { previews += 1 }
    try checks.fire(try requiredView(fixture.customization, "popup-preview", LocalActionButton.self),
                    "preview control dispatches its production action")
    checks.check(previews == 1, "preview invokes the supplied callback without showing a window")
    _ = try requiredView(fixture.customization, "popup-history", LocalActionButton.self)

    let clockTools = ["none", "activity", "calendar", "datetime"]
    Store.shared.set(key: "Clock_popup_tools", value: clockTools)
    var notifications: [String] = []
    let token = NotificationCenter.default.addObserver(forName: .localPopupOptionsChanged, object: nil, queue: nil) {
        if let module = $0.object as? String { notifications.append(module) }
    }
    defer { NotificationCenter.default.removeObserver(token) }
    func choose(_ slot: Int, _ id: String) throws {
        let choice = try requiredView(fixture.customization, "popup-tool-choice-\(slot)", LocalChoice.self)
        let index = choice.indexOfItem(withTitle: FooterTools.title(id))
        guard index >= 0 else { throw SettingsCheckError(message: "Missing built-in tool option: " + id) }
        choice.selectItem(at: index)
        try checks.fire(choice, "native tool choice dispatches a built-in option")
        fixture.layout()
    }
    var expected = FooterTools.defaults("CPU")
    try choose(1, "calendar")
    expected[1] = "calendar"
    checks.check(FooterTools.items("CPU") == expected &&
                 UserDefaults.standard.stringArray(forKey: "CPU_popup_tools") == expected,
                 "changing one slot saves the selected tool without changing its neighbors")
    try choose(0, "none")
    expected[0] = "none"
    let rebuilt = fixture.popup.customizationSettings()
    let rebuiltHidden = try requiredView(rebuilt, "popup-tool-choice-0", LocalChoice.self)
    let rebuiltCalendar = try requiredView(rebuilt, "popup-tool-choice-1", LocalChoice.self)
    checks.check(FooterTools.items("CPU") == expected &&
                 rebuiltHidden.selectedItem?.title == FooterTools.title("none") &&
                 rebuiltCalendar.selectedItem?.title == FooterTools.title("calendar"),
                 "hidden and selected tools survive rebuilding the production editor")
    try checks.fire(try requiredView(fixture.customization, "popup-tools-reset", LocalActionButton.self),
                    "reset control dispatches its production action")
    checks.check(!Store.shared.exist(key: "CPU_popup_tools") &&
                 UserDefaults.standard.object(forKey: "CPU_popup_tools") == nil &&
                 FooterTools.items("CPU") == FooterTools.defaults("CPU"),
                 "reset removes the override and restores this module's tool defaults")
    checks.check(Store.shared.array(key: "Clock_popup_tools", defaultValue: []) as? [String] == clockTools &&
                 notifications.count >= 3 && notifications.allSatisfy { $0 == "CPU" },
                 "tool changes notify only their module and leave another module's choices intact")
    fixture.layout()

    let firstUp = try requiredView(try fixture.row(0), "popup-section-up-dashboard", LocalActionButton.self)
    let lastDown = try requiredView(try fixture.row(fixture.sectionIDs.count - 1),
                                   "popup-section-down-processes", LocalActionButton.self)
    checks.check(!firstUp.isEnabled && !lastDown.isEnabled, "first and last section rows disable moves outside the list")
    let original = fixture.popup.orderedSectionIDs()
    var moved = original
    moved.swapAt(2, 3)
    try checks.fire(try requiredView(try fixture.row(2), "popup-section-down-details", LocalActionButton.self),
                    "middle section down button dispatches its production action")
    fixture.layout()
    checks.check(fixture.popup.orderedSectionIDs() == moved &&
                 fixture.popup.arrangedSubviews.compactMap { $0.identifier?.rawValue } == moved.map { "popup-section:" + $0 },
                 "moving a section saves its order and rearranges the real popup")
    try checks.fire(try requiredView(try fixture.row(3), "popup-section-up-details", LocalActionButton.self),
                    "middle section up button dispatches its production action")
    fixture.layout()
    checks.check(fixture.popup.orderedSectionIDs() == original, "moving the section back restores its original order")

    let originalHeight = fixture.popup.frame.height
    var resized: NSSize?
    fixture.popup.sizeCallback = { resized = $0 }
    let toggle = try requiredView(try fixture.row(2), "popup-section-toggle-details", LocalToggle.self)
    toggle.state = .off
    try checks.fire(toggle, "section visibility switch dispatches its production action")
    fixture.layout()
    checks.check(fixture.popup.popupSection("details")?.isHidden == true &&
                 (Store.shared.array(key: "CPU_popup_hiddenSections", defaultValue: []) as? [String] ?? []).contains("details") &&
                 fixture.popup.frame.height < originalHeight && resized == fixture.popup.frame.size,
                 "hiding a section saves its state and reduces the popup through its size callback")
    let restoredToggle = try requiredView(try fixture.row(2), "popup-section-toggle-details", LocalToggle.self)
    restoredToggle.state = .on
    try checks.fire(restoredToggle, "section visibility switch restores the section")
    fixture.layout()
    checks.check(fixture.popup.popupSection("details")?.isHidden == false &&
                 abs(fixture.popup.frame.height - originalHeight) < 0.6,
                 "restoring a section restores the popup height")
}

private func verifyInsertedStackWidth(_ checks: Checks) {
    let host = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 240))
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    let scroll = ScrollableStackView()
    scroll.translatesAutoresizingMaskIntoConstraints = false
    scroll.stackView.edgeInsets = .init(top: 0, left: 8, bottom: 0, right: 8)
    host.addSubview(scroll)
    NSLayoutConstraint.activate([
        scroll.leadingAnchor.constraint(equalTo: host.leadingAnchor),
        scroll.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        scroll.topAnchor.constraint(equalTo: host.topAnchor),
        scroll.bottomAnchor.constraint(equalTo: host.bottomAnchor)
    ])
    func row(_ height: CGFloat) -> NSView {
        let view = NSView()
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }
    let first = row(28), last = row(32), inserted = row(30)
    scroll.stackView.addArrangedSubview(first)
    scroll.stackView.addArrangedSubview(last)
    scroll.stackView.insertArrangedSubview(inserted, at: 1)
    host.layoutSubtreeIfNeeded()
    scroll.stackView.layoutSubtreeIfNeeded()
    let frames = [first, inserted, last].map { $0.convert($0.bounds, to: scroll.stackView) }
    checks.check(scroll.stackView.arrangedSubviews == [first, inserted, last] && frames.allSatisfy {
        abs($0.width - 164) < 0.6 && abs($0.minX - 8) < 0.6 && abs($0.maxX - 172) < 0.6
    }, "a 180pt scroll stack gives added and inserted height-only rows the same 164pt usable width")
}

private func verifyWidgetSizingInputs(_ checks: Checks) throws {
    Store.shared.set(key: "CompactMenuBar", value: false)
    let widget = WidgetWrapper(.pieChart, title: "UIFixture", frame: NSRect(x: 0, y: 0, width: 22, height: 22))
    let other = WidgetWrapper(.barChart, title: "UIFixture", frame: NSRect(x: 0, y: 0, width: 22, height: 22))
    let compactKey = "UIFixture_pie_chart_compact"
    let keys = ["CompactMenuBar", compactKey, widget.dimensionKey, widget.spacingKey, other.dimensionKey, other.spacingKey]
    defer { keys.forEach { Store.shared.remove($0) } }
    [compactKey, widget.dimensionKey, widget.spacingKey].forEach { Store.shared.remove($0) }
    Store.shared.set(key: other.dimensionKey, value: 19)
    Store.shared.set(key: other.spacingKey, value: 9)
    let form = widget.dimensionSettings()
    let compact = try requiredView(form, "widget-compact-toggle", NSSwitch.self)
    func values() throws -> [Int] {
        try ["widget-dimension-input", "widget-spacing-input"].map { id in
            let input = try requiredView(form, id, StepperInput.self)
            guard let field = descendants(input).compactMap({ $0 as? NSTextField }).first(where: { $0.isEditable }),
                  let value = Int(field.stringValue) else {
                throw SettingsCheckError(message: "Missing editable value in production sizing input: " + id)
            }
            return value
        }
    }
    let initial = try values()
    checks.check(initial == [22, 14] && compact.state == .off,
                 "a noncompact pie widget initially displays its 22pt diameter and 14pt spacing defaults")
    compact.state = .on
    try checks.fire(compact, "native compact switch dispatches the widget sizing action")
    let compactDefaults = try values()
    checks.check(compactDefaults == [18, 2] && !Store.shared.exist(key: widget.dimensionKey) &&
                 !Store.shared.exist(key: widget.spacingKey),
                 "compact mode refreshes both inputs without persisting default values as custom overrides")

    Store.shared.set(key: widget.dimensionKey, value: 16)
    Store.shared.set(key: widget.spacingKey, value: 7)
    compact.state = .off
    try checks.fire(compact, "compact off refreshes the sizing form with custom values")
    let customOff = try values()
    compact.state = .on
    try checks.fire(compact, "compact on refreshes the sizing form with custom values")
    let customOn = try values()
    checks.check(customOff == [16, 7] && customOn == [16, 7],
                 "custom diameter and spacing survive switching compact mode off and on")
    Store.shared.remove(compactKey)
    Store.shared.set(key: "CompactMenuBar", value: false)
    NotificationCenter.default.post(name: .toggleOneView, object: nil)
    let globalCustomRegular = try values()
    let customRegularState = compact.state
    Store.shared.set(key: "CompactMenuBar", value: true)
    NotificationCenter.default.post(name: .toggleOneView, object: nil)
    let globalCustomCompact = try values()
    checks.check(globalCustomRegular == [16, 7] && globalCustomCompact == [16, 7] &&
                 customRegularState == .off && compact.state == .on,
                 "global compact changes synchronize the same native switch while preserving custom input values")
    try checks.fire(try requiredView(form, "widget-size-reset", LocalActionButton.self),
                    "native sizing reset dispatches its production action")
    let reset = try values()
    checks.check(reset == [18, 2] && widget.compact && !Store.shared.exist(key: widget.dimensionKey) &&
                 !Store.shared.exist(key: widget.spacingKey) &&
                 Store.shared.int(key: other.dimensionKey, defaultValue: 0) == 19 &&
                 Store.shared.int(key: other.spacingKey, defaultValue: 0) == 9,
                 "reset clears only this widget's custom sizes and refreshes its current compact defaults")

    Store.shared.remove(compactKey)
    Store.shared.set(key: "CompactMenuBar", value: false)
    NotificationCenter.default.post(name: .toggleOneView, object: nil)
    let globalRegular = try values()
    let regularState = compact.state
    Store.shared.set(key: "CompactMenuBar", value: true)
    NotificationCenter.default.post(name: .toggleOneView, object: nil)
    let globalCompact = try values()
    checks.check(globalRegular == [22, 14] && globalCompact == [18, 2] &&
                 regularState == .off && compact.state == .on &&
                 !Store.shared.exist(key: widget.dimensionKey) && !Store.shared.exist(key: widget.spacingKey),
                 "global compact-default notifications synchronize the switch and inputs without creating custom overrides")
}

private func savePreview(_ fixture: SettingsFixture, appearance: NSAppearance,
                         name: String, output: URL, baseline: Bool, checks: Checks) throws {
    NSApp.appearance = appearance
    fixture.window.appearance = appearance
    fixture.host.appearance = appearance
    fixture.caption.stringValue = "Isolated production view · \(baseline ? "baseline" : "checked") · \(name) · \(Int(fixture.width)) pt"
    fixture.window.title = fixture.caption.stringValue
    fixture.layout()
    var bitmap: NSBitmapImageRep?
    appearance.performAsCurrentDrawingAppearance {
        fixture.window.backgroundColor = .windowBackgroundColor
        for view in descendants(fixture.host) {
            view.needsDisplay = true
            if view.wantsLayer { view.updateLayer() }
        }
        bitmap = fixture.host.bitmapImageRepForCachingDisplay(in: fixture.host.bounds)
        if let bitmap { fixture.host.cacheDisplay(in: fixture.host.bounds, to: bitmap) }
    }
    guard let bitmap, let data = bitmap.representation(using: .png, properties: [:]) else {
        throw SettingsCheckError(message: "Could not render the isolated production view")
    }
    let corner = bitmap.colorAt(x: 1, y: 1)?.usingColorSpace(.deviceRGB)
    let brightness = corner.map { ($0.redComponent + $0.greenComponent + $0.blueComponent) / 3 } ?? -1
    checks.check(bitmap.pixelsWide >= Int(fixture.host.bounds.width) && bitmap.pixelsHigh > 100 &&
                 (corner?.alphaComponent ?? 0) > 0.99,
                 "\(name) preview contains an opaque background at the expected size")
    checks.check(name == "dark" ? brightness >= 0 && brightness < 0.5 : brightness > 0.5,
                 "\(name) preview uses the matching semantic window background")
    let filename = "settings-\(baseline ? "baseline" : "checked")-\(name)-\(Int(fixture.width)).png"
    let url = output.appendingPathComponent(filename)
    try data.write(to: url, options: .atomic)
    print("Isolated production view PNG: \(url.path)")
}

@main
private struct SettingsLayoutChecks {
    static func main() {
        do { try run() }
        catch {
            print("Settings checks failed: \(error.localizedDescription)")
            exit(1)
        }
    }

    private static func run() throws {
        setbuf(stdout, nil)
        let domain = ProcessInfo.processInfo.processName
        guard Bundle.main.bundleIdentifier == nil, domain.hasPrefix("stats-settings-checks-") else {
            throw SettingsCheckError(message: "Settings checks require an isolated uniquely named executable")
        }
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        guard let index = CommandLine.arguments.firstIndex(of: "--output-dir"),
              CommandLine.arguments.indices.contains(index + 1) else {
            throw SettingsCheckError(message: "--output-dir is required")
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
        let baseline = CommandLine.arguments.contains("--render-only")
        let checks = Checks()
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        print("Settings checks locale: \(Locale.current.identifier); languages: \(Locale.preferredLanguages)")
        print("Helper resources: \(Bundle.main.resourceURL?.path ?? "unavailable"); localizations: \(Bundle.main.preferredLocalizations)")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        do {
            for width: CGFloat in [540, 680] {
                Store.shared.remove("CPU_popup_tools")
                Store.shared.remove("CPU_popup_sectionOrder")
                Store.shared.remove("CPU_popup_hiddenSections")
                app.appearance = NSAppearance(named: .aqua)
                let fixture = SettingsFixture(width: width)
                defer { fixture.window.close() }
                if !baseline {
                    try verifyGeometry(fixture, checks)
                    verifySectionAPIs(fixture, checks)
                    if width == 540 {
                        try verifyActions(fixture, checks)
                        verifyInsertedStackWidth(checks)
                        try verifyWidgetSizingInputs(checks)
                    }
                }
                for (name, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
                    guard let appearance = NSAppearance(named: appearanceName) else {
                        throw SettingsCheckError(message: "Missing native appearance " + name)
                    }
                    try savePreview(fixture, appearance: appearance, name: name, output: output,
                                    baseline: baseline, checks: checks)
                }
            }
        } catch {
            checks.check(false, error.localizedDescription)
        }
        print("Settings AppKit checks: \(checks.count) checks, \(checks.failures) failures" +
              (baseline ? "; render-only baseline, layout and action assertions skipped" : ""))
        if checks.failures > 0 { throw SettingsCheckError(message: "Settings checks failed") }
    }
}
