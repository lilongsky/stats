//
//  popup.swift
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

internal class Popup: PopupWrapper {
    private let orderTableView: OrderTableView = OrderTableView()
    private var list: [Clock_t] = []
    private let cache = PopupCache<[Clock_t]>()
    
    private var calendarView: CalendarView? = nil
    private var calendarState: Bool = true
    private var weekNumbersState: Bool = false
    
    public init(_ module: ModuleType) {
        super.init(module, frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))
        
        self.orientation = .vertical
        self.spacing = Constants.Popup.margins
        
        self.calendarState = Store.shared.bool(key: "\(self.title)_calendar", defaultValue: self.calendarState)
        self.weekNumbersState = Store.shared.bool(key: "\(self.title)_calendarWeekNumbers", defaultValue: self.weekNumbersState)
        self.calendarView = CalendarView(self.frame.width, showWeekNumbers: self.weekNumbersState)
        
        self.orderTableView.reorderCallback = { [weak self] in
            self?.rearrange()
        }
        
        if let calendar = self.calendarView, self.calendarState {
            self.addArrangedSubview(calendar)
        }
        
        self.recalculateHeight()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    internal func callback(_ list: [Clock_t]) {
        if list.count != self.orderTableView.list.count || self.orderTableView.window?.isVisible ?? false {
            self.orderTableView.list = list.sorted(by: { $0.popupIndex < $1.popupIndex })
            self.orderTableView.update()
        }
        
        self.cache.apply(list, visible: self.window?.isVisible ?? false, render: self.render)
    }
    
    private func render(_ list: [Clock_t]) {
        defer { self.recalculateHeight() }
        
        let sorted = list.sorted(by: { $0.popupIndex < $1.popupIndex }).filter({ $0.popupState })
        var views = self.subviews.filter{ $0 is ClockView }.compactMap{ $0 as? ClockView }
        
        if sorted.count < views.count && !views.isEmpty {
            views.forEach{ $0.removeFromSuperview() }
            views = []
        }
        
        sorted.forEach { (c: Clock_t) in
            if let view = views.first(where: { $0.clock.id == c.id }) {
                view.update(c)
            } else {
                self.addArrangedSubview(ClockView(width: self.frame.width, clock: c))
            }
        }
        
        self.list = sorted
    }
    
    private func recalculateHeight() {
        let h = self.arrangedSubviews.map({ $0.fittingSize.height + self.spacing }).reduce(0, +) - self.spacing
        if h > 0 && self.frame.size.height != h {
            self.setFrameSize(NSSize(width: self.frame.width, height: h))
            self.sizeCallback?(self.frame.size)
        }
    }
    
    public override func settings() -> NSView? {
        let view = SettingsContainerView()
        
        view.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Keyboard shortcut"), component: KeyboardShartcutView(
                callback: self.setKeyboardShortcut,
                value: self.keyboardShortcut
            ))
        ]))
        
        view.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Calendar"), component: switchView(
                action: #selector(self.toggleCalendarState),
                state: self.calendarState
            )),
            PreferencesRow(localizedString("Show week numbers"), component: switchView(
                action: #selector(self.toggleWeekNumbersState),
                state: self.weekNumbersState
            ))
        ]))
        
        view.addArrangedSubview(self.orderTableView)
        
        return view
    }
    
    public override func appear() {
        if self.calendarState {
            self.calendarView?.checkCurrentDay()
        }
        self.cache.replay(render: self.render)
        self.subviews.compactMap { $0 as? ClockView }.forEach { $0.appear() }
    }
    
    private func rearrange() {
        let views = self.subviews.filter{ $0 is ClockView }.compactMap{ $0 as? ClockView }
        views.forEach{ $0.removeFromSuperview() }
        self.callback(self.list)
    }
    
    @objc private func toggleCalendarState(_ sender: NSControl) {
        self.calendarState = controlState(sender)
        Store.shared.set(key: "\(self.title)_calendar", value: self.calendarState)
        
        guard let view = self.calendarView else { return }
        if self.calendarState {
            self.insertArrangedSubview(view, at: 0)
        } else {
            view.removeFromSuperview()
        }
        self.recalculateHeight()
    }
    
    @objc private func toggleWeekNumbersState(_ sender: NSControl) {
        self.weekNumbersState = controlState(sender)
        Store.shared.set(key: "\(self.title)_calendarWeekNumbers", value: self.weekNumbersState)
        self.calendarView?.setShowWeekNumbers(self.weekNumbersState)
        self.recalculateHeight()
    }
}

private class CalendarView: NSStackView, NSMenuDelegate {
    private var itemSize: CGSize
    private var showWeekNumbers: Bool
    private var navigationHeightConstraint: NSLayoutConstraint?
    
    private var year: Int
    private var month: Int
    private var day: Int
    
    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }
    private var currentMonth: Int {
        Calendar.current.component(.month, from: Date())
    }
    private var currentDay: Int {
        Calendar.current.component(.day, from: Date())
    }
    
    private var weekDays: [String] {
        let calendar = Calendar.current
        let firstWeekdayIndex = calendar.firstWeekday - 1
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale.current
        dateFormatter.calendar = calendar
        let weekdaySymbols = dateFormatter.shortWeekdaySymbols
        return Array(weekdaySymbols![firstWeekdayIndex...]) + weekdaySymbols![..<firstWeekdayIndex]
    }
    
    private var weekdayHeader = NSGridView()
    private let scrollView = NSScrollView()
    private let document = CalendarDocumentView()
    private var dayViews: [CalendarItemView] = []
    private var weekNumberViews: [NSTextField] = []
    private weak var hoveredDay: CalendarItemView?
    private var firstWeek: Date?
    private var monthAnchorRow: Int?
    private let weekCount = 48
    private let anchorRow = 20
    private var rebuilding = false
    private var scrollHeightConstraint: NSLayoutConstraint?
    private let monthPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let yearPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    
    init(_ width: CGFloat, showWeekNumbers: Bool) {
        self.showWeekNumbers = showWeekNumbers
        self.itemSize = NSSize.zero
        self.year = Calendar.current.component(.year, from: Date())
        self.month = Calendar.current.component(.month, from: Date())
        self.day = Calendar.current.component(.day, from: Date())
        
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: width - 32))
        self.setAccessibilityElement(false)
        
        self.spacing = 0
        self.orientation = .vertical
        self.edgeInsets = .init(
            top: Constants.Popup.margins,
            left: Constants.Popup.margins,
            bottom: Constants.Popup.margins,
            right: Constants.Popup.margins
        )
        self.wantsLayer = true
        self.layer?.cornerRadius = Constants.Popup.radius
        
        self.updateItemSize()
        self.addArrangedSubview(self.navigation())
        self.scrollView.drawsBackground = false
        self.scrollView.contentView.drawsBackground = false
        self.scrollView.hasVerticalScroller = false
        self.scrollView.hasHorizontalScroller = false
        self.scrollView.horizontalScrollElasticity = .none
        self.scrollView.verticalScrollElasticity = .none
        self.scrollView.documentView = self.document
        self.document.hoverChanged = { [weak self] point in self?.updateHover(at: point) }
        self.scrollView.contentView.postsBoundsChangedNotifications = true
        self.scrollView.identifier = NSUserInterfaceItemIdentifier("clock-calendar-scroll")
        self.scrollView.setAccessibilityLabel("日历，可连续滚动浏览月份")
        self.scrollView.widthAnchor.constraint(equalToConstant: width - Constants.Popup.margins * 2).isActive = true
        self.scrollHeightConstraint = self.scrollView.heightAnchor.constraint(equalToConstant: self.itemSize.height * 6)
        self.scrollHeightConstraint?.isActive = true
        self.addArrangedSubview(self.scrollView)
        NotificationCenter.default.addObserver(self, selector: #selector(self.scrolled),
            name: NSView.boundsDidChangeNotification, object: self.scrollView.contentView)
        self.setup()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit { NotificationCenter.default.removeObserver(self) }
    
    public func checkCurrentDay() {
        guard self.day != self.currentDay || self.month != self.currentMonth || self.year != self.currentYear else { return }
        self.goToToday()
    }
    
    public func setShowWeekNumbers(_ state: Bool) {
        guard self.showWeekNumbers != state else { return }
        let position = self.visiblePosition()
        self.showWeekNumbers = state
        self.updateItemSize()
        self.setup(keeping: position)
    }
    
    override func updateLayer() {
        self.layer?.backgroundColor = (isDarkMode ? NSColor(red: 17/255, green: 17/255, blue: 17/255, alpha: 0.25) : NSColor(red: 245/255, green: 245/255, blue: 245/255, alpha: 1)).cgColor
    }
    
    private func setup(keeping position: (week: Date, offset: CGFloat)? = nil) {
        self.weekdayHeader.removeFromSuperview()
        
        let grid = NSGridView()
        grid.rowSpacing = 0
        grid.columnSpacing = 0
        
        var headerRow: [NSView] = []
        if self.showWeekNumbers {
            headerRow.append(self.weekNumberHeaderItem())
        }
        headerRow.append(contentsOf: self.weekDays.map { headerItem($0) })
        grid.addRow(with: headerRow)
          
        self.weekdayHeader = grid
        self.updateNavigation()
        self.insertArrangedSubview(grid, at: 1)
        let monthStart = Calendar.current.date(from: DateComponents(year: self.year, month: self.month, day: 1)) ?? Date()
        self.rebuild(around: position?.week ?? self.weekStart(containing: monthStart), offset: position?.offset ?? 0)
    }

    private func weekStart(containing date: Date) -> Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let days = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -days, to: start) ?? start
    }

    private func visiblePosition() -> (week: Date, offset: CGFloat)? {
        guard let firstWeek else { return nil }
        let y = max(0, self.scrollView.contentView.bounds.minY)
        let row = Int(floor(y / self.itemSize.height))
        guard let week = Calendar.current.date(byAdding: .day, value: row * 7, to: firstWeek) else { return nil }
        return (week, y - CGFloat(row) * self.itemSize.height)
    }

    // Reuse the fixed-size date buffer. Recreating a constraint-based grid here
    // stalls the main thread while a trackpad gesture is still in progress.
    private func rebuild(around week: Date, offset: CGFloat) {
        let calendar = Calendar.current
        guard let first = calendar.date(byAdding: .day, value: -self.anchorRow * 7, to: week) else { return }
        self.rebuilding = true
        self.setHoveredDay(nil)
        self.firstWeek = first
        self.monthAnchorRow = nil
        let today = calendar.dateComponents([.year, .month, .day], from: Date())
        let dateColumnOffset: CGFloat = self.showWeekNumbers ? 1 : 0
        self.weekNumberViews.forEach { $0.isHidden = !self.showWeekNumbers }
        for row in 0..<self.weekCount {
            guard let weekDate = calendar.date(byAdding: .day, value: row * 7, to: first) else { continue }
            if self.showWeekNumbers {
                if row == self.weekNumberViews.count {
                    let number = self.weekNumberItem()
                    self.weekNumberViews.append(number)
                    self.document.addSubview(number)
                }
                let number = self.weekNumberViews[row]
                number.frame = NSRect(x: 0, y: CGFloat(row) * self.itemSize.height,
                                      width: self.itemSize.width, height: self.itemSize.height)
                number.stringValue = "\(calendar.component(.weekOfYear, from: weekDate))"
            }
            for column in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: column, to: weekDate) else { continue }
                let components = calendar.dateComponents([.era, .year, .month, .day], from: date)
                let index = row * 7 + column
                let isToday = components.year == today.year && components.month == today.month && components.day == today.day
                let isOutOfMonth = components.month != self.month || components.year != self.year
                if index == self.dayViews.count {
                    let item = CalendarItemView(components, size: self.itemSize, isToday: isToday, isOutOfMonth: isOutOfMonth)
                    self.dayViews.append(item)
                    self.document.addSubview(item)
                }
                self.dayViews[index].update(components,
                    frame: NSRect(x: (CGFloat(column) + dateColumnOffset) * self.itemSize.width,
                                  y: CGFloat(row) * self.itemSize.height,
                                  width: self.itemSize.width, height: self.itemSize.height),
                    isToday: isToday, isOutOfMonth: isOutOfMonth)
            }
        }
        let size = NSSize(width: self.frame.width - Constants.Popup.margins * 2,
                          height: self.itemSize.height * CGFloat(self.weekCount))
        self.document.setFrameSize(size)
        self.scrollView.contentView.scroll(to: NSPoint(x: 0, y: CGFloat(self.anchorRow) * self.itemSize.height + offset))
        self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
        self.rebuilding = false
        self.updateVisibleMonth()
        self.refreshHover()
    }

    @objc private func scrolled() {
        guard !self.rebuilding, self.firstWeek != nil else { return }
        let row = self.scrollView.contentView.bounds.minY / self.itemSize.height
        if (row < 6 || row > CGFloat(self.weekCount - 12)), let position = self.visiblePosition() {
            self.rebuild(around: position.week, offset: position.offset)
        } else {
            self.updateVisibleMonth()
            self.refreshHover()
        }
    }

    private func setHoveredDay(_ day: CalendarItemView?) {
        guard self.hoveredDay !== day else { return }
        self.hoveredDay?.setHovered(false)
        self.hoveredDay = day
        day?.setHovered(true)
    }

    private func updateHover(at point: NSPoint?) {
        guard let point, self.window != nil else { self.setHoveredDay(nil); return }
        let clip = self.scrollView.contentView
        let location = clip.convert(point, from: nil)
        guard clip.bounds.contains(location) else { self.setHoveredDay(nil); return }
        let gridPoint = self.document.convert(location, from: clip)
        let row = Int(floor(gridPoint.y / self.itemSize.height))
        let column = Int(floor(gridPoint.x / self.itemSize.width)) - (self.showWeekNumbers ? 1 : 0)
        guard row >= 0, row < self.weekCount, column >= 0, column < 7 else { self.setHoveredDay(nil); return }
        self.setHoveredDay(self.dayViews[row * 7 + column])
    }

    private func refreshHover() {
        let window = self.window
        self.updateHover(at: window?.isKeyWindow == true && NSApp.isActive ? window?.mouseLocationOutsideOfEventStream : nil)
    }

    private func updateVisibleMonth() {
        let row = Int(floor((self.scrollView.contentView.bounds.minY + self.itemSize.height / 2) / self.itemSize.height))
        guard self.monthAnchorRow != row else { return }
        guard let position = self.visiblePosition(),
              let date = Calendar.current.date(byAdding: .day,
                value: position.offset >= self.itemSize.height / 2 ? 13 : 6, to: position.week) else { return }
        self.monthAnchorRow = row
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        guard self.year != year || self.month != month else { return }
        self.year = year
        self.month = month
        self.updateNavigation()
        self.dayViews.forEach { $0.setDisplayedMonth(self.month, year: self.year) }
    }

    private func moveMonth(_ offset: Int) {
        let calendar = Calendar.current
        guard let date = calendar.date(from: DateComponents(year: self.year, month: self.month, day: 1)),
              let target = calendar.date(byAdding: .month, value: offset, to: date) else { return }
        self.jump(toYear: calendar.component(.year, from: target), month: calendar.component(.month, from: target))
    }

    private func jump(toYear year: Int, month: Int) {
        let calendar = Calendar.current
        guard year > 0, (1...calendar.standaloneMonthSymbols.count).contains(month),
              let target = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              calendar.component(.year, from: target) == year,
              calendar.component(.month, from: target) == month,
              let firstWeek else { return }
        let targetWeek = self.weekStart(containing: target)
        let days = calendar.dateComponents([.day], from: firstWeek, to: targetWeek).day ?? 0
        let row = CGFloat(days) / 7
        if row >= 6 && row <= CGFloat(self.weekCount - 12) {
            self.scrollView.contentView.scroll(to: NSPoint(x: 0, y: row * self.itemSize.height))
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
            self.scrolled()
        } else {
            self.rebuild(around: targetWeek, offset: 0)
        }
    }

    private func updateNavigation() {
        self.monthPicker.selectItem(withTag: self.month)
        if self.yearPicker.menu?.item(withTag: self.year) == nil {
            self.yearPicker.removeAllItems()
            self.yearPicker.addItem(withTitle: "\(self.year)")
            self.yearPicker.lastItem?.tag = self.year
        }
        self.yearPicker.selectItem(withTag: self.year)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === self.yearPicker.menu else { return }
        // Build the scrollable native menu only when opened, not during a
        // trackpad gesture. Reopening recenters it on the year being browsed.
        self.yearPicker.removeAllItems()
        for year in max(1, self.year - 50)...(self.year + 50) {
            self.yearPicker.addItem(withTitle: "\(year)")
            self.yearPicker.lastItem?.tag = year
        }
        self.yearPicker.selectItem(withTag: self.year)
    }

    @objc private func selectMonth(_ sender: NSPopUpButton) {
        guard let month = sender.selectedItem?.tag else { return }
        self.jump(toYear: self.year, month: month)
    }

    @objc private func selectYear(_ sender: NSPopUpButton) {
        guard let year = sender.selectedItem?.tag else { return }
        self.jump(toYear: year, month: self.month)
    }
    
    private func navigation() -> NSView {
        let view = NSStackView()
        view.distribution = .fill
        view.alignment = .centerY
        self.navigationHeightConstraint = view.heightAnchor.constraint(greaterThanOrEqualToConstant: max(self.itemSize.height, 24))
        self.navigationHeightConstraint?.isActive = true
        view.orientation = .horizontal
        view.spacing = 4
        view.edgeInsets = .init(top: 0, left: 6, bottom: 6, right: 6)
        
        let details = NSStackView()
        details.orientation = .horizontal
        // Pop-up cells extend beyond their alignment rects. Leave enough room
        // for two separate native hit areas, including in the borderless style.
        details.spacing = 6
        for (picker, label, identifier) in [
            (self.monthPicker, "Choose month", "clock-calendar-month"),
            (self.yearPicker, "Choose year", "clock-calendar-year")
        ] {
            picker.bezelStyle = .rounded
            picker.controlSize = .small
            picker.font = .systemFont(ofSize: 14, weight: .medium)
            picker.isBordered = false
            picker.autoenablesItems = false
            picker.cell?.lineBreakMode = .byTruncatingTail
            picker.toolTip = localizedString(label)
            picker.setAccessibilityLabel(localizedString(label))
            picker.identifier = NSUserInterfaceItemIdentifier(identifier)
            picker.target = self
        }
        self.monthPicker.action = #selector(self.selectMonth(_:))
        for (index, month) in Calendar.current.standaloneMonthSymbols.enumerated() {
            self.monthPicker.addItem(withTitle: month)
            self.monthPicker.lastItem?.tag = index + 1
        }
        self.monthPicker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        self.monthPicker.widthAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        self.yearPicker.action = #selector(self.selectYear(_:))
        self.yearPicker.menu?.delegate = self
        self.yearPicker.setContentCompressionResistancePriority(.required, for: .horizontal)
        self.yearPicker.widthAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
        let format = DateFormatter.dateFormat(fromTemplate: "yMMMM", options: 0, locale: .current) ?? "MMMM y"
        let yearFirst = format.range(of: "y").map { year in
            [format.range(of: "M"), format.range(of: "L")].compactMap { $0 }
                .allSatisfy { year.lowerBound < $0.lowerBound }
        } ?? false
        (yearFirst ? [self.yearPicker, self.monthPicker] : [self.monthPicker, self.yearPicker])
            .forEach { details.addArrangedSubview($0) }
        self.updateNavigation()
        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 4
        buttons.setContentCompressionResistancePriority(.required, for: .horizontal)

        let today = NSButton(title: localizedString("Today"), target: self, action: #selector(self.goToToday))
        today.bezelStyle = .rounded
        today.controlSize = .small
        today.font = .systemFont(ofSize: 11, weight: .medium)
        today.focusRingType = .none
        today.toolTip = localizedString("Return to today")
        today.identifier = NSUserInterfaceItemIdentifier("clock-calendar-today")
        today.setAccessibilityLabel(localizedString("Return to today"))
        
        let prev = NSButton()
        prev.bezelStyle = .regularSquare
        prev.translatesAutoresizingMaskIntoConstraints = false
        prev.imageScaling = .scaleNone
        prev.image = iconFromSymbol(name: "arrow.left", scale: .medium)
        prev.contentTintColor = .labelColor
        prev.isBordered = false
        prev.action = #selector(self.prevMonth)
        prev.target = self
        prev.toolTip = localizedString("Previous month")
        prev.focusRingType = .none
        
        let next = NSButton()
        next.bezelStyle = .regularSquare
        next.translatesAutoresizingMaskIntoConstraints = false
        next.imageScaling = .scaleNone
        next.image = iconFromSymbol(name: "arrow.right", scale: .medium)
        next.contentTintColor = .labelColor
        next.isBordered = false
        next.action = #selector(self.nextMonth)
        next.target = self
        next.toolTip = localizedString("Next month")
        next.focusRingType = .none
        
        buttons.addArrangedSubview(today)
        buttons.addArrangedSubview(prev)
        buttons.addArrangedSubview(next)
        
        view.addArrangedSubview(details)
        view.addArrangedSubview(NSView())
        view.addArrangedSubview(buttons)
        
        return view
    }
    
    private func updateItemSize() {
        let columns: CGFloat = self.showWeekNumbers ? 8 : 7
        self.itemSize = NSSize(
            width: (self.frame.width-(Constants.Popup.margins*2))/columns,
            height: (self.frame.width-(Constants.Popup.spacing*2))/8 - 4
        )
        self.navigationHeightConstraint?.constant = max(self.itemSize.height, 24)
        self.scrollHeightConstraint?.constant = self.itemSize.height * 6
    }
    
    private func headerItem(_ value: String) -> NSView {
        let view = NSTextField()
        let cell = VerticallyCenteredTextFieldCell(textCell: value)
        view.cell = cell
        view.alignment = .center
        view.textColor = .gray
        view.font = .systemFont(ofSize: 10, weight: .medium)
        view.widthAnchor.constraint(equalToConstant: self.itemSize.width).isActive = true
        view.heightAnchor.constraint(equalToConstant: self.itemSize.height).isActive = true
        return view
    }
    
    private func weekNumberHeaderItem() -> NSView {
        let view = NSTextField()
        let cell = VerticallyCenteredTextFieldCell(textCell: "")
        view.cell = cell
        view.alignment = .center
        view.textColor = .secondaryLabelColor
        view.font = .systemFont(ofSize: 10, weight: .medium)
        view.widthAnchor.constraint(equalToConstant: self.itemSize.width).isActive = true
        view.heightAnchor.constraint(equalToConstant: self.itemSize.height).isActive = true
        self.addRightBorder(view)
        return view
    }
    
    private func weekNumberItem() -> NSTextField {
        let view = NSTextField(frame: NSRect(origin: .zero, size: self.itemSize))
        let cell = VerticallyCenteredTextFieldCell(textCell: "")
        view.cell = cell
        view.alignment = .center
        view.textColor = .secondaryLabelColor
        view.font = .systemFont(ofSize: 10, weight: .medium)
        self.addRightBorder(view, fixedFrame: true)
        return view
    }
    
    private func addRightBorder(_ view: NSView, fixedFrame: Bool = false) {
        let border = NSView()
        border.wantsLayer = true
        let borderColor = self.isDarkMode
            ? NSColor.white.withAlphaComponent(0.4)
            : NSColor.separatorColor
        border.layer?.backgroundColor = borderColor.cgColor
        view.addSubview(border)
        
        let lineWidth = 1 / (NSScreen.main?.backingScaleFactor ?? 1)
        if fixedFrame {
            border.frame = NSRect(x: view.bounds.maxX - lineWidth, y: 0, width: lineWidth, height: view.bounds.height)
            border.autoresizingMask = [.minXMargin, .height]
            return
        }
        border.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            border.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            border.topAnchor.constraint(equalTo: view.topAnchor),
            border.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            border.widthAnchor.constraint(equalToConstant: lineWidth)
        ])
    }
    
    @objc private func goToToday() {
        let today = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        self.year = today.year ?? self.currentYear
        self.month = today.month ?? self.currentMonth
        self.day = today.day ?? self.currentDay
        self.setup()
    }

    @objc private func prevMonth() { self.moveMonth(-1) }
    @objc private func nextMonth() { self.moveMonth(1) }
}

private final class CalendarDocumentView: NSView {
    var hoverChanged: ((NSPoint?) -> Void)?
    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.window?.acceptsMouseMovedEvents = true
        self.hoverChanged?(nil)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        self.trackingAreas.forEach(self.removeTrackingArea)
        self.addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { self.hoverChanged?(event.locationInWindow) }
    override func mouseMoved(with event: NSEvent) { self.hoverChanged?(event.locationInWindow) }
    override func mouseExited(with event: NSEvent) { self.hoverChanged?(nil) }
}

private class CalendarItemView: NSView {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "yyyyMMdd", options: 0, locale: .current)
        return formatter
    }()
    private var components: DateComponents
    private var isHoverable: Bool { !self.isToday }
    private var isToday: Bool
    private let field = NSTextField()
    private let circle = NSView()
    private var hovered = false
    
    private let app = URL(fileURLWithPath: "/System/Applications/Calendar.app")
    
    init(_ components: DateComponents, size: NSSize, isToday: Bool, isOutOfMonth: Bool) {
        self.components = components
        self.isToday = isToday
        
        super.init(frame: NSRect(x: 0, y: 0, width: size.width, height: size.height))
        
        self.wantsLayer = true
        self.layer?.cornerRadius = 4
        let field = self.field
        let cell = VerticallyCenteredTextFieldCell(textCell: "\(components.day ?? 0)")
        field.cell = cell
        field.alignment = .center
        self.circle.wantsLayer = true
        self.circle.layer?.backgroundColor = NSColor.systemRed.cgColor
        self.addSubview(self.circle)
        self.addSubview(field)
        self.update(components, frame: self.frame, isToday: isToday, isOutOfMonth: isOutOfMonth)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ components: DateComponents, frame: NSRect, isToday: Bool, isOutOfMonth: Bool) {
        self.setHovered(false)
        self.components = components
        self.isToday = isToday
        self.frame = frame
        self.field.frame = self.bounds
        self.field.stringValue = "\(components.day ?? 0)"
        self.field.textColor = isToday ? .white : (isOutOfMonth ? .lightGray : .labelColor)
        let diameter = min(frame.width, frame.height) - 3
        self.circle.frame = NSRect(x: (frame.width - diameter) / 2,
                                   y: (frame.height - diameter) / 2 + 0.5,
                                   width: diameter, height: diameter)
        self.circle.layer?.cornerRadius = diameter / 2
        self.circle.isHidden = !isToday
        self.toolTip = self.formattedDate()
    }
    
    func setDisplayedMonth(_ month: Int, year: Int) {
        guard !self.isToday else { return }
        self.field.textColor = self.components.month == month && self.components.year == year ? .labelColor : .lightGray
    }

    func setHovered(_ state: Bool) {
        let state = state && self.isHoverable
        guard self.hovered != state else { return }
        self.hovered = state
        self.layer?.backgroundColor = state ? NSColor.gray.withAlphaComponent(0.2).cgColor : .clear
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !self.isHidden else { return nil }
        return self.bounds.contains(self.convert(point, from: self.superview)) ? self : nil
    }
    
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            NSWorkspace.shared.open([], withApplicationAt: self.app, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        guard let value = self.formattedDate() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
    
    private func formattedDate() -> String? {
        guard let date = Calendar.current.date(from: self.components) else { return nil }
        return Self.dateFormatter.string(from: date)
    }
}

internal class ClockView: NSStackView {
    public var clock: Clock_t
    private let background: Bool
    
    open override var intrinsicContentSize: CGSize {
        return CGSize(width: self.bounds.width, height: self.bounds.height)
    }
    
    private let cache = PopupCache<Clock_t>()
    
    private let clockView: ClockChart = ClockChart(frame: CGRect(x: 0, y: 0, width: 34, height: 34))
    private let nameField: NSTextField = TextView()
    private let timeField: NSTextField = TextView()
    private let tzField: NSTextField = TextView()
    private let dateField: NSTextField = TextView()
    
    init(width: CGFloat, clock: Clock_t, background: Bool = true, nameSize: CGFloat = 11, timeSize: CGFloat = 13) {
        self.clock = clock
        self.background = background
        
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 50))
        
        self.orientation = .horizontal
        self.distribution = .fill
        self.spacing = Constants.Popup.margins
        self.edgeInsets = NSEdgeInsets(
            top: Constants.Popup.margins,
            left: Constants.Popup.margins,
            bottom: Constants.Popup.margins,
            right: Constants.Popup.margins
        )
        self.wantsLayer = true
        self.layer?.cornerRadius = Constants.Popup.radius
        self.setAccessibilityElement(true)
        self.toolTip = "\(clock.name): \(clock.formatted())"
        
        self.clockView.widthAnchor.constraint(equalToConstant: 34).isActive = true
        
        let container: NSStackView = NSStackView()
        container.orientation = .vertical
        container.spacing = 2
        container.distribution = .fillEqually
        container.alignment = .leading
        
        self.nameField.font = NSFont.systemFont(ofSize: nameSize, weight: .medium)
        self.nameField.textColor = .tertiaryLabelColor
        self.nameField.stringValue = self.clock.name
        self.nameField.cell?.truncatesLastVisibleLine = true
        
        self.timeField.font = NSFont.systemFont(ofSize: timeSize, weight: .regular)
        self.timeField.stringValue = clock.formatted()
        self.timeField.cell?.truncatesLastVisibleLine = true
        
        container.addArrangedSubview(self.nameField)
        container.addArrangedSubview(self.timeField)
        container.setContentHuggingPriority(.defaultLow, for: .horizontal)
        
        let details: NSStackView = NSStackView()
        details.orientation = .vertical
        details.spacing = 2
        details.distribution = .fillEqually
        details.alignment = .trailing
        
        self.tzField.font = NSFont.systemFont(ofSize: nameSize, weight: .medium)
        self.tzField.textColor = .tertiaryLabelColor
        self.tzField.alignment = .trailing
        
        self.dateField.font = NSFont.systemFont(ofSize: nameSize, weight: .regular)
        self.dateField.textColor = .tertiaryLabelColor
        self.dateField.alignment = .trailing
        
        details.addArrangedSubview(self.tzField)
        details.addArrangedSubview(self.dateField)
        details.setContentHuggingPriority(.required, for: .horizontal)
        
        self.addArrangedSubview(self.clockView)
        self.addArrangedSubview(container)
        self.addArrangedSubview(details)
        
        self.update(clock)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func updateLayer() {
        guard self.background else { return }
        self.layer?.backgroundColor = (isDarkMode ? NSColor(red: 17/255, green: 17/255, blue: 17/255, alpha: 0.25) : NSColor(red: 245/255, green: 245/255, blue: 245/255, alpha: 1)).cgColor
    }
    
    public func update(_ newClock: Clock_t) {
        if self.clock.tz != newClock.tz || self.clock.name != newClock.name {
            self.clock = newClock
            self.nameField.stringValue = self.clock.name
        }
        self.cache.apply(newClock, visible: self.window?.isVisible ?? false, render: self.renderClock)
    }
    
    private func renderClock(_ newClock: Clock_t) {
        self.timeField.stringValue = newClock.formatted()
        self.setDetails(newClock)
        if let value = newClock.value {
            self.clockView.setValue(value.convertToTimeZone(TimeZone(from: newClock.tz)))
        }
        self.clockView.display()
    }
    
    private func setDetails(_ clock: Clock_t) {
        let date = clock.value ?? Date()
        let tz = TimeZone(from: clock.tz)
        
        let seconds = tz.secondsFromGMT(for: date)
        let sign = seconds < 0 ? "-" : "+"
        let hours = abs(seconds) / 3600
        let minutes = abs(seconds) / 60 % 60
        self.tzField.stringValue = minutes == 0
            ? "GMT\(sign)\(hours)"
            : String(format: "GMT\(sign)%d:%02d", hours, minutes)
        
        guard clock.tz != "local" else {
            self.dateField.stringValue = ""
            self.dateField.isHidden = true
            return
        }
        self.dateField.isHidden = false
        
        var remote = Calendar.current
        remote.timeZone = tz
        var local = Calendar.current
        local.timeZone = .current
        let diff = (remote.ordinality(of: .day, in: .era, for: date) ?? 0) - (local.ordinality(of: .day, in: .era, for: date) ?? 0)
        
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = tz
        formatter.dateFormat = "EEE"
        var value = formatter.string(from: date)
        if diff > 0 {
            value += " · +\(diff)"
        } else if diff < 0 {
            value += " · \(diff)"
        }
        self.dateField.stringValue = value
    }
    
    public func appear() {
        self.cache.replay(render: self.renderClock)
    }
}

internal class ClockChart: NSView {
    private let calendar = Calendar.current
    private var hour: Int = 0
    private var minute: Int = 0
    private var second: Int = 0
    
    private let hourLayer = CALayer()
    private let minuteLayer = CALayer()
    private let secondsLayer = CALayer()
    private let pinLayer = CAShapeLayer()
    
    override init(frame: CGRect = NSRect.zero) {
        super.init(frame: frame)
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let context = NSGraphicsContext.current!.cgContext
        context.saveGState()
        context.setFillColor(NSColor.controlBackgroundColor.cgColor)
        context.setStrokeColor((isDarkMode ? NSColor.darkGray : NSColor.lightGray).cgColor)
        context.setLineWidth(1)
        context.addEllipse(in: CGRect(x: 0, y: 0, width: self.frame.width, height: self.frame.height))
        context.drawPath(using: .fillStroke)
        context.restoreGState()
        
        let anchor = CGPoint(x: 0.5, y: 0)
        let center = CGPoint(x: self.frame.size.width / 2, y: self.frame.size.height / 2)
        
        let hourAngle: CGFloat = CGFloat(Double(hour) * (360.0 / 12.0)) + CGFloat(Double(minute) * (1.0 / 60.0) * (360.0 / 12.0))
        let minuteAngle: CGFloat = CGFloat(minute) * CGFloat(360.0 / 60.0)
        let secondsAngle: CGFloat = CGFloat(self.second) * CGFloat(360.0 / 60.0)
        
        self.hourLayer.backgroundColor = NSColor.labelColor.cgColor
        self.hourLayer.anchorPoint = anchor
        self.hourLayer.position = center
        self.hourLayer.cornerRadius = 2
        self.hourLayer.bounds = CGRect(x: 0, y: 0, width: 2, height: self.frame.size.width / 2 - 4)
        self.hourLayer.transform = CATransform3DMakeRotation(-hourAngle / 180 * CGFloat(Double.pi), 0, 0, 1)
        self.layer?.addSublayer(self.hourLayer)
        
        self.minuteLayer.backgroundColor = NSColor.secondaryLabelColor.cgColor
        self.minuteLayer.anchorPoint = anchor
        self.minuteLayer.position = center
        self.minuteLayer.cornerRadius = 2
        self.minuteLayer.bounds = CGRect(x: 0, y: 0, width: 2, height: self.frame.size.width / 2 - 2)
        self.minuteLayer.transform = CATransform3DMakeRotation(-minuteAngle / 180 * CGFloat(Double.pi), 0, 0, 1)
        self.layer?.addSublayer(self.minuteLayer)
        
        self.secondsLayer.backgroundColor = NSColor.red.cgColor
        self.secondsLayer.anchorPoint = anchor
        self.secondsLayer.position = center
        self.secondsLayer.cornerRadius = 1
        self.secondsLayer.bounds = CGRect(x: 0, y: 0, width: 1, height: self.frame.size.width / 2 - 1)
        self.secondsLayer.transform = CATransform3DMakeRotation(-secondsAngle / 180 * CGFloat(Double.pi), 0, 0, 1)
        self.layer?.addSublayer(self.secondsLayer)
        
        self.pinLayer.fillColor = NSColor.controlBackgroundColor.cgColor
        self.pinLayer.strokeColor = (isDarkMode ? NSColor.darkGray : NSColor.lightGray).cgColor
        self.pinLayer.anchorPoint = anchor
        self.pinLayer.path = CGMutablePath(roundedRect: CGRect(
            x: center.x - 3 / 2,
            y: center.y - 3 / 2,
            width: 3,
            height: 3
        ), cornerWidth: 4, cornerHeight: 4, transform: nil)
        self.layer?.addSublayer(self.pinLayer)
    }
    
    public func setValue(_ value: Date) {
        self.hour = self.calendar.component(.hour, from: value)
        self.minute = self.calendar.component(.minute, from: value)
        self.second = self.calendar.component(.second, from: value)
        
        DispatchQueue.main.async(execute: {
            self.display()
        })
    }
}

private class OrderTableView: NSView, NSTableViewDelegate, NSTableViewDataSource {
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private var dragDropType = NSPasteboard.PasteboardType(rawValue: "\(Bundle.main.bundleIdentifier!).sensors-row")
    
    public var reorderCallback: () -> Void = {}
    public var list: [Clock_t] = []
    
    init() {
        super.init(frame: NSRect.zero)
        
        self.wantsLayer = true
        self.layer?.cornerRadius = 3
        
        self.scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView.documentView = self.tableView
        self.scrollView.hasHorizontalScroller = false
        self.scrollView.hasVerticalScroller = true
        self.scrollView.autohidesScrollers = true
        self.scrollView.backgroundColor = NSColor.clear
        self.scrollView.drawsBackground = true
        
        self.tableView.frame = self.scrollView.bounds
        self.tableView.delegate = self
        self.tableView.dataSource = self
        self.tableView.backgroundColor = NSColor.clear
        self.tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        self.tableView.registerForDraggedTypes([dragDropType])
        self.tableView.gridColor = .gridColor
        self.tableView.gridStyleMask = [.solidVerticalGridLineMask, .solidHorizontalGridLineMask]
        self.tableView.style = .plain
        
        let nameColumn = NSTableColumn(identifier: nameColumnID)
        nameColumn.headerCell.title = localizedString("Name")
        nameColumn.headerCell.alignment = .center
        let statusColumn = NSTableColumn(identifier: statusColumnID)
        statusColumn.headerCell.title = ""
        statusColumn.width = 16
        
        self.tableView.addTableColumn(nameColumn)
        self.tableView.addTableColumn(statusColumn)
        
        self.addSubview(self.scrollView)
        
        NSLayoutConstraint.activate([
            self.scrollView.leftAnchor.constraint(equalTo: self.leftAnchor),
            self.scrollView.rightAnchor.constraint(equalTo: self.rightAnchor),
            self.scrollView.topAnchor.constraint(equalTo: self.topAnchor),
            self.scrollView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            
            self.heightAnchor.constraint(equalToConstant: 120)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func update() {
        self.tableView.reloadData()
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return self.list.count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if !self.list.indices.contains(row) { return nil }
        let item = self.list[row]
        
        let cell = NSTableCellView()
        
        switch tableColumn?.identifier {
        case nameColumnID:
            let text: NSTextField = NSTextField()
            text.drawsBackground = false
            text.isBordered = false
            text.isEditable = false
            text.isSelectable = false
            text.translatesAutoresizingMaskIntoConstraints = false
            text.identifier = NSUserInterfaceItemIdentifier(item.name)
            text.stringValue = item.name
            
            text.sizeToFit()
            
            cell.addSubview(text)
            
            NSLayoutConstraint.activate([
                text.widthAnchor.constraint(equalTo: cell.widthAnchor),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        case statusColumnID:
            let button: NSButton = NSButton(frame: NSRect(x: 0, y: 5, width: 10, height: 10))
            button.identifier = NSUserInterfaceItemIdentifier("\(row)")
            button.setButtonType(.switch)
            button.state = item.popupState ? .on : .off
            button.action = #selector(self.toggleClock)
            button.title = ""
            button.isBordered = false
            button.isTransparent = false
            button.target = self
            button.sizeToFit()
            
            cell.addSubview(button)
        default: break
        }
        
        return cell
    }
    
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(String(row), forType: self.dragDropType)
        return item
    }
    
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        if dropOperation == .above {
            return .move
        }
        return []
    }
    
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        var oldIndexes = [Int]()
        info.enumerateDraggingItems(options: [], for: tableView, classes: [NSPasteboardItem.self], searchOptions: [:]) { dragItem, _, _ in
            if let item = dragItem.item as? NSPasteboardItem, let str = item.string(forType: self.dragDropType), let index = Int(str) {
                oldIndexes.append(index)
            }
        }
        
        var oldIndexOffset = 0
        var newIndexOffset = 0
        
        tableView.beginUpdates()
        for oldIndex in oldIndexes {
            let currentIdx: Int
            let newIdx: Int
            
            if oldIndex < row {
                currentIdx = oldIndex + oldIndexOffset
                newIdx = row - 1
                oldIndexOffset -= 1
            } else {
                currentIdx = oldIndex
                newIdx = row + newIndexOffset
                newIndexOffset += 1
            }
            
            if self.list.indices.contains(currentIdx) && self.list.indices.contains(newIdx) {
                self.list.insert(self.list.remove(at: currentIdx), at: newIdx)
            }
        }
        for i in self.list.indices {
            self.list[i].popupIndex = i
        }
        self.reorderCallback()
        tableView.reloadData()
        tableView.endUpdates()
        
        return true
    }
    
    @objc private func toggleClock(_ sender: NSButton) {
        guard let id = sender.identifier, let i = Int(id.rawValue) else { return }
        self.list[i].popupState = sender.state == NSControl.StateValue.on
    }
}
