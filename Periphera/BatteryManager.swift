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

    // MARK: - Hardware Charge Inhibit State (Physical SMC Control)
    var isHardwareHelperInstalled: Bool = false
    var isHardwareChargingBlocked: Bool = false
    var smcSupportsTahoe: Bool = false
    var smcSupportsLegacy: Bool = false

    // MARK: - AlDente Protection Settings (Persisted in UserDefaults)
    var isProtectionEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isProtectionEnabled, forKey: "batteryProtectionEnabled")
            applyHardwareChargingState()
        }
    }

    var chargeLimit: Int {
        didSet {
            let clamped = Swift.min(Swift.max(chargeLimit, 60), 100)
            if clamped != chargeLimit { chargeLimit = clamped }
            UserDefaults.standard.set(chargeLimit, forKey: "batteryChargeLimit")
            applyHardwareChargingState()
        }
    }

    var isSailingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isSailingEnabled, forKey: "batterySailingEnabled")
            applyHardwareChargingState()
        }
    }

    var sailingDiff: Int {
        didSet {
            UserDefaults.standard.set(sailingDiff, forKey: "batterySailingDiff")
            applyHardwareChargingState()
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
    var isTopUpActive: Bool = false {
        didSet {
            applyHardwareChargingState()
        }
    }

    // State tracking for notifications to avoid spamming
    private var hasNotifiedForCurrentLimit: Bool = false
    private var hasNotifiedForOverheat: Bool = false
    private var loopSource: CFRunLoopSource?
    private var timer: Timer?

    private init() {
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
        self.sailingDiff = Swift.max(defaults.integer(forKey: "batterySailingDiff"), 2)
        self.isHeatProtectionEnabled = defaults.bool(forKey: "batteryHeatProtectionEnabled")
        self.maxTempThreshold = defaults.double(forKey: "batteryMaxTempThreshold")
        self.notifyOnLimit = defaults.bool(forKey: "batteryNotifyOnLimit")
        self.soundAlert = defaults.bool(forKey: "batterySoundAlert")

        detectSMCKeys()
        checkHardwareControlInstalled()
        refreshTelemetry()
        applyHardwareChargingState()
        startMonitoring()
        requestNotificationPermission()
    }

    // MARK: - Monitoring Lifecycle
    func startMonitoring() {
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

    // MARK: - SMC Key Support & Hardware Helper Check
    func detectSMCKeys() {
        if let out = readSMCKey("CHTE"), !out.contains("no data") && !out.contains("Error") {
            smcSupportsTahoe = true
        } else if let out = readSMCKey("CH0B"), !out.contains("no data") && !out.contains("Error") {
            smcSupportsLegacy = true
        }
    }

    func checkHardwareControlInstalled() {
        let helperPath = "/usr/local/bin/periphera-smc"
        guard FileManager.default.fileExists(atPath: helperPath) else {
            isHardwareHelperInstalled = false
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", helperPath, "-v"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            isHardwareHelperInstalled = (process.terminationStatus == 0)
        } catch {
            isHardwareHelperInstalled = false
        }

        detectSMCKeys()
        queryHardwareChargingBlockedStatus()
    }

    private func queryHardwareChargingBlockedStatus() {
        if smcSupportsTahoe {
            if let out = readSMCKey("CHTE") {
                isHardwareChargingBlocked = out.contains("01 00 00 00") || out.contains(" 1 (") || out.contains("16777216")
            }
        } else if smcSupportsLegacy {
            if let out = readSMCKey("CH0B") {
                isHardwareChargingBlocked = out.contains("02") || out.contains(" 2 (")
            }
        }
    }

    private func getUsableSMCPath() -> String? {
        let installed = "/usr/local/bin/periphera-smc"
        if FileManager.default.fileExists(atPath: installed) {
            return installed
        }
        return Bundle.main.path(forResource: "smc", ofType: nil)
    }

    private func readSMCKey(_ key: String) -> String? {
        guard let path = getUsableSMCPath() else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-k", key, "-r"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    // MARK: - Privileged Hardware Helper Installation
    @discardableResult
    func installHardwareHelper() -> Bool {
        guard let bundledSMC = Bundle.main.path(forResource: "smc", ofType: nil) else {
            return false
        }
        let helperPath = "/usr/local/bin/periphera-smc"
        let sudoersPath = "/private/etc/sudoers.d/periphera"

        let cmd = "mkdir -p /usr/local/bin && cp '\(bundledSMC)' '\(helperPath)' && chmod 4755 '\(helperPath)' && chown root:wheel '\(helperPath)' && echo 'ALL ALL = NOPASSWD: \(helperPath)' > '\(sudoersPath)' && chmod 440 '\(sudoersPath)'"

        let appleScript = NSAppleScript(source: "do shell script \"\(cmd)\" with administrator privileges")
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)

        checkHardwareControlInstalled()
        applyHardwareChargingState()
        refreshTelemetry()
        return isHardwareHelperInstalled
    }

    @discardableResult
    func uninstallHardwareHelper() -> Bool {
        enableHardwareCharging()
        let helperPath = "/usr/local/bin/periphera-smc"
        let sudoersPath = "/private/etc/sudoers.d/periphera"
        let cmd = "rm -f '\(helperPath)' '\(sudoersPath)'"
        let appleScript = NSAppleScript(source: "do shell script \"\(cmd)\" with administrator privileges")
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)
        checkHardwareControlInstalled()
        return !isHardwareHelperInstalled
    }

    // MARK: - Hardware Charging Execution (SMC Write)
    private func runPrivilegedSMC(_ args: [String]) {
        let helperPath = "/usr/local/bin/periphera-smc"
        guard FileManager.default.fileExists(atPath: helperPath) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        var fullArgs = ["-n", helperPath]
        fullArgs.append(contentsOf: args)
        process.arguments = fullArgs
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try? process.run()
        process.waitUntilExit()
    }

    func disableHardwareCharging() {
        guard isHardwareHelperInstalled else { return }
        if smcSupportsTahoe {
            runPrivilegedSMC(["-k", "CHTE", "-w", "01000000"])
            if level > chargeLimit && isSailingEnabled {
                runPrivilegedSMC(["-k", "CHIE", "-w", "08"])
            }
        } else if smcSupportsLegacy {
            runPrivilegedSMC(["-k", "CH0B", "-w", "02"])
            runPrivilegedSMC(["-k", "CH0C", "-w", "02"])
        }
        isHardwareChargingBlocked = true
    }

    func enableHardwareCharging() {
        guard isHardwareHelperInstalled else { return }
        if smcSupportsTahoe {
            runPrivilegedSMC(["-k", "CHIE", "-w", "00"])
            runPrivilegedSMC(["-k", "CHTE", "-w", "00000000"])
        } else if smcSupportsLegacy {
            runPrivilegedSMC(["-k", "CH0B", "-w", "00"])
            runPrivilegedSMC(["-k", "CH0C", "-w", "00"])
        }
        isHardwareChargingBlocked = false
    }

    // MARK: - Hardware Charging State Evaluator
    func applyHardwareChargingState() {
        guard hasBattery && isHardwareHelperInstalled else { return }

        let shouldBlock: Bool
        if !isProtectionEnabled || isTopUpActive {
            shouldBlock = false
        } else if isACConnected {
            if level >= chargeLimit {
                shouldBlock = true
            } else if isSailingEnabled {
                if isHardwareChargingBlocked {
                    let resumeThreshold = Swift.max(chargeLimit - sailingDiff, 20)
                    shouldBlock = (level > resumeThreshold)
                } else {
                    shouldBlock = false
                }
            } else {
                shouldBlock = false
            }
        } else {
            shouldBlock = false
        }

        if shouldBlock != isHardwareChargingBlocked {
            if shouldBlock {
                disableHardwareCharging()
            } else {
                enableHardwareCharging()
            }
        }
    }

    // MARK: - Telemetry Refresh via IOKit & AppleSmartBattery
    func refreshTelemetry() {
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
                        self.healthPercentage = Swift.min(Swift.max((self.rawMaxCapacity * 100) / design, 1), 100)
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

        evaluateProtectionState()
        applyHardwareChargingState()
        queryHardwareChargingBlockedStatus()
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
        } else if isHardwareHelperInstalled {
            content.body = "La batteria ha raggiunto il \(limit)%. Ricarica hardware interrotta fisicamente per preservare le celle."
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
        applyHardwareChargingState()
        refreshTelemetry()
    }

    func setLimit(_ newLimit: Int) {
        chargeLimit = newLimit
        hasNotifiedForCurrentLimit = false
        applyHardwareChargingState()
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
            if isHardwareChargingBlocked {
                return isIT ? "Ricarica interrotta (Hardware) • Limite \(chargeLimit)%" : "Charging halted (Hardware) • Limit \(chargeLimit)%"
            }
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
        if isHardwareChargingBlocked {
            return "pause.fill"
        }
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
        if isHardwareChargingBlocked || (isProtectionEnabled && isACConnected && level >= chargeLimit) {
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
