//
//  Settings.swift
//  Stats
//
//  Created by Serhiy Mytrovtsiy on 12/04/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

public extension NSToolbarItem.Identifier {
    static let previewButton = NSToolbarItem.Identifier("previewButton")
    static let settingsSidebarSeparator = NSToolbarItem.Identifier("settingsSidebarSeparator")
}

class SettingsWindow: NSWindow, NSWindowDelegate, NSToolbarDelegate {
    private static let size: CGSize = CGSize(width: 860, height: 620)
    private static let frameAutosaveName = "eu.exelban.Stats.Settings.WindowFrame"
    
    internal var onClose: (() -> Void)?
    
    private let mainView: MainView = MainView(frame: NSRect(x: 0, y: 0, width: 660, height: 620))
    private let sidebarView: SidebarView = SidebarView(frame: NSRect(x: 0, y: 0, width: 200, height: 620))
    private weak var settingsSplitView: NSSplitView?
    
    private var dashboard: NSView = Dashboard()
    private var settings: ApplicationSettings = ApplicationSettings()
    
    private var toggleButton: NSControl? = nil
    private var moduleToggleView: NSView? = nil
    private var activeModuleName: String? = nil
    private var visibleModuleName: String? = nil
    private var settingsPreviewButton: SettingsPreviewButton? = nil
    private static var modulePreviewStates: [String: Bool] = [:]
    
    init() {
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SettingsWindow.size.width,
                height: SettingsWindow.size.height
            ),
            styleMask: [.closable, .titled, .miniaturizable, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        
        self.toggleButton = self.mainView.moduleSwitch
        self.toggleButton?.target = self
        self.toggleButton?.action = #selector(self.toggleEnable)
        self.moduleToggleView = self.mainView.moduleHeader

        let sidebarViewController = NSSplitViewController()
        self.settingsSplitView = sidebarViewController.splitView
        
        let sidebarVC: NSViewController = NSViewController(nibName: nil, bundle: nil)
        sidebarVC.view = self.sidebarView
        let mainVC: NSViewController = NSViewController(nibName: nil, bundle: nil)
        mainVC.view = self.mainView
        
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        let contentItem = NSSplitViewItem(viewController: mainVC)
        
        sidebarItem.canCollapse = false
        contentItem.canCollapse = false
        
        sidebarViewController.addSplitViewItem(sidebarItem)
        sidebarViewController.addSplitViewItem(contentItem)
        
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 240
        sidebarItem.preferredThicknessFraction = 200 / SettingsWindow.size.width
        contentItem.minimumThickness = 540
        
        let newToolbar = NSToolbar(identifier: "eu.exelban.Stats.Settings.Toolbar")
        newToolbar.allowsUserCustomization = false
        newToolbar.autosavesConfiguration = false
        newToolbar.displayMode = .iconOnly
        newToolbar.showsBaselineSeparator = true
        newToolbar.delegate = self
        
        self.toolbar = newToolbar
        self.toolbarStyle = .unified
        self.contentViewController = sidebarViewController
        self.titlebarAppearsTransparent = true
        self.backgroundColor = .windowBackgroundColor
        self.isRestorable = true
        self.isReleasedWhenClosed = false
        self.delegate = self
        self.setFrameAutosaveName(SettingsWindow.frameAutosaveName)
        if !self.setFrameUsingName(SettingsWindow.frameAutosaveName) {
            self.positionCenter()
        }
        self.setIsVisible(false)
        self.minSize = NSSize(width: 760, height: 520)
        var restoredFrame = self.frame
        if restoredFrame.width < self.minSize.width || restoredFrame.height < self.minSize.height {
            restoredFrame.size.width = max(restoredFrame.width, self.minSize.width)
            restoredFrame.size.height = max(restoredFrame.height, self.minSize.height)
            self.setFrame(restoredFrame, display: false)
        }
        self.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        self.standardWindowButton(.zoomButton)?.isEnabled = false
        
        let windowController = NSWindowController()
        windowController.window = self
        windowController.loadWindow()
        
        NotificationCenter.default.addObserver(self, selector: #selector(menuCallback), name: .openModuleSettings, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(externalModuleToggle), name: .toggleModule, object: nil)
        
        self.sidebarView.setModules(modules)
        self.sidebarView.openMenu("Dashboard")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .openModuleSettings, object: nil)
        NotificationCenter.default.removeObserver(self, name: .toggleModule, object: nil)
    }
    
    func windowWillClose(_ notification: Notification) {
        self.updateReaderVisibility(visible: false)
        let onClose = self.onClose
        DispatchQueue.main.async {
            onClose?()
        }
    }

    override func setIsVisible(_ flag: Bool) {
        super.setIsVisible(flag)
        self.updateReaderVisibility(visible: flag && !self.isMiniaturized)
    }

    func windowDidMiniaturize(_ notification: Notification) {
        self.updateReaderVisibility(visible: false)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        self.updateReaderVisibility()
    }

    private func updateReaderVisibility(visible: Bool? = nil) {
        let name = (visible ?? (self.isVisible && !self.isMiniaturized)) ? self.activeModuleName : nil
        guard name != self.visibleModuleName else { return }
        self.visibleModuleName = name
        var info: [String: Any] = ["state": name != nil]
        if let name { info["module"] = name }
        NotificationCenter.default.post(name: .openWindow, object: self, userInfo: info)
    }
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == NSEvent.EventType.keyDown && event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "w":
                self.close()
                return true
            case "q":
                NSApp.terminate(self)
                return true
            case ",":
                self.sidebarView.openMenu("Settings")
                return true
            case "m":
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
    
    override func mouseUp(with: NSEvent) {
        NotificationCenter.default.post(name: .clickInSettings, object: nil, userInfo: nil)
    }
    
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .settingsSidebarSeparator:
            guard let splitView = self.settingsSplitView else { return nil }
            return NSTrackingSeparatorToolbarItem(identifier: itemIdentifier, splitView: splitView, dividerIndex: 0)
        case .previewButton:
            let button = SettingsPreviewButton { [weak self] in
                guard let self, let moduleName = self.activeModuleName else { return }
                let visible = !(SettingsWindow.modulePreviewStates[moduleName] ?? true)
                SettingsWindow.modulePreviewStates[moduleName] = visible
                self.settingsPreviewButton?.setPreviewVisible(visible)
                self.toolbar?.items.first { $0.itemIdentifier == .previewButton }?.label = self.settingsPreviewButton?.title ?? localizedString("Preview")
                NotificationCenter.default.post(name: .togglePreview, object: nil, userInfo: ["module": moduleName])
            }
            self.settingsPreviewButton = button
            
            let toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)
            toolbarItem.label = localizedString("Preview")
            toolbarItem.view = button
            toolbarItem.isBordered = false
            
            return toolbarItem
        default:
            return nil
        }
    }
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.settingsSidebarSeparator, .flexibleSpace, .previewButton]
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.settingsSidebarSeparator, .flexibleSpace]
    }

    private func setPreviewAvailable(_ available: Bool) {
        guard let toolbar = self.toolbar else { return }
        let index = toolbar.items.firstIndex { $0.itemIdentifier == .previewButton }
        if available {
            if index == nil {
                toolbar.insertItem(withItemIdentifier: .previewButton, at: toolbar.items.count)
            }
            if let moduleName = self.activeModuleName {
                self.settingsPreviewButton?.setPreviewVisible(SettingsWindow.modulePreviewStates[moduleName] ?? true)
                toolbar.items.first { $0.itemIdentifier == .previewButton }?.label = self.settingsPreviewButton?.title ?? localizedString("Preview")
            }
        } else if let index {
            toolbar.removeItem(at: index)
            self.settingsPreviewButton = nil
        }
    }
    
    internal func open(module: String? = nil) {
        if !self.isVisible {
            self.setIsVisible(true)
            self.makeKeyAndOrderFront(nil)
        }
        if !self.isKeyWindow {
            self.orderFrontRegardless()
        }
        
        if var name = module {
            if name == "Combined modules" { name = "Dashboard" }
            self.sidebarView.openMenu(name)
        }
        self.updateReaderVisibility()
    }
    
    @objc private func menuCallback(_ notification: Notification) {
        if let title = notification.userInfo?["module"] as? String {
            var view: NSView = NSView()
            if let detectedModule = modules.first(where: { $0.config.name == title }) {
                if let v = detectedModule.window {
                    view = v
                }
                self.activeModuleName = detectedModule.config.name
                toggleNSControlState(self.toggleButton, state: detectedModule.enabled ? .on : .off)
                self.moduleToggleView?.isHidden = false
                self.setPreviewAvailable(detectedModule.config.hasPreview)
            } else if title == "Dashboard" {
                self.activeModuleName = nil
                view = self.dashboard
                self.moduleToggleView?.isHidden = true
                self.setPreviewAvailable(false)
            } else if title == "Settings" {
                self.activeModuleName = nil
                self.settings.viewWillAppear()
                view = self.settings
                self.moduleToggleView?.isHidden = true
                self.setPreviewAvailable(false)
            }
            
            self.title = localizedString(title)
            
            self.mainView.setView(view)
            self.sidebarView.openMenu(title)
            self.updateReaderVisibility()
        }
    }
    
    @objc private func toggleEnable(_ sender: NSControl) {
        guard let moduleName = self.activeModuleName else { return }
        NotificationCenter.default.post(name: .toggleModule, object: nil, userInfo: ["module": moduleName, "state": controlState(sender)])
    }
    
    @objc private func externalModuleToggle(_ notification: Notification) {
        if let name = notification.userInfo?["module"] as? String, name == self.activeModuleName {
            if let state = notification.userInfo?["state"] as? Bool {
                toggleNSControlState(self.toggleButton, state: state ? .on : .off)
            }
        }
    }
    
    private func positionCenter() {
        guard let screen = NSScreen.main else {
            self.center()
            return
        }
        self.setFrameOrigin(NSPoint(
            x: (screen.frame.width - SettingsWindow.size.width)/2,
            y: ((screen.frame.height - SettingsWindow.size.height)/1.75)
        ))
    }
}

// MARK: - MainView

private class MainView: NSView {
    fileprivate let container = NSStackView()
    fileprivate let moduleHeader = NSStackView()
    fileprivate let moduleSwitch = NSSwitch()

    override init(frame: NSRect) {
        super.init(frame: frame)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.wantsLayer = true

        let label = NSTextField(labelWithString: localizedString("Enable module"))
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        self.moduleSwitch.controlSize = .small
        self.moduleSwitch.setAccessibilityLabel(localizedString("Enable module"))
        self.moduleSwitch.toolTip = localizedString("Toggle the module")
        self.moduleSwitch.state = .on
        self.moduleHeader.translatesAutoresizingMaskIntoConstraints = false
        self.moduleHeader.orientation = .horizontal
        self.moduleHeader.distribution = .fill
        self.moduleHeader.alignment = .centerY
        self.moduleHeader.spacing = 12
        self.moduleHeader.edgeInsets = NSEdgeInsets(top: 12, left: 24, bottom: 12, right: 24)
        self.moduleHeader.setHuggingPriority(.required, for: .vertical)
        self.moduleHeader.addArrangedSubview(label)
        self.moduleHeader.addArrangedSubview(NSView())
        self.moduleHeader.addArrangedSubview(self.moduleSwitch)
        self.moduleHeader.isHidden = true

        self.container.translatesAutoresizingMaskIntoConstraints = false
        self.container.orientation = .vertical
        self.container.alignment = .leading
        self.container.setHuggingPriority(.defaultLow, for: .horizontal)
        self.container.setHuggingPriority(.defaultLow, for: .vertical)

        let body = NSStackView(views: [self.moduleHeader, self.container])
        body.translatesAutoresizingMaskIntoConstraints = false
        body.orientation = .vertical
        body.alignment = .leading
        body.distribution = .fill
        body.detachesHiddenViews = true
        body.spacing = 0
        self.addSubview(body)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            body.topAnchor.constraint(equalTo: self.safeAreaLayoutGuide.topAnchor),
            body.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            self.moduleHeader.widthAnchor.constraint(equalTo: body.widthAnchor),
            self.container.widthAnchor.constraint(equalTo: body.widthAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        self.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        self.needsDisplay = true
    }

    fileprivate func setView(_ view: NSView) {
        self.container.arrangedSubviews.forEach { $0.removeFromSuperview() }
        self.container.addArrangedSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: self.container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: self.container.trailingAnchor),
            view.topAnchor.constraint(equalTo: self.container.topAnchor),
            view.bottomAnchor.constraint(equalTo: self.container.bottomAnchor)
        ])
    }
}

// MARK: - Sidebar

private class SidebarView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private struct Entry {
        let title: String
        let icon: NSImage?
        var isGroup: Bool = false
    }

    private let tableView = NSTableView()
    private let moreButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private var pauseMenuItem: NSMenuItem?
    private var entries: [Entry] = []
    private var selectedTitle: String?
    private var isUpdatingSelection = false

    private var pauseState: Bool {
        get { Store.shared.bool(key: "pause", defaultValue: false) }
        set { Store.shared.set(key: "pause", value: newValue) }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        self.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("settings-navigation"))
        column.resizingMask = .autoresizingMask
        self.tableView.addTableColumn(column)
        self.tableView.identifier = NSUserInterfaceItemIdentifier("settings-sidebar")
        self.tableView.headerView = nil
        self.tableView.style = .sourceList
        self.tableView.selectionHighlightStyle = .sourceList
        self.tableView.backgroundColor = .clear
        self.tableView.rowSizeStyle = .medium
        self.tableView.rowHeight = 30
        self.tableView.intercellSpacing = NSSize(width: 0, height: 2)
        self.tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        self.tableView.allowsEmptySelection = false
        self.tableView.allowsMultipleSelection = false
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.setAccessibilityLabel(localizedString("Settings"))
        scrollView.documentView = self.tableView

        self.moreButton.translatesAutoresizingMaskIntoConstraints = false
        self.moreButton.identifier = NSUserInterfaceItemIdentifier("settings-more-menu")
        self.moreButton.controlSize = .small
        self.moreButton.bezelStyle = .texturedRounded
        self.moreButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        self.moreButton.setAccessibilityLabel(localizedString("More"))
        self.moreButton.toolTip = localizedString("More")
        self.moreButton.menu = self.makeMoreMenu()
        self.moreButton.setContentHuggingPriority(.required, for: .horizontal)

        self.addSubview(scrollView)
        self.addSubview(self.moreButton)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: self.safeAreaLayoutGuide.topAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: self.moreButton.topAnchor, constant: -12),
            self.moreButton.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 12),
            self.moreButton.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -12)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(listenForPause), name: .pause, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: .pause, object: nil)
    }

    fileprivate func openMenu(_ title: String) {
        guard let row = self.entries.firstIndex(where: { !$0.isGroup && $0.title == title }) else { return }
        guard self.selectedTitle != title else { return }
        self.selectedTitle = title
        self.isUpdatingSelection = true
        self.tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        self.tableView.scrollRowToVisible(row)
        self.isUpdatingSelection = false
        NotificationCenter.default.post(name: .openModuleSettings, object: nil, userInfo: ["module": title])
    }

    fileprivate func setModules(_ list: [Module]) {
        self.entries = [
            Entry(title: "Dashboard", icon: NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)),
            Entry(title: "Settings", icon: NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil))
        ]
        let available = list.filter { $0.available }
        if !available.isEmpty {
            self.entries.append(Entry(title: "Modules", icon: nil, isGroup: true))
            self.entries.append(contentsOf: available.map { Entry(title: $0.config.name, icon: $0.config.icon) })
        }
        self.tableView.reloadData()
        if let title = self.selectedTitle,
           let row = self.entries.firstIndex(where: { !$0.isGroup && $0.title == title }) {
            self.isUpdatingSelection = true
            self.tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            self.isUpdatingSelection = false
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        self.entries.count
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        self.entries[row].isGroup
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        !self.entries[row].isGroup
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        self.entries[row].isGroup ? 28 : 30
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = self.entries[row]
        let identifier = NSUserInterfaceItemIdentifier(entry.isGroup ? "settings-sidebar-group" : "settings-sidebar-item")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? SidebarCell
            ?? SidebarCell(identifier: identifier, isGroup: entry.isGroup)
        cell.textField?.stringValue = localizedString(entry.title)
        cell.imageView?.image = entry.icon
        cell.toolTip = localizedString(entry.title)
        cell.setAccessibilityLabel(localizedString(entry.title))
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !self.isUpdatingSelection else { return }
        let row = self.tableView.selectedRow
        guard self.entries.indices.contains(row), !self.entries[row].isGroup else { return }
        self.openMenu(self.entries[row].title)
    }

    private func makeMoreMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let label = NSMenuItem(title: localizedString("More"), action: nil, keyEquivalent: "")
        label.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)
        menu.addItem(label)

        let support = NSMenuItem(title: localizedString("Support the application"), action: nil, keyEquivalent: "")
        support.image = NSImage(systemSymbolName: "heart", accessibilityDescription: nil)
        let supportMenu = NSMenu()
        let destinations = [
            ("System Stats", "https://www.system-stats.com"),
            ("GitHub Sponsors", "https://github.com/sponsors/exelban"),
            ("PayPal", "https://www.paypal.com/donate?hosted_button_id=3DS5JHDBATMTC"),
            ("Ko-fi", "https://ko-fi.com/exelban"),
            ("Patreon", "https://patreon.com/exelban")
        ]
        for (title, address) in destinations {
            let item = NSMenuItem(title: title, action: #selector(openSupportLink), keyEquivalent: "")
            item.target = self
            item.representedObject = address
            supportMenu.addItem(item)
        }
        support.submenu = supportMenu
        menu.addItem(support)

        let report = NSMenuItem(title: localizedString("Report a bug"), action: #selector(reportBug), keyEquivalent: "")
        report.target = self
        report.image = NSImage(systemSymbolName: "ladybug", accessibilityDescription: nil)
        menu.addItem(report)
        menu.addItem(.separator())

        let pause = NSMenuItem(title: "", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        self.pauseMenuItem = pause
        self.updatePauseMenuItem()
        menu.addItem(pause)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: localizedString("Close application"), action: #selector(closeApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    @objc private func openSupportLink(_ sender: NSMenuItem) {
        guard let address = sender.representedObject as? String, let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func reportBug() {
        NSWorkspace.shared.open(URL(string: "https://github.com/exelban/stats/issues/new?template=bug_report.yml")!)
    }

    @objc private func closeApp(_ sender: Any?) {
        NSApp.terminate(sender)
    }

    @objc private func togglePause() {
        self.pauseState = !self.pauseState
        self.updatePauseMenuItem()
        NotificationCenter.default.post(name: .pause, object: nil, userInfo: ["state": self.pauseState])
    }

    @objc private func listenForPause() {
        self.updatePauseMenuItem()
    }

    private func updatePauseMenuItem() {
        self.pauseMenuItem?.title = localizedString(self.pauseState ? "Resume the Stats" : "Pause the Stats")
        self.pauseMenuItem?.image = NSImage(systemSymbolName: self.pauseState ? "play" : "pause", accessibilityDescription: nil)
    }
}

private class SidebarCell: NSTableCellView {
    private let isGroup: Bool

    init(identifier: NSUserInterfaceItemIdentifier, isGroup: Bool) {
        self.isGroup = isGroup
        super.init(frame: .zero)
        self.identifier = identifier

        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: isGroup ? NSFont.smallSystemFontSize : NSFont.systemFontSize, weight: isGroup ? .semibold : .regular)
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        self.textField = label
        self.addSubview(label)

        if isGroup {
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -6),
                label.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -4)
            ])
        } else {
            let icon = NSImageView()
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.imageScaling = .scaleProportionallyDown
            self.imageView = icon
            self.addSubview(icon)
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 6),
                icon.centerYAnchor.constraint(equalTo: self.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 16),
                icon.heightAnchor.constraint(equalToConstant: 16),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: self.centerYAnchor)
            ])
        }
        self.updateColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { self.updateColors() }
    }

    private func updateColors() {
        if self.isGroup {
            self.textField?.textColor = .secondaryLabelColor
        } else {
            let selected = self.backgroundStyle == .emphasized
            self.textField?.textColor = selected ? .alternateSelectedControlTextColor : .labelColor
            self.imageView?.contentTintColor = selected ? .alternateSelectedControlTextColor : .controlAccentColor
        }
    }
}

private class SettingsPreviewButton: NSButton {
    private let callback: () -> Void

    fileprivate init(callback: @escaping () -> Void) {
        self.callback = callback
        super.init(frame: .zero)
        self.controlSize = .small
        self.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        self.bezelStyle = .rounded
        self.imagePosition = .imageLeading
        self.target = self
        self.action = #selector(toggleView)
        self.setPreviewVisible(true)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    fileprivate func setPreviewVisible(_ visible: Bool) {
        self.title = localizedString(visible ? "Settings" : "Preview")
        self.image = NSImage(systemSymbolName: visible ? "slider.horizontal.3" : "macwindow", accessibilityDescription: nil)
        self.toolTip = localizedString(visible ? "Open module settings" : "Preview")
        self.setAccessibilityLabel(self.title)
    }

    @objc private func toggleView() {
        self.callback()
    }
}
