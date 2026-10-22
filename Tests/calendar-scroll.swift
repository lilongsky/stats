// Appended to the production Clock popup source by run-calendar-checks.py so
// these checks exercise the real private AppKit views without shipping test APIs.
private extension CalendarView {
    func verifyCalendarScrolling(_ check: (Bool, String) -> Void) {
        let calendar = Calendar.current
        func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day))!
        }
        func scroll(to y: CGFloat) {
            self.scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
            self.scrolled()
        }
        self.rebuild(around: self.weekStart(containing: date(2026, 10, 1)), offset: 0)
        let initial = self.visiblePosition()!
        scroll(to: self.scrollView.contentView.bounds.minY + 7)
        let small = self.visiblePosition()!
        check(small.week == initial.week && small.offset > 0 && small.offset < self.itemSize.height,
              "small scroll moves within a week instead of switching an entire month")

        self.rebuild(around: self.weekStart(containing: date(2026, 10, 25)), offset: self.itemSize.height * 0.8)
        check(self.month == 11 && self.year == 2026,
              "month title follows the visible week when the previous month's row has mostly scrolled away")

        for row in [40, 3, 41, 2] {
            let oldFirst = self.firstWeek!
            let expected = calendar.date(byAdding: .day, value: row * 7, to: oldFirst)!
            scroll(to: CGFloat(row) * self.itemSize.height + 7)
            let visible = self.visiblePosition()!
            check(visible.week == expected, "rebase preserves the visible week in either direction")
            check(abs(visible.offset - 7) < 0.6, "rebase preserves the partial-row scroll offset")
            check(self.dayViews.count == 48 * 7, "repeated scrolling keeps a bounded date cache")
        }

        self.rebuild(around: self.weekStart(containing: date(2024, 2, 1)), offset: 0)
        let dates = self.dayViews.map { calendar.date(from: $0.testComponents)! }
        check(Set(dates).count == dates.count, "continuous weeks do not duplicate dates at month boundaries")
        check(zip(dates, dates.dropFirst()).allSatisfy {
            calendar.dateComponents([.day], from: $0.0, to: $0.1).day == 1
        }, "all cached dates are consecutive across months and years")
        check(dates.contains(date(2024, 2, 29)), "leap day is present")

        self.rebuild(around: self.weekStart(containing: date(2026, 12, 1)), offset: 0)
        self.nextMonth()
        check(self.year == 2027 && self.month == 1, "next arrow crosses the year boundary")
        self.prevMonth()
        check(self.year == 2026 && self.month == 12, "previous arrow crosses back")
        let started = Date()
        for _ in 0..<36 { self.nextMonth() }
        check(self.year == 2029 && self.month == 12, "arrows continue past the cached range")
        for _ in 0..<36 { self.prevMonth() }
        check(self.year == 2026 && self.month == 12, "reverse navigation restores the month")
        print(String(format: "72 month navigations: %.3f seconds", Date().timeIntervalSince(started)))

        scroll(to: self.scrollView.contentView.bounds.minY + 7)
        let before = self.visiblePosition()!
        self.setShowWeekNumbers(false)
        let after = self.visiblePosition()!
        check(before.week == after.week && abs(before.offset - after.offset) < 0.6,
              "changing week-number visibility preserves the scroll position")
        check(self.weekdayHeader.numberOfColumns == 7, "weekdays remain fixed without week numbers")
        self.setShowWeekNumbers(true)
        check(self.weekdayHeader.numberOfColumns == 8, "week numbers restore with aligned date columns")
        check(abs(self.scrollView.frame.height - self.itemSize.height * 6) < 1,
              "calendar keeps its six-week viewport")
        self.checkCurrentDay()
        check(self.year == self.currentYear && self.month == self.currentMonth,
              "reopening returns to the current month")
    }

    func verifyCalendarPickers(_ check: (Bool, String) -> Void) {
        let calendar = Calendar.current
        let symbols = calendar.standaloneMonthSymbols
        self.goToToday()
        let identities = self.dayViews.map { ObjectIdentifier($0) }
        check(identities.count == 336, "picker navigation starts with the bounded 336-date view pool")
        check(self.monthPicker.cell is NSPopUpButtonCell && self.yearPicker.cell is NSPopUpButtonCell &&
              !self.monthPicker.pullsDown && !self.yearPicker.pullsDown,
              "month and year use native AppKit selection popups")
        check(self.monthPicker.window === self.window && self.yearPicker.window === self.window &&
              self.monthPicker.isEnabled && self.yearPicker.isEnabled,
              "both pickers are enabled controls in the real calendar window")
        check(self.monthPicker.target === self && self.monthPicker.action == #selector(self.selectMonth(_:)) &&
              self.yearPicker.target === self && self.yearPicker.action == #selector(self.selectYear(_:)),
              "native picker target-actions are connected to calendar navigation")
        check(self.monthPicker.itemArray.map { $0.title } == symbols &&
              self.monthPicker.itemArray.map { $0.tag } == Array(1...symbols.count),
              "month menu uses localized standalone names with numeric month tags")

        func checkSelection(_ context: String) {
            check(self.monthPicker.selectedItem?.tag == self.month &&
                  self.yearPicker.selectedItem?.tag == self.year,
                  "both selected picker values follow \(context)")
        }
        func checkViews(_ context: String) {
            check(self.dayViews.map { ObjectIdentifier($0) } == identities,
                  "\(context) reuses the same 336 date-view objects")
            check(abs(self.scrollView.frame.height - self.itemSize.height * 6) < 1,
                  "\(context) preserves the six-week viewport")
        }
        func refreshYearMenu() -> NSMenu {
            check(self.yearPicker.menu != nil, "native year picker has a menu")
            let menu = self.yearPicker.menu!
            check(menu.delegate === self, "year menu delegates refreshes to the calendar")
            self.menuNeedsUpdate(menu)
            let expected = Array(max(1, self.year - 50)...(self.year + 50))
            check(menu.items.map { $0.tag } == expected,
                  "opening the year menu rebuilds a consecutive range around the displayed year")
            check(self.yearPicker.selectedItem?.tag == self.year,
                  "opening the year menu keeps the displayed year selected")
            return menu
        }
        func chooseMonth(_ value: Int) {
            self.monthPicker.selectItem(withTag: value)
            check(self.monthPicker.selectedItem?.tag == value, "requested month is selectable by its tag")
            check(self.monthPicker.sendAction(self.monthPicker.action, to: self.monthPicker.target),
                  "selecting a native month item dispatches its calendar action")
            checkSelection("month selection")
            checkViews("month selection")
        }
        func chooseYear(_ value: Int) {
            _ = refreshYearMenu()
            self.yearPicker.selectItem(withTag: value)
            check(self.yearPicker.selectedItem?.tag == value, "requested year is selectable by its tag")
            check(self.yearPicker.sendAction(self.yearPicker.action, to: self.yearPicker.target),
                  "selecting a native year item dispatches its calendar action")
            checkSelection("year selection")
            checkViews("year selection")
        }

        self.jump(toYear: 2026, month: 1)
        let initialMenu = refreshYearMenu()
        check(initialMenu.numberOfItems == 101 && initialMenu.items.first?.tag == 1976 &&
              initialMenu.items.last?.tag == 2076,
              "ordinary year menus contain exactly the current year and fifty years on either side")
        chooseYear(2024)
        check(self.year == 2024 && self.month == 1, "choosing 2024 preserves the selected month")
        chooseMonth(2)
        check(self.year == 2024 && self.month == 2 && self.dayViews.contains {
            $0.testComponents.year == 2024 && $0.testComponents.month == 2 && $0.testComponents.day == 29
        }, "choosing February 2024 displays its leap day")
        chooseYear(2023)
        let february2023 = self.dayViews.filter {
            $0.testComponents.year == 2023 && $0.testComponents.month == 2
        }
        check(self.year == 2023 && self.month == 2 && february2023.count == 28 &&
              february2023.allSatisfy { ($0.testComponents.day ?? 0) <= 28 },
              "switching to 2023 keeps February without overflowing into March")

        chooseMonth(12)
        check(self.year == 2023 && self.month == 12, "December selection stays in the selected year")
        self.nextMonth()
        check(self.year == 2024 && self.month == 1, "next arrow crosses from selected December into January")
        checkSelection("the forward year boundary")
        self.prevMonth()
        check(self.year == 2023 && self.month == 12, "previous arrow returns to the selected December")
        chooseMonth(1)
        self.prevMonth()
        check(self.year == 2022 && self.month == 12, "previous arrow crosses from selected January into December")
        checkSelection("the reverse year boundary")
        self.nextMonth()
        check(self.year == 2023 && self.month == 1, "next arrow returns to the selected January")
        checkViews("arrow navigation after picker selection")

        self.jump(toYear: 2140, month: 9)
        let distantMenu = refreshYearMenu()
        check(distantMenu.numberOfItems == 101 && distantMenu.items.first?.tag == 2090 &&
              distantMenu.items.last?.tag == 2190 && self.yearPicker.selectedItem?.tag == 2140,
              "a distant jump recenters the native year menu on 2140")
        chooseYear(2141)
        check(self.year == 2141 && self.month == 9, "a year from the refreshed distant menu remains selectable")

        self.scrollView.contentView.scroll(to: NSPoint(x: 0,
            y: self.scrollView.contentView.bounds.minY + 7))
        self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
        self.scrolled()
        let beforeMenu = (year: self.year, month: self.month, day: self.day, firstWeek: self.firstWeek)
        let beforePosition = self.visiblePosition()!
        let beforeDates = self.dayViews.map { $0.testComponents }
        // No action is sent: this covers menu preparation followed by cancellation,
        // without synthesizing OS menu tracking or a physical pointer click.
        _ = refreshYearMenu()
        if let monthMenu = self.monthPicker.menu { self.menuNeedsUpdate(monthMenu) }
        let afterPosition = self.visiblePosition()!
        check(self.year == beforeMenu.year && self.month == beforeMenu.month && self.day == beforeMenu.day &&
              self.firstWeek == beforeMenu.firstWeek && self.dayViews.map { $0.testComponents } == beforeDates &&
              afterPosition.week == beforePosition.week && abs(afterPosition.offset - beforePosition.offset) < 0.6,
              "preparing and cancelling the menus leaves the calendar date and scroll position unchanged")
        checkSelection("menu preparation without an action")
        checkViews("menu preparation without an action")

        self.jump(toYear: 1, month: 6)
        let earliestMenu = refreshYearMenu()
        check(earliestMenu.numberOfItems == 51 && earliestMenu.items.first?.tag == 1 &&
              earliestMenu.items.last?.tag == 51,
              "the year menu clamps its lower bound to year one")
        chooseYear(2)
        check(self.year == 2 && self.month == 6, "the clamped year menu still navigates while preserving the month")

        self.jump(toYear: 2026, month: 12)
        let oldFirst = self.firstWeek
        for weeks in [6, 20] {
            self.scrollView.contentView.scroll(to: NSPoint(x: 0,
                y: self.scrollView.contentView.bounds.minY + CGFloat(weeks) * self.itemSize.height + 7))
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
            self.scrolled()
            if weeks == 6 {
                check(self.year == 2027 && self.month == 1, "scrolling moves the displayed month across the year boundary")
            }
            checkSelection("scrolling, including a date-buffer rebase")
            checkViews("scrolling with native pickers")
        }
        check(self.firstWeek != oldFirst, "picker synchronization also covers a real date-buffer rebase")
        self.goToToday()
        check(self.year == self.currentYear && self.month == self.currentMonth,
              "Today returns from the selected and scrolled dates to the current month")
        checkSelection("Today")
        checkViews("Today after picker navigation")

        func visibleControls(in view: NSView) -> [NSControl] {
            guard !view.isHidden else { return [] }
            if let control = view as? NSControl { return [control] }
            return view.subviews.flatMap { visibleControls(in: $0) }
        }
        check(abs(self.bounds.width - 264) < 0.6, "picker layout is exercised at the real 264-point calendar width")
        for value in 1...symbols.count {
            chooseMonth(value)
            self.window?.layoutIfNeeded()
            self.layoutSubtreeIfNeeded()
            let navigation = self.arrangedSubviews[0]
            let controls = visibleControls(in: navigation)
            let frames = controls.map { $0.convert($0.bounds, to: self) }
            check(controls.count >= 5 && controls.contains { $0 === self.monthPicker } &&
                  controls.contains { $0 === self.yearPicker },
                  "navigation retains native month, year, Today and arrow controls")
            check(self.monthPicker.bounds.width >= 51.4 && self.yearPicker.bounds.width >= 59.4,
                  "every localized month leaves usable 52/60-point month and year click widths")
            check(frames.allSatisfy { !$0.isEmpty && self.bounds.insetBy(dx: -0.6, dy: -0.6).contains($0) },
                  "all navigation controls fit inside the 264-point calendar")
            var overlaps = false
            for first in frames.indices {
                for second in frames.indices where second > first {
                    let intersection = frames[first].intersection(frames[second])
                    if !intersection.isNull && intersection.width > 0.6 && intersection.height > 0.6 {
                        overlaps = true
                    }
                }
            }
            let geometry = zip(controls, frames).map { "\($0.0.identifier?.rawValue ?? String(describing: type(of: $0.0))):\($0.1)" }.joined(separator: ", ")
            check(!overlaps, "localized month and year pickers never overlap navigation controls (\(geometry))")
        }
        self.goToToday()
        checkSelection("Today after checking all localized month widths")
        checkViews("all picker layout checks")
    }

    func verifyCalendarHover(_ check: (Bool, String) -> Void) {
        self.rebuild(around: self.weekStart(containing: Date()), offset: 0)
        let cell = self.dayViews[(self.anchorRow + 1) * 7 + 2]
        let point = cell.convert(NSPoint(x: cell.bounds.midX, y: cell.bounds.midY), to: nil)
        let event = NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: self.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
        func highlighted() -> [CalendarItemView] { self.dayViews.filter { $0.testHovered } }

        self.document.mouseEntered(with: event)
        check(highlighted().count == 1 && highlighted().first === cell,
              "pointer entry highlights exactly the date under the pointer")
        var previous = cell.testComponents
        for _ in 0..<20 {
            self.scrollView.contentView.scroll(to: NSPoint(x: 0,
                y: self.scrollView.contentView.bounds.minY + self.itemSize.height))
            self.scrolled()
            check(highlighted().count <= 1, "scroll notifications never leave multiple highlighted dates")
            // Keep the pointer still while dates move beneath it, including a cache rebase.
            self.document.mouseMoved(with: event)
            let active = highlighted()
            check(active.count == 1, "stationary pointer retains exactly one highlighted date while scrolling")
            check(active.first?.testComponents != previous, "hover follows the newly visible date instead of the old date")
            previous = active[0].testComponents
        }
        self.document.mouseExited(with: event)
        check(highlighted().isEmpty, "leaving the calendar clears hover")
        self.document.mouseEntered(with: event)
        self.updateHover(at: NSPoint(x: -100, y: -100))
        check(highlighted().isEmpty, "pointer outside the clipped date grid clears hover")
        self.rebuild(around: self.weekStart(containing: Date()), offset: 0)
        if let today = self.dayViews.first(where: { $0.testIsToday }) {
            let todayPoint = today.convert(NSPoint(x: today.bounds.midX, y: today.bounds.midY), to: nil)
            self.updateHover(at: todayPoint)
            check(highlighted().isEmpty, "today keeps its red marker without a gray hover background")
        }
    }

    func verifyCalendarDateUpdates(_ check: (Bool, String) -> Void) {
        let calendar = Calendar.current
        self.goToToday()
        check(self.dayViews.filter { $0.testTodayVisible }.count == 1,
              "today has exactly one visible red marker")
        let distant = calendar.date(byAdding: .year, value: -20, to: Date())!
        self.rebuild(around: self.weekStart(containing: distant), offset: 7)
        check(self.dayViews.allSatisfy { !$0.testTodayVisible },
              "scrolling far from today removes the old red marker")
        for index in [0, self.anchorRow * 7 + 2, self.dayViews.count - 1] {
            let item = self.dayViews[index]
            check(item.testDayText == "\(item.testComponents.day!)",
                  "date text follows the newly visible date after a cache rebase")
            check(item.toolTip == item.testFormattedDate,
                  "date tooltip follows the new date used by click actions")
        }
        for showNumbers in [false, true] {
            self.setShowWeekNumbers(showNumbers)
            self.window?.layoutIfNeeded()
            let item = self.dayViews[(self.anchorRow + 1) * 7 + 2]
            let center = item.convert(NSPoint(x: item.bounds.midX, y: item.bounds.midY), to: nil)
            self.updateHover(at: center)
            check(item.testHovered && self.dayViews.filter { $0.testHovered }.count == 1,
                  "hover stays aligned with date columns after changing week numbers")
            let edge = self.dayViews[(self.anchorRow + 1) * 7 + 6].frame.maxX
            check(abs(edge - self.document.bounds.maxX) < 0.6,
                  "date columns fill the grid without horizontal clipping")
        }
        self.goToToday()
        check(self.dayViews.filter { $0.testTodayVisible }.count == 1,
              "return to today restores the current date marker after distant scrolling")
    }
}

private extension CalendarItemView {
    var testComponents: DateComponents { self.components }
    var testHovered: Bool { self.hovered }
    var testIsToday: Bool { self.isToday }
    var testTodayVisible: Bool { !self.circle.isHidden }
    var testDayText: String { self.field.stringValue }
    var testFormattedDate: String? { self.formattedDate() }
}

@main
private struct CalendarScrollChecks {
    static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let view = CalendarView(264, showWeekNumbers: true)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 264, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.layoutIfNeeded()
        var checks = 0
        func check(_ result: Bool, _ message: String) {
            guard result else {
                FileHandle.standardError.write(Data("Calendar check failed: \(message)\n".utf8))
                Darwin.exit(1)
            }
            checks += 1
        }
        view.verifyCalendarScrolling(check)
        view.verifyCalendarHover(check)
        view.verifyCalendarDateUpdates(check)
        view.verifyCalendarPickers(check)
        window.close()
        print("Passed \(checks) real AppKit calendar navigation and scrolling checks")
    }
}
