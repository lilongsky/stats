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
        view.verifyCalendarScrolling { result, message in
            precondition(result, message)
            checks += 1
        }
        view.verifyCalendarHover { result, message in
            precondition(result, message)
            checks += 1
        }
        view.verifyCalendarDateUpdates { result, message in
            precondition(result, message)
            checks += 1
        }
        window.close()
        print("Passed \(checks) real AppKit calendar scrolling checks")
    }
}
