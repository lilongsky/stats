//
//  settings.swift
//  Clock
//
//  Created by Serhiy Mytrovtsiy on 24/03/2023
//  Using Swift 5.0
//  Running on macOS 13.2
//
//  Copyright © 2023 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

let nameColumnID = NSUserInterfaceItemIdentifier(rawValue: "name")
let formatColumnID = NSUserInterfaceItemIdentifier(rawValue: "format")
let tzColumnID = NSUserInterfaceItemIdentifier(rawValue: "tz")
let calendarColumnID = NSUserInterfaceItemIdentifier(rawValue: "calendar")
let statusColumnID = NSUserInterfaceItemIdentifier(rawValue: "status")

internal class Settings: SettingsContainerView, Settings_v, NSTableViewDelegate, NSTableViewDataSource, NSTextFieldDelegate {
    public var callback: (() -> Void) = {}
    
    private var cachedList: [Clock_t] = []
    private var list: [Clock_t] {
        get { self.cachedList }
        set {
            self.cachedList = newValue
            
            if newValue.isEmpty {
                Store.shared.remove("\(self.title)_list")
            } else {
                let encoder = JSONEncoder()
                if let encoded = try? encoder.encode(newValue){
                    Store.shared.set(key: "\(self.title)_list", value: encoded)
                }
            }
        }
    }
    
    private var title: String
    
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private var tableHeightConstraint: NSLayoutConstraint?
    private var footerView: NSStackView? = nil
    private var deleteButton: NSButton? = nil
    
    private var ntpSync: Bool = false
    
    public init(_ module: ModuleType) {
        self.title = module.stringValue
        
        self.ntpSync = Store.shared.bool(key: "\(self.title)_ntpSync", defaultValue: self.ntpSync)
        
        super.init(frame: NSRect.zero)
        
        if let objects = Store.shared.data(key: "\(self.title)_list") {
            let decoder = JSONDecoder()
            if let objectsDecoded = try? decoder.decode(Array.self, from: objects) as [Clock_t] {
                self.cachedList = objectsDecoded
            }
        }
        if self.cachedList.isEmpty {
            self.cachedList = [Clock.local]
        }
        
        self.orientation = .vertical
        self.distribution = .gravityAreas
        self.spacing = 0
        
        self.scrollView.documentView = self.tableView
        self.scrollView.identifier = NSUserInterfaceItemIdentifier("clock-settings-scroll")
        self.scrollView.hasHorizontalScroller = false
        self.scrollView.hasVerticalScroller = true
        self.scrollView.autohidesScrollers = true
        self.scrollView.backgroundColor = NSColor.clear
        self.scrollView.drawsBackground = true
        
        self.tableView.frame = self.scrollView.bounds
        self.tableView.identifier = NSUserInterfaceItemIdentifier("clock-settings-table")
        self.tableView.autoresizingMask = [.width]
        self.tableView.delegate = self
        self.tableView.dataSource = self
        self.tableView.allowsMultipleSelection = false
        self.tableView.focusRingType = .none
        self.tableView.gridColor = .gridColor
        self.tableView.columnAutoresizingStyle = .noColumnAutoresizing
        self.tableView.allowsColumnResizing = false
        self.tableView.gridStyleMask = [.solidVerticalGridLineMask, .solidHorizontalGridLineMask]
        self.tableView.usesAlternatingRowBackgroundColors = true
        self.tableView.style = .plain
        self.tableView.intercellSpacing = NSSize(width: 4, height: self.tableView.intercellSpacing.height)
        self.tableView.rowHeight = 32
        
        let nameColumn = NSTableColumn(identifier: nameColumnID)
        nameColumn.headerCell.title = localizedString("Name")
        nameColumn.headerCell.alignment = .center
        nameColumn.minWidth = 72
        let formatColumn = NSTableColumn(identifier: formatColumnID)
        formatColumn.headerCell.title = localizedString("Format")
        formatColumn.headerCell.alignment = .center
        formatColumn.minWidth = 96
        formatColumn.width = 160
        let tzColumn = NSTableColumn(identifier: tzColumnID)
        tzColumn.headerCell.title = localizedString("Time zone")
        tzColumn.headerCell.alignment = .center
        tzColumn.minWidth = 96
        tzColumn.width = 132
        let calendarColumn = NSTableColumn(identifier: calendarColumnID)
        calendarColumn.headerCell.title = localizedString("Calendar")
        calendarColumn.headerCell.alignment = .center
        calendarColumn.minWidth = 76
        calendarColumn.width = 92
        let statusColumn = NSTableColumn(identifier: statusColumnID)
        statusColumn.headerCell.title = ""
        statusColumn.minWidth = 28
        statusColumn.maxWidth = 28
        statusColumn.width = 28
        statusColumn.resizingMask = []
        
        self.tableView.addTableColumn(nameColumn)
        self.tableView.addTableColumn(formatColumn)
        self.tableView.addTableColumn(tzColumn)
        self.tableView.addTableColumn(calendarColumn)
        self.tableView.addTableColumn(statusColumn)
        
        let separator = NSBox()
        separator.boxType = .separator
        
        self.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Sync with NTP server"), component: switchView(
                action: #selector(self.toggleNTPSync),
                state: self.ntpSync
            ))
        ]))
        
        self.addArrangedSubview(self.scrollView)
        self.addArrangedSubview(separator)
        self.addArrangedSubview(self.footer())
        
        self.tableHeightConstraint = self.scrollView.heightAnchor.constraint(equalToConstant: 0)
        self.tableHeightConstraint?.isActive = true
        self.reloadClocks()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        self.scrollView.tile()
        self.fitTableColumns()
        self.updateTableHeight()
    }

    private func fitTableColumns() {
        let columns = self.tableView.tableColumns
        let width = self.scrollView.contentView.bounds.width
        guard columns.count == 5, width > 0 else { return }
        // Native table styles add spacing around their columns. Reserve that
        // measured space and the checkbox before allocating editable columns.
        let columnsWidth = columns.reduce(CGFloat.zero) { $0 + $1.width }
        let spacing = max(0, self.tableView.rect(ofColumn: 4).maxX - columnsWidth)
        let minimums: [CGFloat] = [72, 96, 96, 76]
        let weights: [CGFloat] = [0.26, 0.34, 0.24, 0.16]
        let extra = max(0, width - spacing - 28 - minimums.reduce(0, +))
        for index in minimums.indices {
            columns[index].width = minimums[index] + extra * weights[index]
        }
        columns[4].width = 28
        self.tableView.setFrameSize(NSSize(width: width, height: self.tableView.frame.height))
    }

    private func updateTableHeight() {
        let rowsHeight = CGFloat(max(1, self.cachedList.count)) * (self.tableView.rowHeight + self.tableView.intercellSpacing.height)
        let headerHeight = self.tableView.headerView?.frame.height ?? 0
        let maximumHeight: CGFloat
        if #available(macOS 26.0, *) {
            maximumHeight = 248
        } else {
            maximumHeight = 254
        }
        let height = min(maximumHeight, ceil(rowsHeight + headerHeight))
        if abs((self.tableHeightConstraint?.constant ?? 0) - height) > 0.5 {
            self.tableHeightConstraint?.constant = height
        }
    }

    private func reloadClocks() {
        self.tableView.reloadData()
        self.updateTableHeight()
    }
    
    private func footer() -> NSView {
        let view = NSStackView()
        view.heightAnchor.constraint(equalToConstant: 27).isActive = true
        view.spacing = 4
        view.orientation = .horizontal
        
        var addButton: NSButton {
            let btn = NSButton()
            btn.widthAnchor.constraint(equalToConstant: 27).isActive = true
            btn.heightAnchor.constraint(equalToConstant: 27).isActive = true
            btn.bezelStyle = .rounded
            btn.image =  iconFromSymbol(name: "plus", scale: .medium)
            btn.action = #selector(self.addNewClock)
            btn.target = self
            btn.toolTip = localizedString("Add new clock")
            btn.focusRingType = .none
            return btn
        }
        var deleteButton: NSButton {
            let btn = NSButton()
            btn.widthAnchor.constraint(equalToConstant: 27).isActive = true
            btn.heightAnchor.constraint(equalToConstant: 27).isActive = true
            btn.bezelStyle = .rounded
            btn.image =  iconFromSymbol(name: "minus", scale: .medium)
            btn.action = #selector(self.deleteClock)
            btn.target = self
            btn.toolTip = localizedString("Delete selected clock")
            btn.focusRingType = .none
            return btn
        }
        self.deleteButton = deleteButton
        
        view.addArrangedSubview(addButton)
        view.addArrangedSubview(NSView())
        
        let helpBtn = NSButton()
        helpBtn.widthAnchor.constraint(equalToConstant: 27).isActive = true
        helpBtn.heightAnchor.constraint(equalToConstant: 27).isActive = true
        helpBtn.bezelStyle = .helpButton
        helpBtn.title = ""
        helpBtn.action = #selector(self.openFormatHelp)
        helpBtn.target = self
        helpBtn.toolTip = localizedString("Help with datetime format")
        view.addArrangedSubview(helpBtn)
        
        self.footerView = view
        return view
    }
    
    func load(widgets: [Kit.widget_t]) {
        self.reloadClocks()
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return self.list.count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier else { return nil }
        let cell = NSTableCellView()
        let item = self.list[row]
        
        switch id {
        case nameColumnID, formatColumnID:
            let text: NSTextField = NSTextField()
            text.identifier = id
            text.drawsBackground = false
            text.isBordered = false
            text.sizeToFit()
            text.delegate = self
            text.stringValue = id == nameColumnID ? item.name : item.format
            text.usesSingleLineMode = true
            text.maximumNumberOfLines = 1
            text.lineBreakMode = .byTruncatingTail
            text.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(text)
            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        case tzColumnID:
            let select: NSPopUpButton = selectView(action: #selector(self.toggleTZ), items: Clock.zones, selected: item.tz)
            select.identifier = NSUserInterfaceItemIdentifier("\(row)")
            select.itemArray.forEach { $0.identifier = NSUserInterfaceItemIdentifier("\(row)") }
            select.controlSize = .small
            select.cell?.lineBreakMode = .byTruncatingTail
            select.preferredEdge = .maxX
            select.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(select)
            NSLayoutConstraint.activate([
                select.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                select.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                select.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        case calendarColumnID:
            let select: NSPopUpButton = selectView(action: #selector(self.toggleCalendar), items: Clock.calendars, selected: item.calendar)
            select.identifier = NSUserInterfaceItemIdentifier("\(row)")
            select.itemArray.forEach { $0.identifier = NSUserInterfaceItemIdentifier("\(row)") }
            select.controlSize = .small
            select.cell?.lineBreakMode = .byTruncatingTail
            select.preferredEdge = .maxX
            select.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(select)
            NSLayoutConstraint.activate([
                select.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                select.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                select.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        case statusColumnID:
            let button: NSButton = NSButton(frame: NSRect(x: 0, y: 8, width: 10, height: 10))
            button.identifier = NSUserInterfaceItemIdentifier("\(row)")
            button.setButtonType(.switch)
            button.state = item.enabled ? .on : .off
            button.action = #selector(self.toggleClock)
            button.title = ""
            button.isBordered = false
            button.isTransparent = false
            button.target = self
            button.controlSize = .small
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setAccessibilityLabel("\(item.name) · \(localizedString("Status"))")
            cell.addSubview(button)
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                button.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        default: break
        }
        
        return cell
    }
    
    func controlTextDidChange(_ notification: Notification) {
        if let textField = notification.object as? NSTextField, let id = textField.identifier {
            let i = self.tableView.selectedRow
            switch id {
            case nameColumnID:
                self.list[i].name = textField.stringValue
            case formatColumnID:
                self.list[i].format = textField.stringValue
            default: return
            }
        }
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        if self.tableView.selectedRow == -1 {
            self.deleteButton?.removeFromSuperview()
        } else {
            if let btn = self.deleteButton {
                self.footerView?.insertArrangedSubview(btn, at: 1)
            }
        }
    }
    
    private func selectValue(_ sender: Any) -> (key: String, index: Int)? {
        if let select = sender as? NSPopUpButton,
           let key = select.selectedItem?.representedObject as? String,
           let id = select.identifier,
           let index = Int(id.rawValue) {
            return (key, index)
        }
        
        if let item = sender as? NSMenuItem,
           let key = item.representedObject as? String,
           let id = item.identifier,
           let index = Int(id.rawValue) {
            return (key, index)
        }
        
        return nil
    }
    
    @objc private func toggleTZ(_ sender: Any) {
        guard let value = self.selectValue(sender) else { return }
        let key = value.key
        let i = value.index
        self.list[i].tz = key
    }
    @objc private func toggleCalendar(_ sender: Any) {
        guard let value = self.selectValue(sender) else { return }
        let key = value.key
        let i = value.index
        self.list[i].calendar = key
    }
    @objc private func toggleClock(_ sender: NSButton) {
        guard let id = sender.identifier, let i = Int(id.rawValue) else { return }
        self.list[i].enabled = sender.state == NSControl.StateValue.on
    }
    @objc private func addNewClock() {
        self.list.append(Clock_t(name: "\(localizedString("Clock")) \(self.list.count)", format: Clock.local.format, tz: Clock.local.tz))
        self.reloadClocks()
    }
    @objc private func deleteClock() {
        guard self.tableView.selectedRow != -1 else { return }
        self.list.remove(at: self.tableView.selectedRow)
        self.reloadClocks()
        self.deleteButton?.removeFromSuperview()
    }
    @objc private func openFormatHelp() {
        NSWorkspace.shared.open(URL(string: "https://www.nsdateformatter.com")!)
    }
    @objc func toggleNTPSync(_ sender: NSControl) {
        self.ntpSync = controlState(sender)
        Store.shared.set(key: "\(self.title)_ntpSync", value: self.ntpSync)
        self.callback()
    }
}
