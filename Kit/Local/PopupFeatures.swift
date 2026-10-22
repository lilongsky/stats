import Cocoa
import UniformTypeIdentifiers

public enum FooterTools {
    public static let catalog: [(id: String, title: String, bundle: String?, path: String?)] = [
        ("none", "Hidden", nil, nil),
        ("activity", "Activity Monitor", "com.apple.ActivityMonitor", "/System/Applications/Utilities/Activity Monitor.app"),
        ("console", "Console", "com.apple.Console", "/System/Applications/Utilities/Console.app"),
        ("terminal", "Terminal", "com.apple.Terminal", "/System/Applications/Utilities/Terminal.app"),
        ("system", "System Information", "com.apple.SystemProfiler", "/System/Applications/Utilities/System Information.app"),
        ("disk", "Disk Utility", "com.apple.DiskUtility", "/System/Applications/Utilities/Disk Utility.app"),
        ("network", "Network Settings", nil, "x-apple.systempreferences:com.apple.Network-Settings.extension"),
        ("battery", "Battery Settings", nil, "x-apple.systempreferences:com.apple.Battery-Settings.extension"),
        ("bluetooth", "Bluetooth Settings", nil, "x-apple.systempreferences:com.apple.BluetoothSettings"),
        ("datetime", "Date & Time Settings", nil, "x-apple.systempreferences:com.apple.Date-Time-Settings.extension"),
        ("calendar", "Calendar", "com.apple.iCal", "/System/Applications/Calendar.app")
    ]
    public static let historyModules = ["CPU", "GPU", "RAM", "Disk", "Network", "Sensors", "Battery"]
    public static func defaults(_ module: String) -> [String] {
        switch module {
        case "Disk": return ["activity", "console", "terminal", "disk"]
        case "Network": return ["activity", "console", "terminal", "network"]
        case "Battery": return ["activity", "console", "terminal", "battery"]
        case "Clock": return ["activity", "console", "calendar", "datetime"]
        case "Bluetooth": return ["activity", "console", "system", "bluetooth"]
        default: return ["activity", "console", "terminal", "system"]
        }
    }
    public static func items(_ module: String) -> [String] {
        let saved = Store.shared.array(key: "\(module)_popup_tools", defaultValue: []) as? [String] ?? []
        return saved.count == 4 ? saved : self.defaults(module)
    }
    public static func url(_ id: String) -> URL? {
        if id.hasPrefix("/") { return URL(fileURLWithPath: id) }
        guard let item = self.catalog.first(where: { $0.id == id }), let path = item.path else { return nil }
        if path.hasPrefix("x-apple.") { return URL(string: path) }
        if let bundle = item.bundle, let found = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            return found
        }
        return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }
    public static func title(_ id: String) -> String {
        self.catalog.first(where: { $0.id == id }).map { localizedString($0.title) } ??
            FileManager.default.displayName(atPath: id).replacingOccurrences(of: ".app", with: "")
    }
    public static func icon(_ id: String) -> NSImage {
        if let url = self.url(id), url.isFileURL { return NSWorkspace.shared.icon(forFile: url.path) }
        let symbol: String
        switch id {
        case "network": symbol = "network"
        case "battery": symbol = "battery.100"
        case "bluetooth": symbol = "gearshape"
        case "datetime": symbol = "calendar.badge.clock"
        default: symbol = "gearshape"
        }
        return NSImage(systemSymbolName: symbol, accessibilityDescription: self.title(id))?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)) ?? NSImage()
    }
}

internal final class FooterToolsEditor: NSStackView {
    private let module: String
    init(module: String) {
        self.module = module
        super.init(frame: .zero)
        self.orientation = .vertical
        self.alignment = .leading
        self.spacing = 0
        self.identifier = NSUserInterfaceItemIdentifier("popup-tools-editor")
        self.reload()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func reload() {
        self.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let saved = FooterTools.items(self.module)
        for slot in 0..<4 {
            var options = FooterTools.catalog.map { $0.id }
            if saved[slot].hasPrefix("/") { options.append(saved[slot]) }
            let titles = options.map(FooterTools.title) + [localizedString("Choose Application…")]
            let selected = options.firstIndex(of: saved[slot]) ?? 0
            let choice = LocalChoice(titles, selected: selected) { [weak self] index in
                guard let self else { return }
                var selectedID: String?
                if index < options.count {
                    selectedID = options[index]
                } else {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.applicationBundle]
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    panel.directoryURL = URL(fileURLWithPath: "/Applications")
                    panel.prompt = localizedString("Choose Application")
                    if panel.runModal() == .OK { selectedID = panel.url?.path }
                }
                if let selectedID {
                    var items = FooterTools.items(self.module)
                    items[slot] = selectedID
                    Store.shared.set(key: "\(self.module)_popup_tools", value: items)
                    NotificationCenter.default.post(name: .localPopupOptionsChanged, object: self.module)
                }
                self.reload()
            }
            choice.identifier = NSUserInterfaceItemIdentifier("popup-tool-choice-\(slot)")
            for (index, id) in options.enumerated() where id != "none" {
                let icon = FooterTools.icon(id).copy() as! NSImage
                icon.size = NSSize(width: 16, height: 16)
                choice.item(at: index)?.image = icon
            }
            let row = PreferencesRow(String(format: localizedString("Shortcut %d"), slot + 1), component: choice)
            self.addArrangedSubview(row)
            fillSettingsWidth(row, in: self)
            let separator = NSBox()
            separator.boxType = .separator
            self.addArrangedSubview(separator)
            fillSettingsWidth(separator, in: self)
        }
        let reset = LocalActionButton(localizedString("Restore Default Tools")) { [weak self] in
            guard let self else { return }
            Store.shared.remove("\(self.module)_popup_tools")
            self.reload()
            NotificationCenter.default.post(name: .localPopupOptionsChanged, object: self.module)
        }
        reset.identifier = NSUserInterfaceItemIdentifier("popup-tools-reset")
        let resetRow = PreferencesRow(localizedString("Tool preset"), component: reset)
        self.addArrangedSubview(resetRow)
        fillSettingsWidth(resetRow, in: self)
    }
}

public extension PopupWrapper {
    func addPopupSection(_ view: NSView, id: String, title: String, before nextID: String? = nil) {
        view.identifier = NSUserInterfaceItemIdentifier("popup-section:" + id)
        self.popupSectionTitles[id] = title
        if !self.popupSectionOrder.contains(id) {
            if let nextID, let index = self.popupSectionOrder.firstIndex(of: nextID) {
                self.popupSectionOrder.insert(id, at: index)
            } else {
                self.popupSectionOrder.append(id)
            }
        }
        self.popupSectionHeights[id] = view.frame.height
        self.addArrangedSubview(view)
    }
    func popupSection(_ id: String) -> NSView? {
        self.arrangedSubviews.first { $0.identifier?.rawValue == "popup-section:" + id }
    }
    func orderedSectionIDs() -> [String] {
        let saved = Store.shared.array(key: "\(self.title)_popup_sectionOrder", defaultValue: []) as? [String] ?? []
        return saved.filter { self.popupSectionOrder.contains($0) } +
            self.popupSectionOrder.filter { !saved.contains($0) }
    }
    @discardableResult func applySectionLayout() -> NSSize {
        let ordered = self.orderedSectionIDs().compactMap { self.popupSection($0) }
        guard !ordered.isEmpty else { return self.frame.size }
        let hidden = Store.shared.array(key: "\(self.title)_popup_hiddenSections", defaultValue: []) as? [String] ?? []
        if ordered != self.arrangedSubviews {
            ordered.forEach { self.removeArrangedSubview($0) }
            ordered.forEach { self.addArrangedSubview($0) }
        }
        var height: CGFloat = 0
        var visibleCount = 0
        for view in ordered {
            let id = String((view.identifier?.rawValue ?? "").dropFirst("popup-section:".count))
            if !view.isHidden {
                self.popupSectionHeights[id] = max(view.frame.height, view.fittingSize.height)
            }
            view.isHidden = hidden.contains(id)
            if !view.isHidden {
                height += max(view.frame.height, view.fittingSize.height, self.popupSectionHeights[id] ?? 0)
                visibleCount += 1
            }
        }
        height += CGFloat(max(0, visibleCount - 1)) * self.spacing + self.edgeInsets.top + self.edgeInsets.bottom
        let size = NSSize(width: self.frame.width, height: height)
        if self.frame.size != size { self.setFrameSize(size) }
        return size
    }
    func customizationSettings() -> NSView {
        let view = SettingsContainerView()
        view.identifier = NSUserInterfaceItemIdentifier("popup-customization")
        let preview = NSStackView()
        preview.orientation = .horizontal
        preview.spacing = 8
        let previewButton = LocalActionButton(localizedString("Preview Popup"), symbol: "macwindow") { [weak self] in self?.previewAction?() }
        previewButton.identifier = NSUserInterfaceItemIdentifier("popup-preview")
        preview.addArrangedSubview(previewButton)
        if FooterTools.historyModules.contains(self.title) {
            let historyButton = LocalActionButton(localizedString("View History"), symbol: "clock.arrow.circlepath") { [weak self] in
                if let self { HistoryWindow.show(module: self.title) }
            }
            historyButton.identifier = NSUserInterfaceItemIdentifier("popup-history")
            preview.addArrangedSubview(historyButton)
        }
        preview.addArrangedSubview(NSView())
        view.addArrangedSubview(preview)
        if !self.popupSectionOrder.isEmpty {
            view.addArrangedSubview(PreferencesSection(title: localizedString("Popup Sections"),
                subtitle: localizedString("Drag sections to reorder them. Use the switches to choose what appears."), id: "popup-settings-sections", [
                PopupSectionsEditor(popup: self)
            ]))
        }
        view.addArrangedSubview(PreferencesSection(title: localizedString("Shortcut Tools"),
            subtitle: localizedString("Choose the applications shown at the bottom of this popup."), id: "popup-settings-tools", [
            FooterToolsEditor(module: self.title)
        ]))
        return view
    }
}

private final class PopupSectionsEditor: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private weak var popup: PopupWrapper?
    private let table = NSTableView()
    private var ids: [String] = []
    private let dragType = NSPasteboard.PasteboardType("eu.exelban.Stats.Compact.popupSection")
    init(popup: PopupWrapper) {
        self.popup = popup
        self.ids = popup.orderedSectionIDs()
        super.init(frame: .zero)
        self.identifier = NSUserInterfaceItemIdentifier("popup-section-editor")
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = self.ids.count > 8
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        self.addSubview(scroll)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("section"))
        column.width = 340
        self.table.addTableColumn(column)
        self.table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        self.table.headerView = nil
        // The surrounding card supplies insets; automatic style adds vertical
        // table padding that would clip the last row in this fixed-height list.
        self.table.style = .plain
        self.table.rowHeight = 36
        self.table.intercellSpacing = .zero
        self.table.autoresizingMask = [.width]
        self.table.identifier = NSUserInterfaceItemIdentifier("popup-sections-table")
        self.table.backgroundColor = .clear
        self.table.dataSource = self
        self.table.delegate = self
        self.table.registerForDraggedTypes([self.dragType])
        self.table.setDraggingSourceOperationMask(.move, forLocal: true)
        scroll.documentView = self.table
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: self.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            self.heightAnchor.constraint(equalToConstant: CGFloat(min(8, max(1, self.ids.count))) * 36)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func numberOfRows(in tableView: NSTableView) -> Int { self.ids.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let popup, row < self.ids.count else { return nil }
        let id = self.ids[row]
        let hidden = Store.shared.array(key: "\(popup.title)_popup_hiddenSections", defaultValue: []) as? [String] ?? []
        let line = NSStackView()
        line.orientation = .horizontal
        line.spacing = 8
        line.edgeInsets = .init(top: 4, left: 2, bottom: 4, right: 2)
        let handle = NSImageView(image: NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil) ?? NSImage())
        handle.contentTintColor = .tertiaryLabelColor
        handle.widthAnchor.constraint(equalToConstant: 14).isActive = true
        line.addArrangedSubview(handle)
        let title = NSTextField(labelWithString: localizedString(popup.popupSectionTitles[id] ?? id))
        title.font = .systemFont(ofSize: 13)
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        line.addArrangedSubview(title)
        line.addArrangedSubview(NSView())
        let toggle = LocalToggle(!hidden.contains(id)) { [weak self] visible in
            guard let self, let popup = self.popup else { return }
            var hidden = Store.shared.array(key: "\(popup.title)_popup_hiddenSections", defaultValue: []) as? [String] ?? []
            hidden.removeAll { $0 == id }
            if !visible { hidden.append(id) }
            Store.shared.set(key: "\(popup.title)_popup_hiddenSections", value: hidden)
            self.changed()
        }
        toggle.identifier = NSUserInterfaceItemIdentifier("popup-section-toggle-\(id)")
        toggle.setAccessibilityLabel(title.stringValue)
        let up = LocalActionButton("", symbol: "chevron.up") { [weak self] in self?.move(row, to: row - 1) }
        let down = LocalActionButton("", symbol: "chevron.down") { [weak self] in self?.move(row, to: row + 1) }
        up.identifier = NSUserInterfaceItemIdentifier("popup-section-up-\(id)")
        down.identifier = NSUserInterfaceItemIdentifier("popup-section-down-\(id)")
        up.setAccessibilityLabel(localizedString("Move Section Up"))
        down.setAccessibilityLabel(localizedString("Move Section Down"))
        for button in [up, down] {
            button.isBordered = false
            button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        }
        up.isEnabled = row > 0
        down.isEnabled = row + 1 < self.ids.count
        line.addArrangedSubview(up)
        line.addArrangedSubview(down)
        line.addArrangedSubview(toggle)
        return line
    }
    private func move(_ from: Int, to: Int) {
        guard self.ids.indices.contains(from), self.ids.indices.contains(to) else { return }
        let id = self.ids.remove(at: from)
        self.ids.insert(id, at: to)
        if let popup { Store.shared.set(key: "\(popup.title)_popup_sectionOrder", value: self.ids) }
        self.table.reloadData()
        self.changed()
    }
    private func changed() {
        guard let popup else { return }
        let size = popup.applySectionLayout()
        popup.sizeCallback?(size)
    }
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(self.ids[row], forType: self.dragType)
        return item
    }
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                   proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        operation == .above && info.draggingSource as? NSTableView === self.table ? .move : []
    }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
                   row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let id = info.draggingPasteboard.string(forType: self.dragType),
              let from = self.ids.firstIndex(of: id) else { return false }
        self.move(from, to: min(self.ids.count-1, row > from ? row-1 : row))
        return true
    }
}
