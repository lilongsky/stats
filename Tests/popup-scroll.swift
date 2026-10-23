// Exercise production popup settings in a hidden AppKit window. Synthetic
// events are delivered directly to its responders; no input event is posted.
import Cocoa
import Kit

private struct ScrollCheckError: LocalizedError {
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
            print("FAIL: " + message)
        }
    }
}

private func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(descendants)
}

private final class FlippedDocument: NSView {
    override var isFlipped: Bool { true }
}

private final class OuterScrollView: NSScrollView {
    var received: [NSEvent] = []
    override func scrollWheel(with event: NSEvent) {
        self.received.append(event)
        super.scrollWheel(with: event)
    }
}

private final class Fixture {
    let window: NSWindow
    let outer = OuterScrollView()
    let popup: PopupWrapper
    let customization: NSView
    let table: NSTableView
    let inner: NSScrollView
    let ids: [String]

    init(count: Int) throws {
        let popup = PopupWrapper(.GPU, frame: NSRect(x: 0, y: 0, width: 320, height: 0))
        popup.title = "PopupScrollFixture-" + UUID().uuidString
        popup.orientation = .vertical
        let ids = (0..<count).map { "section-\($0)" }
        for id in ids {
            let section = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 36))
            section.heightAnchor.constraint(equalToConstant: 36).isActive = true
            popup.addPopupSection(section, id: id, title: id)
        }
        popup.applySectionLayout()
        let customization = popup.customizationSettings()
        guard let table = descendants(customization).first(where: {
            $0.identifier?.rawValue == "popup-sections-table"
        }) as? NSTableView, let inner = table.enclosingScrollView else {
            throw ScrollCheckError(message: "Production section table or its scroll view is missing")
        }
        self.popup = popup
        self.ids = ids
        self.customization = customization
        self.table = table
        self.inner = inner
        self.window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 400),
                               styleMask: [.borderless], backing: .buffered, defer: false)
        self.window.isReleasedWhenClosed = false
        self.outer.hasVerticalScroller = true
        self.outer.verticalScrollElasticity = .none
        self.window.contentView = self.outer
        let document = FlippedDocument(frame: NSRect(x: 0, y: 0, width: 540, height: 1200))
        self.outer.documentView = document
        customization.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(customization)
        NSLayoutConstraint.activate([
            customization.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 16),
            customization.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -16),
            customization.topAnchor.constraint(equalTo: document.topAnchor, constant: 16)
        ])
        self.window.layoutIfNeeded()
        self.table.reloadData()
        self.window.layoutIfNeeded()
        for row in 0..<count { _ = self.table.view(atColumn: 0, row: row, makeIfNecessary: true) }
        self.window.layoutIfNeeded()
    }

    func scroll(_ delta: Int32) throws -> NSEvent {
        // Pixel wheel event remains local to this hidden fixture. It is never
        // passed to CGEvent.post, NSApplication.sendEvent or the global queue.
        guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                               wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0),
              let event = NSEvent(cgEvent: cg) else {
            throw ScrollCheckError(message: "Could not construct a local scroll event")
        }
        self.inner.scrollWheel(with: event)
        self.window.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        return event
    }
}

private func verifyShortList(_ count: Int, _ checks: Checks) throws {
    let fixture = try Fixture(count: count)
    defer { fixture.window.close() }
    let event = try fixture.scroll(-120)
    checks.check(!fixture.inner.hasVerticalScroller, "\(count) rows: no internal scrollbar")
    checks.check(fixture.outer.received.count == 1 && fixture.outer.received.first === event,
                 "\(count) rows: outer settings receives the original scroll event once")
    checks.check(abs(fixture.inner.contentView.bounds.minY) < 0.6,
                 "\(count) rows: fully visible section list does not shift")
    let reversed = try fixture.scroll(60)
    checks.check(fixture.outer.received.count == 2 && fixture.outer.received.last === reversed,
                 "\(count) rows: immediate reverse event reaches the outer settings page once")
    checks.check(!Store.shared.exist(key: "\(fixture.popup.title)_popup_sectionOrder") &&
                 !Store.shared.exist(key: "\(fixture.popup.title)_popup_hiddenSections"),
                 "\(count) rows: scrolling leaves section preferences untouched")
    if count > 0 {
        let last = fixture.table.rect(ofRow: count - 1)
        checks.check(fixture.inner.contentView.bounds.insetBy(dx: -0.6, dy: -0.6).contains(last),
                     "\(count) rows: last row remains fully visible")
    }
}

private func verifyLongList(_ checks: Checks) throws {
    let fixture = try Fixture(count: 10)
    defer { fixture.window.close() }
    let outerBefore = fixture.outer.contentView.bounds.minY
    _ = try fixture.scroll(-24)
    checks.check(fixture.inner.hasVerticalScroller, "10 rows: internal scrollbar is retained")
    checks.check(fixture.outer.received.isEmpty &&
                 abs(fixture.outer.contentView.bounds.minY - outerBefore) < 0.6,
                 "10 rows: a scroll within available inner content does not move the outer page")
    // AppKit's private wheel animator does not run for an unshown window.
    // Verify native table scrolling separately; physical wheel movement is
    // checked through the running application, not inferred from this fixture.
    fixture.table.scrollRowToVisible(9)
    checks.check(fixture.inner.contentView.bounds.minY > 0 &&
                 fixture.table.visibleRect.intersects(fixture.table.rect(ofRow: 9)),
                 "10 rows: native scrolling can reveal the last section")

    fixture.window.makeFirstResponder(fixture.table)
    fixture.table.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
    for (keyCode, character, expected) in [(UInt16(125), "\u{F701}", 3), (UInt16(126), "\u{F700}", 2)] {
        guard let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                        timestamp: 0, windowNumber: fixture.window.windowNumber,
                                        context: nil, characters: character,
                                        charactersIgnoringModifiers: character, isARepeat: false,
                                        keyCode: keyCode) else {
            throw ScrollCheckError(message: "Could not construct a local arrow-key event")
        }
        fixture.table.keyDown(with: key)
        checks.check(fixture.table.selectedRow == expected,
                     "10 rows: native arrow-key selection reaches row \(expected)")
    }
    let dragType = NSPasteboard.PasteboardType("eu.exelban.Stats.Compact.popupSection")
    let writer = fixture.table.dataSource?.tableView?(fixture.table, pasteboardWriterForRow: 2)
    checks.check(fixture.table.registeredDraggedTypes.contains(dragType) &&
                 (writer as? NSPasteboardItem)?.string(forType: dragType) == fixture.ids[2],
                 "10 rows: native drag registration and row pasteboard writer are retained")

    guard let moveDown = descendants(fixture.customization).first(where: {
        $0.identifier?.rawValue == "popup-section-down-section-2"
    }) as? NSControl, let action = moveDown.action else {
        throw ScrollCheckError(message: "Production section move action is missing")
    }
    checks.check(moveDown.sendAction(action, to: moveDown.target), "10 rows: move-down action is reachable")
    var expected = fixture.ids
    expected.swapAt(2, 3)
    checks.check(fixture.popup.orderedSectionIDs() == expected,
                 "10 rows: production move action preserves section reordering")
}

@main
private struct PopupScrollChecks {
    static func main() {
        setbuf(stdout, nil)
        let domain = Bundle.main.bundleIdentifier ?? ""
        guard ProcessInfo.processInfo.processName.hasPrefix("stats-popup-scroll-checks-"),
              domain.hasPrefix("local.stats.popup-scroll-checks.") else {
            print("Popup scroll checks require a uniquely named isolated helper")
            exit(1)
        }
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        NSApplication.shared.setActivationPolicy(.accessory)
        let checks = Checks()
        do {
            for count in [1, 3, 8] { try verifyShortList(count, checks) }
            try verifyLongList(checks)
        } catch {
            checks.check(false, error.localizedDescription)
        }
        print("Popup scroll AppKit checks: \(checks.count) checks, \(checks.failures) failures")
        if checks.failures != 0 { exit(1) }
    }
}
