// Benchmarks the real calendar on the main thread in an isolated AppKit window.
// These timings cover event handling and layout, not display refresh/frame pacing.
private extension CalendarView {
    func measureCalendarScrolling() -> [String: Any] {
        func measure(_ action: () -> Void) -> Double {
            let start = DispatchTime.now().uptimeNanoseconds
            action()
            return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        }
        func summary(_ values: [Double]) -> [String: Double] {
            let sorted = values.sorted()
            return ["median_ms": sorted[sorted.count / 2],
                    "p95_ms": sorted[Int(Double(sorted.count - 1) * 0.95)],
                    "max_ms": sorted.last!,
                    "total_ms": sorted.reduce(0, +)]
        }
        var rebases: [Double] = []
        for index in 0..<12 {
            let date = Calendar.current.date(byAdding: .month, value: index * 5, to: Date())!
            rebases.append(measure {
                self.rebuild(around: self.weekStart(containing: date), offset: 7)
                self.window?.layoutIfNeeded()
                self.document.layoutSubtreeIfNeeded()
            })
        }
        self.goToToday()
        var frames: [Double] = []
        for index in 0..<600 {
            frames.append(measure {
                let step: CGFloat = index < 300 ? 8 : -8
                self.scrollView.contentView.scroll(to: NSPoint(x: 0,
                    y: self.scrollView.contentView.bounds.minY + step))
                self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
                self.scrolled()
                self.window?.layoutIfNeeded()
                self.document.layoutSubtreeIfNeeded()
            })
        }
        return ["rebase": summary(rebases), "scroll_steps": summary(frames),
                "steps": frames.count, "rebase_samples": rebases.count,
                "scope": "isolated production AppKit event handling and layout; not physical display frame rate"]
    }
}

@main
private struct CalendarPerformance {
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let view = CalendarView(264, showWeekNumbers: true)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 264, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.layoutIfNeeded()
        let result = view.measureCalendarScrolling()
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        window.close()
    }
}
