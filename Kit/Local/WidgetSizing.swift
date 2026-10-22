import Cocoa

public extension WidgetWrapper {
    var dimensionKey: String { "\(self.title)_\(self.type.rawValue)_customDimension" }
    var spacingKey: String { "\(self.title)_\(self.type.rawValue)_customSpacing" }

    private var settingsDefaultDimension: Int {
        if let line = self as? LineChart { return Int(line.automaticGraphWidth) }
        if let network = self as? NetworkChart { return Int(network.automaticGraphWidth) }
        return self.type == .pieChart ? (self.compact ? 18 : Int(self.frame.height)) : (self.compact ? 7 : 11)
    }

    func configuredDimension(_ fallback: CGFloat) -> CGFloat {
        let configured = Store.shared.int(key: self.dimensionKey, defaultValue: 0)
        guard configured > 0 else { return fallback }
        if self.type == .pieChart {
            return min(max(10, CGFloat(configured)), self.frame.height)
        }
        return min(160, max(6, CGFloat(configured)))
    }

    func dimensionSettings() -> NSView {
        var rows: [NSView] = [self.compactSizeRow()]
        var dimensionInput: StepperInput?
        let isDiameter = self.type == .pieChart
        let supportsWidth = [.lineChart, .barChart, .networkChart].contains(self.type)
        if isDiameter || supportsWidth {
            let fallback = self.settingsDefaultDimension
            let input = StepperInput(Store.shared.int(key: self.dimensionKey, defaultValue: fallback),
                                     range: NSRange(location: isDiameter ? 10 : 6,
                                                    length: isDiameter ? max(0, Int(self.frame.height) - 10) : 154),
                                     unit: "pt") { [weak self] value in
                guard let self else { return }
                Store.shared.set(key: self.dimensionKey, value: value)
                self.compactChanged()
            }
            dimensionInput = input
            input.identifier = NSUserInterfaceItemIdentifier("widget-dimension-input")
            rows.append(PreferencesRow(localizedString(isDiameter ? "Pie Diameter" : "Graph Width"), component: input))
        }
        let spacingInput = StepperInput(
            Store.shared.int(key: self.spacingKey, defaultValue: self.compact ? 2 : 14),
            range: NSRange(location: 0, length: 20), unit: "pt"
        ) { [weak self] value in
            guard let self else { return }
            Store.shared.set(key: self.spacingKey, value: value)
            self.compactChanged()
        }
        spacingInput.identifier = NSUserInterfaceItemIdentifier("widget-spacing-input")
        self.updateSizingSettings = { [weak self, weak dimensionInput, weak spacingInput] in
            guard let self else { return }
            dimensionInput?.updateValue(Int(self.configuredDimension(CGFloat(self.settingsDefaultDimension))))
            spacingInput?.updateValue(Store.shared.int(key: self.spacingKey, defaultValue: self.compact ? 2 : 14))
        }
        rows.append(PreferencesRow(localizedString("Item Spacing"), component: spacingInput))
        let reset = LocalActionButton(localizedString("Restore Size and Spacing")) { [weak self] in
            guard let self else { return }
            Store.shared.remove(self.dimensionKey)
            Store.shared.remove(self.spacingKey)
            self.compactChanged()
            self.updateSizingSettings?()
        }
        reset.identifier = NSUserInterfaceItemIdentifier("widget-size-reset")
        rows.append(PreferencesRow(localizedString("Size preset"), component: reset))
        return PreferencesSection(title: localizedString("Size and Spacing"),
            subtitle: localizedString("Changes apply to this widget and appear immediately in the menu bar."), rows)
    }
}
