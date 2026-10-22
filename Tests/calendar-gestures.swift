// Replay inertial delta curves and abrupt reversals through the production
// calendar's native clip view. This measures date continuity and processing cost,
// not physical touchpad input, NSScrollView's private animator, or display FPS.
private extension CalendarView {
    func verifyCalendarGestures() -> [String: Any] {
        let calendar = Calendar.current
        self.goToToday()
        let reference = self.visiblePosition()!.week
        func position() -> Double {
            let visible = self.visiblePosition()!
            let days = calendar.dateComponents([.day], from: reference, to: visible.week).day!
            return Double(days) / 7 * self.itemSize.height + visible.offset
        }
        var samples: [[String: Any]] = []
        func deliver(_ delta: CGFloat, name: String) {
            let before = position()
            let start = DispatchTime.now().uptimeNanoseconds
            self.scrollView.contentView.scroll(to: NSPoint(x: 0,
                y: self.scrollView.contentView.bounds.minY + delta))
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
            self.scrolled()
            self.window?.layoutIfNeeded()
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            let movement = position() - before
            samples.append(["name": name, "delta": delta, "movement": movement,
                            "error": movement - delta, "handling_ms": elapsed])
        }
        for _ in 0..<12 {
            for _ in 0..<24 { deliver(72, name: "fast forward") }
            for delta: CGFloat in [200, 160, 120, 90, 64, 40, 24, 12, 5, 2, 1] {
                deliver(delta, name: "inertial deceleration")
            }
            for _ in 0..<24 { deliver(-72, name: "fast reverse") }
            for delta: CGFloat in [-160, -100, 140, 90, 40, -100, -160, 200, -200, 240, -240] {
                deliver(delta, name: "interrupt inertia and reverse")
            }
        }
        let errors = samples.filter { abs($0["error"] as! Double) > 1.1 }
        self.goToToday()
        return ["samples": samples, "steps": samples.count, "discontinuities": errors.count,
                "max_error_points": samples.map { abs($0["error"] as! Double) }.max()!,
                "max_handling_ms": samples.map { $0["handling_ms"] as! Double }.max()!,
                "scope": "production NSClipView delta replay; physical trackpad and native momentum animator not measured"]
    }
}

@main
private struct CalendarGestureChecks {
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let view = CalendarView(264, showWeekNumbers: true)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 264, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.layoutIfNeeded()
        let report = view.verifyCalendarGestures()
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        window.close()
        if report["discontinuities"] as! Int != 0 { Darwin.exit(1) }
    }
}
