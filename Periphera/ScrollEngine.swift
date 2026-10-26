//
//  ScrollEngine.swift
//  Periphera
//
//  Created by Carlo Siccardi on 19/10/2026.
//

import Foundation
import CoreGraphics
import ApplicationServices
import AppKit
import ServiceManagement
import Observation

enum AppLanguage: String, CaseIterable, Sendable {
    case it = "IT"
    case en = "EN"

    static var systemDefault: AppLanguage {
        let code = Locale.preferredLanguages.first ?? "en"
        return code.lowercased().hasPrefix("it") ? .it : .en
    }
}

enum InputDeviceType: String, Sendable {
    case trackpad = "Trackpad"
    case mouse = "Mouse"
}

/// Lock-free / fast configuration snapshot read by the real-time CGEventTap callback.
struct ScrollTapConfig: Sendable {
    var isEnabled: Bool
    var trackpadNatural: Bool
    var mouseNatural: Bool
    var invertMouseHorizontal: Bool
    var mouseSpeedMultiplier: Double
    var systemIsNatural: Bool
}

/// Thread-safe box shared between the MainActor ScrollEngine and the C CGEventTap callback.
nonisolated final class TapSharedContext: @unchecked Sendable {
    private var lock = os_unfair_lock_s()
    private var _config: ScrollTapConfig
    fileprivate var machPort: CFMachPort?
    private var lastReportedDevice: InputDeviceType?
    private var lastReportTime: CFAbsoluteTime = 0
    var onDeviceActivity: (@Sendable (InputDeviceType, Bool) -> Void)?

    init(config: ScrollTapConfig) {
        self._config = config
    }

    func updateConfig(_ newConfig: ScrollTapConfig) {
        os_unfair_lock_lock(&lock)
        _config = newConfig
        os_unfair_lock_unlock(&lock)
    }

    func currentConfig() -> ScrollTapConfig {
        os_unfair_lock_lock(&lock)
        let copy = _config
        os_unfair_lock_unlock(&lock)
        return copy
    }

    func notifyActivity(device: InputDeviceType, didInvert: Bool) {
        let now = CFAbsoluteTimeGetCurrent()
        os_unfair_lock_lock(&lock)
        let shouldNotify = (lastReportedDevice != device) || (now - lastReportTime > 0.25)
        if shouldNotify {
            lastReportedDevice = device
            lastReportTime = now
        }
        os_unfair_lock_unlock(&lock)

        if shouldNotify {
            onDeviceActivity?(device, didInvert)
        }
    }
}

private nonisolated func scrollEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let context = Unmanaged<TapSharedContext>.fromOpaque(userInfo).takeUnretainedValue()

    // Re-enable tap automatically if macOS temporarily disables it due to timeout or user input
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let port = context.machPort {
            CGEvent.tapEnable(tap: port, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    guard type == .scrollWheel else {
        return Unmanaged.passUnretained(event)
    }

    let config = context.currentConfig()
    guard config.isEnabled else {
        return Unmanaged.passUnretained(event)
    }

    // Distinguish Trackpad (continuous gesture / scroll phase / momentum phase) vs physical Mouse wheel
    let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
    let scrollPhase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
    let momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)

    let isTrackpad = isContinuous || scrollPhase != 0 || momentumPhase != 0
    let device: InputDeviceType = isTrackpad ? .trackpad : .mouse

    // Determine whether this device's desired direction differs from the macOS system-wide direction.
    // macOS has already applied `systemIsNatural` to the incoming event deltas.
    // Therefore, if `desiredNatural != systemIsNatural`, we invert the event deltas!
    let desiredNatural = isTrackpad ? config.trackpadNatural : config.mouseNatural
    let shouldInvert = (desiredNatural != config.systemIsNatural)
    let speedMultiplier = isTrackpad ? 1.0 : config.mouseSpeedMultiplier

    if shouldInvert || abs(speedMultiplier - 1.0) > 0.01 {
        let sign: Int64 = shouldInvert ? -1 : 1
        let signDouble: Double = shouldInvert ? -1.0 : 1.0

        // Read all vertical (Axis 1) deltas before mutating (setting DeltaAxis1 resets Point/Fixed deltas)
        let deltaY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let pointDeltaY = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let fixedDeltaY = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)

        let scaledDeltaY = Int64((Double(deltaY * sign) * speedMultiplier).rounded())
        let scaledPointY = Int64((Double(pointDeltaY * sign) * speedMultiplier).rounded())
        let scaledFixedY = (fixedDeltaY * signDouble) * speedMultiplier

        // When deltaY is non-zero, ensure scaledDeltaY doesn't round to 0
        let finalDeltaY: Int64
        if deltaY != 0 && scaledDeltaY == 0 {
            finalDeltaY = deltaY * sign
        } else {
            finalDeltaY = scaledDeltaY
        }

        // Order matters in CoreGraphics: set DeltaAxis1 first, then FixedPt, then PointDelta
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: finalDeltaY)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: scaledFixedY)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: scaledPointY)

        // Optionally invert horizontal axis (Axis 2)
        if shouldInvert && (isTrackpad || config.invertMouseHorizontal) {
            let deltaX = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            let pointDeltaX = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
            let fixedDeltaX = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)

            event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -deltaX)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -fixedDeltaX)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -pointDeltaX)
        }
    }

    context.notifyActivity(device: device, didInvert: shouldInvert)
    return Unmanaged.passUnretained(event)
}

@Observable
@MainActor
final class ScrollEngine {
    // MARK: - Persisted Settings
    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.isEnabled)
            syncSharedConfig()
        }
    }

    /// True = Natural scrolling (content moves with fingers), False = Classic/Standard scrolling
    var trackpadNatural: Bool {
        didSet {
            UserDefaults.standard.set(trackpadNatural, forKey: Keys.trackpadNatural)
            syncSharedConfig()
        }
    }

    /// True = Natural scrolling, False = Classic/Standard wheel scrolling (wheel down -> page down)
    var mouseNatural: Bool {
        didSet {
            UserDefaults.standard.set(mouseNatural, forKey: Keys.mouseNatural)
            syncSharedConfig()
        }
    }

    var invertMouseHorizontal: Bool {
        didSet {
            UserDefaults.standard.set(invertMouseHorizontal, forKey: Keys.invertMouseHorizontal)
            syncSharedConfig()
        }
    }

    var mouseSpeedMultiplier: Double {
        didSet {
            UserDefaults.standard.set(mouseSpeedMultiplier, forKey: Keys.mouseSpeedMultiplier)
            syncSharedConfig()
        }
    }

    var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Keys.language)
        }
    }

    // MARK: - Live Runtime State
    private(set) var isAccessibilityGranted: Bool = false

    func setAccessibilityGrantedForPreview(_ granted: Bool) {
        isAccessibilityGranted = granted
    }
    private(set) var isTapActive: Bool = false
    private(set) var systemIsNatural: Bool = true
    private(set) var lastActiveDevice: InputDeviceType? = nil
    private(set) var lastDeviceInverted: Bool = false
    private(set) var activityPulse: Bool = false
    private(set) var launchAtLogin: Bool = false

    private let sharedContext: TapSharedContext
    private var runLoopSource: CFRunLoopSource?
    private var permissionTimer: Timer?
    private var pulseResetTask: Task<Void, Never>?

    private enum Keys {
        static let isEnabled = "periphera.isEnabled"
        static let trackpadNatural = "periphera.trackpadNatural"
        static let mouseNatural = "periphera.mouseNatural"
        static let invertMouseHorizontal = "periphera.invertMouseHorizontal"
        static let mouseSpeedMultiplier = "periphera.mouseSpeedMultiplier"
        static let language = "periphera.language"
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Keys.isEnabled: true,
            Keys.trackpadNatural: true,   // Trackpad: Naturale di default
            Keys.mouseNatural: false,     // Mouse: Standard (Non-naturale) di default
            Keys.invertMouseHorizontal: false,
            Keys.mouseSpeedMultiplier: 1.0
        ])

        let enabled = defaults.bool(forKey: Keys.isEnabled)
        let tpNatural = defaults.bool(forKey: Keys.trackpadNatural)
        let msNatural = defaults.bool(forKey: Keys.mouseNatural)
        let invHoriz = defaults.bool(forKey: Keys.invertMouseHorizontal)
        let speed = defaults.double(forKey: Keys.mouseSpeedMultiplier)
        let sysNatural = Self.readSystemNaturalScrolling()

        if let savedLang = defaults.string(forKey: Keys.language),
           let parsedLang = AppLanguage(rawValue: savedLang) {
            self.language = parsedLang
        } else {
            self.language = AppLanguage.systemDefault
        }

        self.isEnabled = enabled
        self.trackpadNatural = tpNatural
        self.mouseNatural = msNatural
        self.invertMouseHorizontal = invHoriz
        self.mouseSpeedMultiplier = speed == 0 ? 1.0 : speed
        self.systemIsNatural = sysNatural

        let initialConfig = ScrollTapConfig(
            isEnabled: enabled,
            trackpadNatural: tpNatural,
            mouseNatural: msNatural,
            invertMouseHorizontal: invHoriz,
            mouseSpeedMultiplier: speed == 0 ? 1.0 : speed,
            systemIsNatural: sysNatural
        )
        self.sharedContext = TapSharedContext(config: initialConfig)

        self.launchAtLogin = (SMAppService.mainApp.status == .enabled)

        setupCallbacksAndObservers()
        checkAccessibilityAndStart(promptIfNeeded: false)
        startMonitoringPermissionsAndSystemPrefs()
    }

    // MARK: - System Scroll Preference Detection
    private static func readSystemNaturalScrolling() -> Bool {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        if let val = CFPreferencesCopyAppValue(
            "com.apple.swipescrolldirection" as CFString,
            kCFPreferencesAnyApplication
        ) as? Bool {
            return val
        }
        return true
    }

    private func refreshSystemScrollDirection() {
        let latest = Self.readSystemNaturalScrolling()
        if latest != systemIsNatural {
            systemIsNatural = latest
            syncSharedConfig()
        }
    }

    private func syncSharedConfig() {
        sharedContext.updateConfig(
            ScrollTapConfig(
                isEnabled: isEnabled,
                trackpadNatural: trackpadNatural,
                mouseNatural: mouseNatural,
                invertMouseHorizontal: invertMouseHorizontal,
                mouseSpeedMultiplier: mouseSpeedMultiplier,
                systemIsNatural: systemIsNatural
            )
        )
    }

    // MARK: - Observers & Callbacks
    private func setupCallbacksAndObservers() {
        sharedContext.onDeviceActivity = { [weak self] device, didInvert in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lastActiveDevice = device
                self.lastDeviceInverted = didInvert
                self.activityPulse = true
                self.pulseResetTask?.cancel()
                self.pulseResetTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(900))
                    guard !Task.isCancelled else { return }
                    self?.activityPulse = false
                }
            }
        }

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("SwipeScrollDirectionDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshSystemScrollDirection()
            }
        }
    }

    private func startMonitoringPermissionsAndSystemPrefs() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshSystemScrollDirection()
                let trusted = AXIsProcessTrusted()
                if trusted != self.isAccessibilityGranted {
                    self.isAccessibilityGranted = trusted
                }
                if trusted && !self.isTapActive {
                    self.startEventTap()
                } else if !trusted && self.isTapActive {
                    self.stopEventTap()
                }
            }
        }
    }

    // MARK: - Accessibility & Event Tap Lifecycle
    func checkAccessibilityAndStart(promptIfNeeded: Bool) {
        let trusted: Bool
        if promptIfNeeded {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            trusted = AXIsProcessTrustedWithOptions(options)
        } else {
            trusted = AXIsProcessTrusted()
        }

        isAccessibilityGranted = trusted
        if trusted {
            startEventTap()
        } else {
            stopEventTap()
        }
    }

    func requestAccessibilityPermission() {
        checkAccessibilityAndStart(promptIfNeeded: true)
        if !isAccessibilityGranted {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func startEventTap() {
        guard !isTapActive else { return }

        let eventMask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        let userInfo = Unmanaged.passUnretained(sharedContext).toOpaque()

        // Try session event tap first, fallback to HID event tap
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: scrollEventTapCallback,
            userInfo: userInfo
        ) ?? CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: scrollEventTapCallback,
            userInfo: userInfo
        )

        guard let tap else {
            isTapActive = false
            return
        }

        sharedContext.machPort = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isTapActive = true
    }

    private func stopEventTap() {
        if let tap = sharedContext.machPort {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            sharedContext.machPort = nil
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        isTapActive = false
    }

    // MARK: - Launch at Login
    func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            // Ignore registration error in unsigned/dev builds, refresh status below
        }
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    // MARK: - Presets
    func applyRecommendedPreset() {
        trackpadNatural = true
        mouseNatural = false
        invertMouseHorizontal = false
        mouseSpeedMultiplier = 1.0
        isEnabled = true
    }
}
