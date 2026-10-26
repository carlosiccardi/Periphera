//
//  BatteryManager.swift
//  Periphera
//
//  Created by Carlo Siccardi on 26/10/2026.
//

import Foundation
import SwiftUI
import IOKit
import IOKit.ps
import UserNotifications
import Observation

@Observable
@MainActor
final class BatteryManager {
    static let shared = BatteryManager()

    // MARK: - Hardware Telemetry
    var hasBattery: Bool = false
    var level: Int = 100
    var isCharging: Bool = false
    var isACConnected: Bool = false
    var healthPercentage: Int = 100
    var cycleCount: Int = 0
    var maxDesignCycles: Int = 1000
    var temperatureCelsius: Double = 25.0
    var voltageMilliVolts: Int = 0
    var amperageMilliAmps: Int = 0
    var wattage: Double = 0.0
    var timeRemainingMinutes: Int? = nil
    var rawMaxCapacity: Int = 0
    var designCapacity: Int = 0
    var deviceName: String = ""
    var serialNumber: String = ""

    // MARK: - AlDente Protection Settings (Persisted in UserDefaults)
    var isProtectionEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isProtectionEnabled, forKey: "batteryProtectionEnabled")
        }
    }

    var chargeLimit: Int {
        didSet {
            let clamped = min(max(chargeLimit, 60), 100)
            if clamped != chargeLimit { chargeLimit = clamped }
            UserDefaults.standard.set(chargeLimit, forKey: "batteryChargeLimit")
        }
    }

    var isSailingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isSailingEnabled, forKey: "batterySailingEnabled")
        }
    }

    var sailingDiff: Int {
        didSet {
            UserDefaults.standard.set(sailingDiff, forKey: "batterySailingDiff")
        }
    }

    var isHeatProtectionEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isHeatProtectionEnabled, forKey: "batteryHeatProtectionEnabled")
        }
    }

    var maxTempThreshold: Double {
        didSet {
            UserDefaults.standard.set(maxTempThreshold, forKey: "batteryMaxTempThreshold")
        }
    }

    var notifyOnLimit: Bool {
        didSet {
            UserDefaults.standard.set(notifyOnLimit, forKey: "batteryNotifyOnLimit")
        }
    }

    var soundAlert: Bool {
        didSet {
            UserDefaults.standard.set(soundAlert, forKey: "batterySoundAlert")
        }
    }

    // Temporary 1-click Top Up (charges to 100% when traveling)
    var isTopUpActive: Bool = false

    // State tracking for notifications to avoid spamming
    private var hasNotifiedForCurrentLimit: Bool = false
    private var hasNotifiedForOverheat: Bool = false
    private var loopSource: CFRunLoopSource?
    private var timer: Timer?

    private init() {
        // Load defaults or registered settings
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "batteryProtectionEnabled") == nil {
            defaults.set(true, forKey: "batteryProtectionEnabled")
        }
        if defaults.object(forKey: "batteryChargeLimit") == nil {
            defaults.set(80, forKey: "batteryChargeLimit")
        }
        if defaults.object(forKey: "batterySailingEnabled") == nil {
            defaults.set(false, forKey: "batterySailingEnabled")
        }
        if defaults.object(forKey: "batterySailingDiff") == nil {
            defaults.set(5, forKey: "batterySailingDiff")
        }
        if defaults.object(forKey: "batteryHeatProtectionEnabled") == nil {
            defaults.set(true, forKey: "batteryHeatProtectionEnabled")
        }
        if defaults.object(forKey: "batteryMaxTempThreshold") == nil {
            defaults.set(36.0, forKey: "batteryMaxTempThreshold")
        }
        if defaults.object(forKey: "batteryNotifyOnLimit") == nil {
            defaults.set(true, forKey: "batteryNotifyOnLimit")
        }
        if defaults.object(forKey: "batterySoundAlert") == nil {
            defaults.set(true, forKey: "batterySoundAlert")
        }

        self.isProtectionEnabled = defaults.bool(forKey: "batteryProtectionEnabled")
        self.chargeLimit = defaults.integer(forKey: "batteryChargeLimit")
        self.isSailingEnabled = defaults.bool(forKey: "batterySailingEnabled")
        self.sailingDiff = max(defaults.integer(forKey: "batterySailingDiff"), 2)
        self.isHeatProtectionEnabled = defaults.bool(forKey: "batteryHeatProtectionEnabled")
        self.maxTempThreshold = defaults.double(forKey: "batteryMaxTempThreshold")
        self.notifyOnLimit = defaults.bool(forKey: "batteryNotifyOnLimit")
        self.soundAlert = defaults.bool(forKey: "batterySoundAlert")

        refreshTelemetry()
        startMonitoring()
        requestNotificationPermission()
    }

    // MARK: - Monitoring Lifecycle
    func startMonitoring() {
        // 1. Hardware IOPS run loop observer
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        if let runLoopSource = IOPSNotificationCreateRunLoopSource({ info in
            guard let info = info else { return }
            let manager = Unmanaged<BatteryManager>.fromOpaque(info).takeUnretainedValue()
            Task { @MainActor in
                manager.refreshTelemetry()
            }
        }, context)?.takeRetainedValue() {
            self.loopSource = runLoopSource
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        // 2. Periodic polling timer for temperature, wattage, and smooth UI updates
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshTelemetry()
            }
        }
    }

    func stopMonitoring() {
        if let source = loopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            loopSource = nil
        }
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Telemetry Refresh via IOKit & AppleSmartBattery
    func refreshTelemetry() {
        // 1. Basic power source information
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            hasBattery = false
            return
        }

        var foundBattery = false
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }

            if let type = desc[kIOPSTypeKey as String] as? String, type == (kIOPSInternalBatteryType as String) {
                foundBattery = true
                if let cur = desc[kIOPSCurrentCapacityKey as String] as? Int,
                   let maxCap = desc[kIOPSMaxCapacityKey as String] as? Int, maxCap > 0 {
                    self.level = Swift.min(Swift.max((cur * 100) / maxCap, 0), 100)
                }

                self.isCharging = (desc[kIOPSIsChargingKey as String] as? Bool) ?? false
                let powerSourceState = desc[kIOPSPowerSourceStateKey as String] as? String
                self.isACConnected = (powerSourceState == (kIOPSACPowerValue as String))

                if let time = desc[kIOPSTimeToEmptyKey as String] as? Int, time > 0, time < 65535 {
                    self.timeRemainingMinutes = time
                } else if let time = desc[kIOPSTimeToFullChargeKey as String] as? Int, time > 0, time < 65535 {
                    self.timeRemainingMinutes = time
                } else {
                    self.timeRemainingMinutes = nil
                }
                break
            }
        }
        self.hasBattery = foundBattery

        // 2. Detailed AppleSmartBattery properties
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any] {

                if let rawMax = dict["AppleRawMaxCapacity"] as? Int {
                    self.rawMaxCapacity = rawMax
                }
                if let design = dict["DesignCapacity"] as? Int, design > 0 {
                    self.designCapacity = design
                    if self.rawMaxCapacity > 0 {
                        self.healthPercentage = min(max((self.rawMaxCapacity * 100) / design, 1), 100)
                    }
                }
                if let cycles = dict["CycleCount"] as? Int {
                    self.cycleCount = cycles
                }
                if let designCycles = dict["DesignCycleCount9C"] as? Int {
                    self.maxDesignCycles = designCycles
                }
                if let temp = dict["Temperature"] as? Int {
                    self.temperatureCelsius = Double(temp) / 100.0
                }
                if let volt = dict["Voltage"] as? Int {
                    self.voltageMilliVolts = volt
                }
                if let rawAmp = dict["Amperage"] as? Int64 {
                    // Sign-extend 32/64-bit amperage
                    let amp = Int(rawAmp)
                    self.amperageMilliAmps = amp
                    let powerW = (Double(self.voltageMilliVolts) * Double(abs(amp))) / 1_000_000.0
                    self.wattage = (powerW * 10).rounded() / 10.0
                }
                if let devName = dict["DeviceName"] as? String {
                    self.deviceName = devName
                }
                if let serial = dict["Serial"] as? String {
                    self.serialNumber = serial
                }
            }
            IOObjectRelease(service)
        }

        // 3. Process protection logic and alerts
        evaluateProtectionState()
    }

    // MARK: - Protection Logic & Smart Alerts
    private func evaluateProtectionState() {
        guard isProtectionEnabled && hasBattery else {
            hasNotifiedForCurrentLimit = false
            hasNotifiedForOverheat = false
            return
        }

        let effectiveLimit = isTopUpActive ? 100 : chargeLimit

        // 1. Charge Limit Reached Check
        if isACConnected && level >= effectiveLimit {
            if !hasNotifiedForCurrentLimit {
                hasNotifiedForCurrentLimit = true
                dispatchLimitReachedAlert(limit: effectiveLimit)
            }
        } else if level < effectiveLimit - 2 {
            // Reset trigger when level drops noticeably below threshold
            hasNotifiedForCurrentLimit = false
        }

        // 2. Overheat Alert Check
        if isHeatProtectionEnabled && temperatureCelsius >= maxTempThreshold {
            if !hasNotifiedForOverheat {
                hasNotifiedForOverheat = true
                dispatchOverheatAlert(temp: temperatureCelsius)
            }
        } else if temperatureCelsius < maxTempThreshold - 1.5 {
            hasNotifiedForOverheat = false
        }
    }

    // MARK: - Notifications
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func dispatchLimitReachedAlert(limit: Int) {
        guard notifyOnLimit else { return }

        if soundAlert {
            NSSound(named: "Glass")?.play()
        }

        let content = UNMutableNotificationContent()
        content.title = "Periphera • Limite di Carica Raggiunto"
        if isTopUpActive {
            content.body = "Ricarica al 100% completata. Top Up terminato."
        } else {
            content.body = "La batteria ha raggiunto il \(limit)%. Modalità salvaguardia attiva per prevenire il deterioramento cellulare."
        }
        if soundAlert {
            content.sound = .default
        }

        let req = UNNotificationRequest(
            identifier: "PeripheraBatteryLimitAlert",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }

    private func dispatchOverheatAlert(temp: Double) {
        if soundAlert {
            NSSound(named: "Basso")?.play()
        }

        let content = UNMutableNotificationContent()
        content.title = "Periphera • Avviso Temperatura Batteria"
        content.body = String(format: "La batteria ha raggiunto %.1f°C. Scollega il caricatore o riduci carichi intensi per preservare le celle.", temp)
        content.sound = .default

        let req = UNNotificationRequest(
            identifier: "PeripheraBatteryOverheatAlert",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: - Public Actions
    func toggleTopUp() {
        isTopUpActive.toggle()
        if isTopUpActive {
            hasNotifiedForCurrentLimit = false
        }
        refreshTelemetry()
    }

    func setLimit(_ newLimit: Int) {
        chargeLimit = newLimit
        hasNotifiedForCurrentLimit = false
        refreshTelemetry()
    }

    // MARK: - Presentation Helpers
    func statusDescription(isIT: Bool) -> String {
        guard hasBattery else {
            return isIT ? "Alimentazione da rete fissa" : "Desktop power source"
        }

        if isTopUpActive {
            return isIT ? "Top Up attivo (ricarica a 100%)" : "Top Up active (charging to 100%)"
        }

        if isProtectionEnabled && isACConnected {
            if level >= chargeLimit {
                return isIT ? "Limite \(chargeLimit)% raggiunto • Batteria protetta" : "Limit \(chargeLimit)% reached • Battery protected"
            }
            if isSailingEnabled && level >= (chargeLimit - sailingDiff) && level <= chargeLimit {
                return isIT ? "In veleggiamento (\(chargeLimit - sailingDiff)% - \(chargeLimit)%)" : "Sailing mode (\(chargeLimit - sailingDiff)% - \(chargeLimit)%)"
            }
            if isCharging {
                return isIT ? "In carica verso \(chargeLimit)%" : "Charging to \(chargeLimit)%"
            }
            return isIT ? "Alimentatore connesso" : "Power adapter connected"
        }

        if isCharging {
            return isIT ? "In carica (\(level)%)" : "Charging (\(level)%)"
        }

        if isACConnected {
            return isIT ? "Alimentatore connesso" : "Connected to power"
        }

        if let minutes = timeRemainingMinutes {
            let h = minutes / 60
            let m = minutes % 60
            let timeStr = h > 0 ? "\(h)h \(m)m" : "\(m)m"
            return isIT ? "\(timeStr) rimanenti" : "\(timeStr) remaining"
        }

        return isIT ? "In uso su batteria" : "On battery power"
    }

    var batteryIconName: String {
        if isCharging || (isACConnected && level < chargeLimit) {
            return "bolt.batteryblock.fill"
        }
        if level >= 90 { return "battery.100" }
        if level >= 70 { return "battery.75" }
        if level >= 45 { return "battery.50" }
        if level >= 20 { return "battery.25" }
        return "battery.0"
    }

    var statusColor: Color {
        if isHeatProtectionEnabled && temperatureCelsius >= maxTempThreshold {
            return .red
        }
        if isTopUpActive {
            return .blue
        }
        if isProtectionEnabled && isACConnected && level >= chargeLimit {
            return Color(red: 0.25, green: 0.78, blue: 0.48)
        }
        if isCharging {
            return .orange
        }
        return .secondary
    }

    func healthCondition(isIT: Bool) -> String {
        if healthPercentage >= 85 {
            return isIT ? "Ottimo" : "Excellent"
        } else if healthPercentage >= 80 {
            return isIT ? "Buono" : "Normal"
        } else {
            return isIT ? "Assistenza" : "Service"
        }
    }
}
