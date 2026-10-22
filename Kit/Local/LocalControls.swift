import Cocoa

public extension Notification.Name {
    static let localPopupOptionsChanged = Notification.Name("StatsCompact.popupOptionsChanged")
}

public final class LocalActionButton: NSButton {
    private let handler: () -> Void
    public init(_ title: String, symbol: String? = nil, action: @escaping () -> Void) {
        self.handler = action
        super.init(frame: .zero)
        self.title = title
        self.bezelStyle = .rounded
        self.controlSize = .small
        self.font = .systemFont(ofSize: 12)
        self.target = self
        self.action = #selector(invoke)
        if let symbol {
            self.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            self.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { self.handler() }
}

public final class LocalChoice: NSPopUpButton {
    private let handler: (Int) -> Void
    public init(_ titles: [String], selected: Int, action: @escaping (Int) -> Void) {
        self.handler = action
        super.init(frame: .zero, pullsDown: false)
        self.controlSize = .small
        self.font = .systemFont(ofSize: 13)
        self.cell?.lineBreakMode = .byTruncatingTail
        self.addItems(withTitles: titles)
        self.selectItem(at: min(max(0, selected), max(0, titles.count - 1)))
        self.target = self
        self.action = #selector(invoke)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { self.handler(self.indexOfSelectedItem) }
}

public final class LocalToggle: NSSwitch {
    private let handler: (Bool) -> Void
    public init(_ enabled: Bool, action: @escaping (Bool) -> Void) {
        self.handler = action
        super.init(frame: .zero)
        self.controlSize = .small
        self.heightAnchor.constraint(equalToConstant: 25).isActive = true
        self.state = enabled ? .on : .off
        self.target = self
        self.action = #selector(invoke)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { self.handler(self.state == .on) }
}

public func localFeatureLabel(_ text: String) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.font = .systemFont(ofSize: 11)
    label.textColor = .secondaryLabelColor
    return label
}
