import Cocoa

public extension WidgetWrapper {
    var dimensionKey: String { "\(self.title)_\(self.type.rawValue)_customDimension" }
    var spacingKey: String { "\(self.title)_\(self.type.rawValue)_customSpacing" }

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
        var defaultDimension: Int = 0
        let isDiameter = self.type == .pieChart
        let supportsWidth = [.lineChart, .barChart, .networkChart].contains(self.type)
        if isDiameter || supportsWidth {
            let fallback: Int
            if let line = self as? LineChart { fallback = Int(line.automaticGraphWidth) }
            else if let network = self as? NetworkChart { fallback = Int(network.automaticGraphWidth) }
            else { fallback = isDiameter ? (self.compact ? 18 : Int(self.frame.height)) : (self.compact ? 7 : 11) }
            let input = StepperInput(Store.shared.int(key: self.dimensionKey, defaultValue: fallback),
                                     range: NSRange(location: isDiameter ? 10 : 6,
                                                    length: isDiameter ? max(0, Int(self.frame.height) - 10) : 154),
                                     unit: "pt") { [weak self] value in
                guard let self else { return }
                Store.shared.set(key: self.dimensionKey, value: value)
                self.compactChanged()
            }
            dimensionInput = input
            defaultDimension = fallback
            rows.append(PreferencesRow(isDiameter ? "饼图直径" : "图形宽度", component: input))
        }
        let spacingInput = StepperInput(
            Store.shared.int(key: self.spacingKey, defaultValue: self.compact ? 2 : 14),
            range: NSRange(location: 0, length: 20), unit: "pt"
        ) { [weak self] value in
            guard let self else { return }
            Store.shared.set(key: self.spacingKey, value: value)
            self.compactChanged()
        }
        rows.append(PreferencesRow("图标间距", component: spacingInput))
        rows.append(PreferencesRow("自动尺寸", component: LocalActionButton("恢复默认") { [weak self] in
            guard let self else { return }
            Store.shared.remove(self.dimensionKey)
            Store.shared.remove(self.spacingKey)
            self.compactChanged()
            let restored: Int
            if let line = self as? LineChart { restored = Int(line.automaticGraphWidth) }
            else if let network = self as? NetworkChart { restored = Int(network.automaticGraphWidth) }
            else if self.type == .pieChart { restored = self.compact ? 18 : Int(self.frame.height) }
            else { restored = defaultDimension }
            dimensionInput?.updateValue(restored)
            spacingInput.updateValue(self.compact ? 2 : 14)
        }))
        return PreferencesSection(title: "尺寸与间距", subtitle: "仅调整这个小组件，菜单栏会即时更新。", rows)
    }
}
