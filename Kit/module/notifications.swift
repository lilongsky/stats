//
//  notifications.swift
//  Kit
//
//  Created by Serhiy Mytrovtsiy on 04/12/2023
//  Using Swift 5.0
//  Running on macOS 14.1
//
//  Copyright © 2023 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import UserNotifications

open class NotificationsWrapper: NSStackView {
    public let module: String
    
    private var ids: [String: Bool?] = [:]
    private var conditions: [String: SustainedCondition] = [:]
    private let conditionLock = NSLock()
    
    public init(_ module: ModuleType, _ ids: [String] = []) {
        self.module = module.stringValue
        super.init(frame: NSRect.zero)
        self.initIDs(ids)
        
        self.orientation = .vertical
        self.distribution = .gravityAreas
        self.translatesAutoresizingMaskIntoConstraints = false
        self.spacing = Constants.Settings.margin
        self.addArrangedSubview(self.durationSettings())
    }
    

    public func durationSettings() -> NSView {
        return PreferencesSection(title: "提醒规则", subtitle: "阈值连续满足指定时长后提醒，适用于本页的阈值规则。", [
            PreferencesRow("持续时间", component: StepperInput(
                Store.shared.int(key: "\(self.module)_notifications_durationSeconds", defaultValue: 2),
                range: NSRange(location: 0, length: 3600), unit: "秒"
            ) { [weak self] seconds in
                guard let self else { return }
                Store.shared.set(key: "\(self.module)_notifications_durationSeconds", value: seconds)
            })
        ])
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func willTerminate() {
        for id in self.ids {
            removeNotification(id.key)
        }
    }
    
    public func initIDs(_ ids: [String]) {
        for id in ids {
            let notificationID = "Stats_\(self.module)_\(id)"
            self.ids[notificationID] = nil
            self.conditions[notificationID] = SustainedCondition()
            removeNotification(notificationID)
        }
    }
    
    public func checkDouble(id rid: String, value: Double, threshold: Double, title: String, subtitle: String, less: Bool = false, consecutive: Int = 2) {
        let id = "Stats_\(self.module)_\(rid)"
        let satisfied = value.isFinite && threshold.isFinite && (less ? value <= threshold : value >= threshold)
        let duration = TimeInterval(Store.shared.int(key: "\(self.module)_notifications_durationSeconds", defaultValue: 2))
        let interval = TimeInterval(Store.shared.int(key: "\(self.module)_updateInterval", defaultValue: 1))
        self.conditionLock.lock()
        var condition = self.conditions[id] ?? SustainedCondition()
        let shouldNotify = condition.evaluate(satisfied, now: ProcessInfo.processInfo.systemUptime,
                                              duration: duration, maximumGap: max(10, interval * 2.5),
                                              signature: "\(less)-\(threshold)")
        self.conditions[id] = condition
        let shouldRemove = !satisfied && self.ids[id] == true
        if !satisfied { self.ids[id] = nil }
        if shouldNotify { self.ids[id] = true }
        self.conditionLock.unlock()
        if shouldRemove { removeNotification(id) }
        if shouldNotify { self.showNotification(id: id, title: title, subtitle: subtitle) }
    }

    public func newNotification(id rid: String, title: String, subtitle: String? = nil) {
        let id = "Stats_\(self.module)_\(rid)"
        
        if self.ids[id] != nil {
            removeNotification(id)
            self.ids[id] = nil
        }
        
        self.showNotification(id: id, title: title, subtitle: subtitle)
        self.ids[id] = true
    }
    
    public func hideNotification(_ rid: String) {
        let id = "Stats_\(self.module)_\(rid)"
        self.conditionLock.lock()
        self.conditions.removeValue(forKey: id)
        let active = self.ids[id] != nil
        self.ids[id] = nil
        self.conditionLock.unlock()
        if active { removeNotification(id) }
    }

    private func showNotification(id: String, title: String, subtitle: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        if let value = subtitle {
            content.subtitle = value
        }
        content.sound = UNNotificationSound.default
        
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        let center = UNUserNotificationCenter.current()
        
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        center.add(request) { (error: Error?) in
            if let err = error {
                print(err)
            }
        }
    }
}
