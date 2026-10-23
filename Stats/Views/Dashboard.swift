//
//  Stats.swift
//  Stats
//
//  Created by Serhiy Mytrovtsiy on 24/12/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

class Dashboard: NSView {
    struct DisplayData {
        let deviceName: String
        let modelIdentifier: String
        let productionYear: String
        let serialNumber: String
        let operatingSystem: String
        let operatingSystemBuild: String
        let processor: String
        let memory: String
        let graphics: String
        let disks: String
        let displays: String
        let uptime: String
        let image: NSImage
    }

    private static var processorValue: String {
        guard let cpu = SystemKit.shared.device.info.cpu, cpu.name != nil || cpu.physicalCores != nil || cpu.logicalCores != nil else {
            return localizedString("Unknown")
        }
        
        var value = ""
        
        if let name = cpu.name {
            value += name
        }
        
        if cpu.physicalCores != nil || cpu.logicalCores != nil {
            if !value.isEmpty {
                value += "\n"
            }
            
            var mini = ""
            if let cores = cpu.physicalCores {
                mini += localizedString("Number of cores", "\(cores)")
            }
            if let threads = cpu.logicalCores {
                if mini != "" {
                    mini += ", "
                }
                mini += localizedString("Number of threads", "\(threads)")
            }
            value += "\(mini)"
        }
        
        if cpu.eCores != nil || cpu.pCores != nil {
            if !value.isEmpty {
                value += "\n"
            }
            
            var mini = ""
            if let eCores = cpu.eCores {
                mini += localizedString("Number of e-cores", "\(eCores)")
            }
            if let pCores = cpu.pCores {
                if mini != "" {
                    mini += "\n"
                }
                mini += localizedString("Number of p-cores", "\(pCores)")
            }
            if let sCores = cpu.sCores {
                if mini != "" {
                    mini += "\n"
                }
                mini += localizedString("Number of s-cores", "\(sCores)")
            }
            value += "\(mini)"
        }
        
        return value
    }
    private static var memoryValue: String {
        guard let dimms = SystemKit.shared.device.info.ram?.dimms else {
            return localizedString("Unknown")
        }
        
        let sizeFormatter = ByteCountFormatter()
        sizeFormatter.allowedUnits = [.useGB]
        sizeFormatter.countStyle = .memory
        
        var value = ""
        for i in 0..<dimms.count {
            let dimm = dimms[i]
            var row = ""
            
            if let size = dimm.size {
                row += size
            }
            
            if let speed = dimm.speed {
                if !row.isEmpty && row.last != " " {
                    row += " "
                }
                row += speed
            }
            
            if let type = dimm.type {
                if !row.isEmpty && row.last != " " {
                    row += " "
                }
                row += type
            }
            
            if dimm.bank != nil || dimm.channel != nil {
                if !row.isEmpty && row.last != " " {
                    row += " "
                }
                
                var mini = "("
                if let bank = dimm.bank {
                    mini += "slot \(bank)"
                }
                if let ch = dimm.channel {
                    mini += "\(mini == "(" ? "" : "/")ch \(ch)"
                }
                row += "\(mini))"
            }
            
            value += "\(row)\(i == dimms.count-1 ? "" : "\n")"
        }
        return value
    }
    private static var graphicsValue: String {
        guard let gpus = SystemKit.shared.device.info.gpu else {
            return localizedString("Unknown")
        }
        
        var value = ""
        for i in 0..<gpus.count {
            var row = gpus[i].name != nil ? gpus[i].name! : localizedString("Unknown")
            
            if gpus[i].vram != nil || gpus[i].cores != nil {
                row += " ("
                if let cores = gpus[i].cores {
                    row += localizedString("Number of cores", "\(cores)")
                }
                if let size = gpus[i].vram {
                    if gpus[i].cores != nil {
                        row += ", \(size)"
                    } else {
                        row += "\(size)"
                    }
                }
                row += ")"
            }
            
            value += "\(row)\(i == gpus.count-1 ? "" : "\n")"
        }
        return value
    }
    private static var disksValue: String {
        guard let disks = SystemKit.shared.device.info.disk else {
            return localizedString("Unknown")
        }
        
        var value = ""
        for i in 0..<disks.count {
            var row = disks[i].name != nil ? disks[i].name! : localizedString("Unknown")
            if let size = disks[i].size {
                let value = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                row += " (\(value))"
            }
            value += "\(row)\(i == disks.count-1 ? "" : "\n")"
        }
        
        return value
    }
    private static var displaysValue: String {
        guard let displays = SystemKit.shared.device.display else {
            return localizedString("Unknown")
        }
        
        var value = ""
        for i in 0..<displays.count {
            var row = displays[i].name != nil ? displays[i].name! : localizedString("Unknown")
            if let size = displays[i].size {
                let displaySize = String(format: "%.1f", size).replacingOccurrences(of: ".0", with: "")
                row += " (\(displaySize)\")"
            }
            if displays[i].resolution != nil || displays[i].refreshRate != nil {
                var details = ""
                if let res = displays[i].resolution {
                    details = "\(Int(res.width))x\(Int(res.height))"
                }
                if let rr = displays[i].refreshRate {
                    if !details.isEmpty {
                        details += ", "
                    }
                    details += "\(String(format: "%.0f", rr))Hz"
                }
                if !details.isEmpty {
                    row += "\n\(details)"
                }
            }
            value += "\(row)\(i == displays.count-1 ? "" : "\n")"
        }
        
        return value
    }
    private static var uptimeValue: String {
        let form = DateComponentsFormatter()
        form.maximumUnitCount = 2
        form.unitsStyle = .full
        form.allowedUnits = [.day, .hour, .minute]
        
        var value = localizedString("Unknown")
        if let bootDate = SystemKit.shared.device.bootDate {
            if let duration = form.string(from: bootDate, to: Date()) {
                value = duration
            }
        }
        
        return value
    }
    
    private let refreshUptime: (() -> String)?
    private var uptimeField: NSTextField?

    convenience init() {
        let device = SystemKit.shared.device
        self.init(data: DisplayData(
            deviceName: device.model.name,
            modelIdentifier: device.model.id,
            productionYear: "\(device.model.year)",
            serialNumber: device.serialNumber ?? localizedString("Unknown"),
            operatingSystem: "macOS \(device.os?.name ?? localizedString("Unknown")) (\(device.os?.version.getFullVersion() ?? ""))",
            operatingSystemBuild: device.os?.build ?? localizedString("Unknown"),
            processor: Self.processorValue,
            memory: Self.memoryValue,
            graphics: Self.graphicsValue,
            disks: Self.disksValue,
            displays: Self.displaysValue,
            uptime: Self.uptimeValue,
            image: device.model.icon
        ), refreshUptime: { Self.uptimeValue })
    }

    // Formatting is separate from layout so the actual view can also render
    // synthetic device information without reading a machine's identifiers.
    init(data: DisplayData, refreshUptime: (() -> String)? = nil) {
        self.refreshUptime = refreshUptime
        super.init(frame: .zero)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.identifier = NSUserInterfaceItemIdentifier("dashboard")

        let scrollView = ScrollableStackView(orientation: .vertical)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.identifier = NSUserInterfaceItemIdentifier("dashboard-scroll")
        scrollView.stackView.identifier = NSUserInterfaceItemIdentifier("dashboard-form")
        scrollView.stackView.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        scrollView.stackView.spacing = 20

        let hardwareFields = [
            ("processor", localizedString("Processor"), data.processor),
            ("memory", localizedString("Memory"), data.memory),
            ("graphics", localizedString("Graphics"), data.graphics),
            ("disks", localizedString("Disks"), data.disks),
            ("displays", localizedString("Display"), data.displays)
        ]
        let deviceFields = [
            ("model", localizedString("Model identifier"), data.modelIdentifier),
            ("year", localizedString("Production year"), data.productionYear),
            ("serial", localizedString("Serial number"), data.serialNumber),
            ("uptime", localizedString("Uptime"), data.uptime)
        ]
        let labelWidth = (hardwareFields + deviceFields).map {
            ($0.1 as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
        }.max().map { max(96, ceil($0)) } ?? 96

        func rows(_ fields: [(String, String, String)]) -> [NSView] {
            fields.map { key, title, value in
                let row = InformationRow(key: key, title: title, value: value, labelWidth: labelWidth)
                if key == "uptime" { self.uptimeField = row.valueField }
                return row
            }
        }

        let header = self.deviceView(data)
        let hardware = PreferencesSection(title: localizedString("Hardware"), id: "dashboard-hardware", rows(hardwareFields))
        let information = PreferencesSection(title: localizedString("Device Information"), id: "dashboard-device", rows(deviceFields))
        for view in [header, hardware, information] {
            scrollView.stackView.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: scrollView.stackView.widthAnchor, constant: -48).isActive = true
        }

        self.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: self.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(windowOpens), name: .openModuleSettings, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowOpens), name: .toggleSettings, object: nil)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .openModuleSettings, object: nil)
        NotificationCenter.default.removeObserver(self, name: .toggleSettings, object: nil)
    }
    
    private func deviceView(_ data: DisplayData) -> NSView {
        let container = NSStackView()
        container.orientation = .horizontal
        container.alignment = .centerY
        container.spacing = 16
        container.identifier = NSUserInterfaceItemIdentifier("dashboard-header")

        let deviceImageView = NSImageView(image: data.image)
        deviceImageView.imageScaling = .scaleProportionallyUpOrDown
        deviceImageView.widthAnchor.constraint(equalToConstant: 72).isActive = true
        deviceImageView.heightAnchor.constraint(equalToConstant: 72).isActive = true

        let text = NSStackView()
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 4
        text.setHuggingPriority(.defaultLow, for: .horizontal)

        let deviceNameField = NSTextField(wrappingLabelWithString: data.deviceName)
        deviceNameField.identifier = NSUserInterfaceItemIdentifier("dashboard-device-name")
        deviceNameField.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        deviceNameField.textColor = .labelColor
        deviceNameField.isSelectable = true
        deviceNameField.toolTip = data.modelIdentifier

        let osField = NSTextField(wrappingLabelWithString: data.operatingSystem)
        osField.identifier = NSUserInterfaceItemIdentifier("dashboard-operating-system")
        osField.font = NSFont.systemFont(ofSize: 12)
        osField.textColor = .secondaryLabelColor
        osField.toolTip = data.operatingSystemBuild
        osField.isSelectable = true

        for field in [deviceNameField, osField] {
            field.alignment = .left
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            text.addArrangedSubview(field)
            field.widthAnchor.constraint(equalTo: text.widthAnchor).isActive = true
        }
        container.addArrangedSubview(deviceImageView)
        container.addArrangedSubview(text)
        text.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -88).isActive = true
        return container
    }

    private final class InformationRow: NSView {
        let valueField: NSTextField

        init(key: String, title: String, value: String, labelWidth: CGFloat) {
            self.valueField = NSTextField(wrappingLabelWithString: value)
            super.init(frame: .zero)
            self.translatesAutoresizingMaskIntoConstraints = false
            self.identifier = NSUserInterfaceItemIdentifier("dashboard-row-\(key)")

            let label = NSTextField(labelWithString: title)
            label.identifier = NSUserInterfaceItemIdentifier("dashboard-label-\(key)")
            label.font = NSFont.systemFont(ofSize: 13)
            label.textColor = .secondaryLabelColor
            label.maximumNumberOfLines = 1
            label.cell?.wraps = false
            label.cell?.usesSingleLineMode = true
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.required, for: .horizontal)

            self.valueField.identifier = NSUserInterfaceItemIdentifier("dashboard-value-\(key)")
            self.valueField.font = NSFont.systemFont(ofSize: 13)
            self.valueField.alignment = .left
            self.valueField.textColor = .labelColor
            self.valueField.isSelectable = true
            self.valueField.maximumNumberOfLines = 0
            self.valueField.lineBreakMode = .byWordWrapping
            self.valueField.setContentHuggingPriority(.defaultLow, for: .horizontal)
            self.valueField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            self.valueField.setContentCompressionResistancePriority(.required, for: .vertical)
            self.valueField.setAccessibilityLabel(title)

            for field in [label, self.valueField] {
                field.translatesAutoresizingMaskIntoConstraints = false
                self.addSubview(field)
            }
            NSLayoutConstraint.activate([
                self.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
                label.leadingAnchor.constraint(equalTo: self.leadingAnchor),
                label.widthAnchor.constraint(equalToConstant: labelWidth),
                label.firstBaselineAnchor.constraint(equalTo: self.valueField.firstBaselineAnchor),
                self.valueField.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 16),
                self.valueField.trailingAnchor.constraint(equalTo: self.trailingAnchor),
                self.valueField.topAnchor.constraint(equalTo: self.topAnchor, constant: 8),
                self.valueField.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -8)
            ])
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
    
    @objc private func windowOpens(_ notification: Notification) {
        guard let moduleName = notification.userInfo?["module"] as? String, moduleName == "Dashboard" || moduleName == "Combined modules" else { return }
        if let refreshUptime { self.uptimeField?.stringValue = refreshUptime() }
    }
}
