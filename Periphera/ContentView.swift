//
//  ContentView.swift
//  Periphera
//
//  Created by Carlo Siccardi on 19/10/2026.
//

import SwiftUI

@MainActor
struct ContentView: View {
    @Bindable var engine: ScrollEngine
    @Bindable var displayManager: DisplayManager
    @Bindable var caffeineManager: CaffeineManager = .shared
    @Bindable var captureManager: ScreenCaptureManager = .shared
    @Bindable var batteryManager: BatteryManager = .shared

    @State private var showMouseSpeedTuning: Bool = false
    @State private var showTrackpadPreview: Bool = false
    @State private var showMousePreview: Bool = false
    @State private var showBatteryDetails: Bool = false

    @MainActor
    init(
        engine: ScrollEngine,
        displayManager: DisplayManager,
        caffeineManager: CaffeineManager = .shared,
        captureManager: ScreenCaptureManager = .shared,
        batteryManager: BatteryManager = .shared,
        showMouseSpeedTuning: Bool = false,
        showTrackpadPreview: Bool = false,
        showMousePreview: Bool = false,
        showBatteryDetails: Bool = false
    ) {
        self.engine = engine
        self.displayManager = displayManager
        self.caffeineManager = caffeineManager
        self.captureManager = captureManager
        self.batteryManager = batteryManager
        _showMouseSpeedTuning = State(initialValue: showMouseSpeedTuning)
        _showTrackpadPreview = State(initialValue: showTrackpadPreview)
        _showMousePreview = State(initialValue: showMousePreview)
        _showBatteryDetails = State(initialValue: showBatteryDetails)
    }

    private var isIT: Bool { engine.language == .it }

    var body: some View {
        VStack(spacing: 12) {
            headerBar

            if !engine.isAccessibilityGranted {
                permissionBanner
            }

            VStack(spacing: 8) {
                MinimalDeviceRow(
                    title: "Trackpad",
                    icon: "rectangle.and.hand.point.up.left",
                    deviceKind: .trackpad,
                    naturalLabel: isIT ? "Naturale" : "Natural",
                    classicLabel: isIT ? "Classico" : "Standard",
                    isIT: isIT,
                    isActiveNow: engine.lastActiveDevice == .trackpad && engine.activityPulse,
                    isNatural: $engine.trackpadNatural,
                    showInfoPreview: $showTrackpadPreview,
                    isEnabled: engine.isEnabled
                )

                MinimalDeviceRow(
                    title: "Mouse",
                    icon: "computermouse",
                    deviceKind: .mouse,
                    naturalLabel: isIT ? "Naturale" : "Natural",
                    classicLabel: isIT ? "Classico" : "Standard",
                    isIT: isIT,
                    isActiveNow: engine.lastActiveDevice == .mouse && engine.activityPulse,
                    isNatural: $engine.mouseNatural,
                    showInfoPreview: $showMousePreview,
                    isEnabled: engine.isEnabled,
                    showSettingsToggle: true,
                    isSettingsExpanded: $showMouseSpeedTuning
                ) {
                    mouseTuningSection
                }

                MinimalDisplayRow(
                    displayManager: displayManager,
                    isIT: isIT
                )

                if batteryManager.hasBattery {
                    MinimalBatteryRow(
                        batteryManager: batteryManager,
                        isIT: isIT,
                        isExpanded: $showBatteryDetails
                    )
                }
            }

            Divider()
                .opacity(0.35)

            footerBar
        }
        .padding(14)
        .frame(width: 288)
        .animation(.snappy(duration: 0.22), value: engine.isEnabled)
        .animation(.snappy(duration: 0.22), value: showMouseSpeedTuning)
        .animation(.snappy(duration: 0.22), value: showTrackpadPreview)
        .animation(.snappy(duration: 0.22), value: showMousePreview)
        .animation(.snappy(duration: 0.22), value: showBatteryDetails)
        .animation(.snappy(duration: 0.22), value: caffeineManager.isActive)
        .animation(.snappy(duration: 0.22), value: engine.isAccessibilityGranted)
        .animation(.snappy(duration: 0.18), value: engine.language)
    }

    // MARK: - Compact Header with Quick Caffè & Capture Action Icons
    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "slider.horizontal.2.square")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(engine.isEnabled ? .primary : .tertiary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                )

            HStack(spacing: 6) {
                Text("Periphera")
                    .font(.system(size: 13.5, weight: .semibold))
                    .tracking(-0.2)

                Circle()
                    .fill(statusDotColor)
                    .frame(width: 5.5, height: 5.5)
            }

            Spacer()

            // 1. Icona Caffè: al tocco cambia colore (arancione attivo, spento inattivo)
            Button {
                withAnimation(.snappy(duration: 0.18)) {
                    caffeineManager.toggle()
                }
            } label: {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(caffeineManager.isActive ? Color.orange : Color.secondary.opacity(0.65))
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(caffeineManager.isActive ? Color.orange.opacity(0.14) : Color.primary.opacity(0.04))
                    )
            }
            .buttonStyle(.plain)
            .help(isIT ? (caffeineManager.isActive ? "Caffè attivo (anti-sospensione)" : "Attiva Caffè") : (caffeineManager.isActive ? "Caffeine active (keep awake)" : "Activate Caffeine"))

            // 2. Icona Cattura Schermo: al tocco apre la barra flottante trascinabile
            Button {
                CaptureOverlayController.shared.toggle(isIT: isIT)
            } label: {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CaptureOverlayController.shared.isVisible ? Color.primary : Color.secondary.opacity(0.65))
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(CaptureOverlayController.shared.isVisible ? Color.primary.opacity(0.12) : Color.primary.opacity(0.04))
                    )
            }
            .buttonStyle(.plain)
            .help(isIT ? "Apri barra screenshot & video (⌘⇧6)" : "Open screenshot & video bar (⌘⇧6)")

            // 3. Switch On/Off generale
            Toggle("", isOn: $engine.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
        }
    }

    private var statusDotColor: Color {
        if !engine.isAccessibilityGranted { return .orange }
        if !engine.isEnabled { return .secondary.opacity(0.4) }
        return Color(red: 0.25, green: 0.78, blue: 0.48)
    }

    // MARK: - Minimal Permission Notice
    private var permissionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)

            Text(isIT ? "Richiesto accesso Accessibilità" : "Accessibility access required")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Button(isIT ? "Abilita" : "Enable") {
                engine.requestAccessibilityPermission()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.10))
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.22), lineWidth: 0.8)
                )
        )
    }

    // MARK: - Inline Mouse Wheel Speed & Horizontal Tuning
    private var mouseTuningSection: some View {
        VStack(spacing: 7) {
            HStack {
                Text(isIT ? "Velocità rotella" : "Wheel speed")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1fx", engine.mouseSpeedMultiplier))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.8))
            }

            Slider(value: $engine.mouseSpeedMultiplier, in: 0.5...2.5, step: 0.1)
                .controlSize(.mini)
                .tint(.primary)

            Toggle(
                isIT ? "Inverti anche scorrimento orizzontale" : "Also invert horizontal scroll",
                isOn: $engine.invertMouseHorizontal
            )
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.6)
                )
        )
    }

    // MARK: - Minimal Footer
    private var footerBar: some View {
        HStack(spacing: 8) {
            Button {
                engine.toggleLaunchAtLogin()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: engine.launchAtLogin ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 11))
                        .foregroundStyle(engine.launchAtLogin ? .primary : .tertiary)
                    Text(isIT ? "Avvia al login" : "Launch at login")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Minimal IT / EN language switch
            Button {
                engine.language = (engine.language == .it) ? .en : .it
            } label: {
                Text(engine.language.rawValue)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 2.5)
                    .background(
                        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .help(isIT ? "Switch to English" : "Passa all'Italiano")

            Button(isIT ? "Esci" : "Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Minimal External Display Brightness Row
private struct MinimalDisplayRow: View {
    @Bindable var displayManager: DisplayManager
    let isIT: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "display")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                Text(isIT ? "Monitor" : "Display")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                if let name = displayManager.primaryExternalName {
                    Text(name)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                if displayManager.hasExternalDisplay {
                    Text("\(Int(displayManager.brightness.rounded()))%")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else {
                    Text(isIT ? "Non connesso" : "Not connected")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "sun.min")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.tertiary)

                Slider(value: $displayManager.brightness, in: 10...100, step: 1)
                    .controlSize(.mini)
                    .tint(.primary)
                    .disabled(!displayManager.hasExternalDisplay)

                Image(systemName: "sun.max.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.8)
                )
        )
        .opacity(displayManager.hasExternalDisplay ? 1.0 : 0.5)
    }
}

// MARK: - Device Row with Expandable (i) Simulator & Optional Inline Settings
private struct MinimalDeviceRow<ExtraContent: View>: View {
    let title: String
    let icon: String
    let deviceKind: InputDeviceType
    let naturalLabel: String
    let classicLabel: String
    let isIT: Bool
    let isActiveNow: Bool
    @Binding var isNatural: Bool
    @Binding var showInfoPreview: Bool
    let isEnabled: Bool
    let showSettingsToggle: Bool
    @Binding var isSettingsExpanded: Bool
    @ViewBuilder let extraContent: () -> ExtraContent

    init(
        title: String,
        icon: String,
        deviceKind: InputDeviceType,
        naturalLabel: String,
        classicLabel: String,
        isIT: Bool,
        isActiveNow: Bool,
        isNatural: Binding<Bool>,
        showInfoPreview: Binding<Bool>,
        isEnabled: Bool,
        showSettingsToggle: Bool = false,
        isSettingsExpanded: Binding<Bool> = .constant(false),
        @ViewBuilder extraContent: @escaping () -> ExtraContent = { EmptyView() }
    ) {
        self.title = title
        self.icon = icon
        self.deviceKind = deviceKind
        self.naturalLabel = naturalLabel
        self.classicLabel = classicLabel
        self.isIT = isIT
        self.isActiveNow = isActiveNow
        self._isNatural = isNatural
        self._showInfoPreview = showInfoPreview
        self.isEnabled = isEnabled
        self.showSettingsToggle = showSettingsToggle
        self._isSettingsExpanded = isSettingsExpanded
        self.extraContent = extraContent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                if isActiveNow {
                    Circle()
                        .fill(Color.primary.opacity(0.65))
                        .frame(width: 4.5, height: 4.5)
                        .transition(.opacity)
                }

                Spacer()

                if showSettingsToggle {
                    Button {
                        withAnimation(.snappy(duration: 0.22)) {
                            isSettingsExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 11.5, weight: .regular))
                            .foregroundStyle(isSettingsExpanded ? .primary : .tertiary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isIT ? "Velocità e opzioni rotella" : "Wheel speed & options")
                }

                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        showInfoPreview.toggle()
                    }
                } label: {
                    Image(systemName: showInfoPreview ? "info.circle.fill" : "info.circle")
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundStyle(showInfoPreview ? .primary : .tertiary)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(isIT ? "Mostra simulazione scorrimento" : "Show scroll simulation")
            }

            HStack(spacing: 4) {
                SegmentPill(
                    label: naturalLabel,
                    isSelected: isNatural
                ) {
                    withAnimation(.snappy(duration: 0.18)) {
                        isNatural = true
                    }
                }

                SegmentPill(
                    label: classicLabel,
                    isSelected: !isNatural
                ) {
                    withAnimation(.snappy(duration: 0.18)) {
                        isNatural = false
                    }
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )

            if isSettingsExpanded {
                extraContent()
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }

            if showInfoPreview {
                ScrollSimulationPreview(
                    deviceKind: deviceKind,
                    isNatural: isNatural,
                    isIT: isIT
                )
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(isActiveNow ? 0.18 : 0.06), lineWidth: 0.8)
                )
        )
        .opacity(isEnabled ? 1.0 : 0.5)
    }
}

// MARK: - Animated Simulation View
private struct ScrollSimulationPreview: View {
    let deviceKind: InputDeviceType
    let isNatural: Bool
    let isIT: Bool

    @State private var phase: Bool = false

    private var inputMovesUp: Bool {
        isNatural
    }

    private var gestureCaption: String {
        switch deviceKind {
        case .trackpad:
            if isNatural {
                return isIT ? "Dita in su ↑" : "Fingers up ↑"
            } else {
                return isIT ? "Dita in giù ↓" : "Fingers down ↓"
            }
        case .mouse:
            if isNatural {
                return isIT ? "Rotella su ↑" : "Wheel up ↑"
            } else {
                return isIT ? "Rotella giù ↓" : "Wheel down ↓"
            }
        }
    }

    private var pageCaption: String {
        isIT ? "Scendi pagina ↓" : "Page down ↓"
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 4) {
                if deviceKind == .trackpad {
                    simulatedTrackpad
                } else {
                    simulatedMouse
                }

                Text(gestureCaption)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .offset(y: -7)

            VStack(spacing: 4) {
                simulatedPage

                Text(pageCaption)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.6)
                )
        )
        .onAppear {
            startLoopAnimation()
        }
        .onChange(of: isNatural) { _, _ in
            phase = false
            startLoopAnimation()
        }
    }

    private func startLoopAnimation() {
        withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
            phase = true
        }
    }

    private var simulatedTrackpad: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.8)
                )
                .frame(width: 54, height: 38)

            let startY: CGFloat = inputMovesUp ? 7 : -7
            let endY: CGFloat = inputMovesUp ? -7 : 7

            HStack(spacing: 5) {
                Circle()
                    .fill(Color.primary.opacity(0.75))
                    .frame(width: 6, height: 6)
                Circle()
                    .fill(Color.primary.opacity(0.75))
                    .frame(width: 6, height: 6)
            }
            .offset(y: phase ? endY : startY)
        }
    }

    private var simulatedMouse: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.8)
                )
                .frame(width: 28, height: 38)

            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.10))
                .frame(width: 5, height: 14)
                .offset(y: -5)

            let startY: CGFloat = inputMovesUp ? -2 : -8
            let endY: CGFloat = inputMovesUp ? -8 : -2

            Circle()
                .fill(Color.primary.opacity(0.82))
                .frame(width: 4, height: 4)
                .offset(y: phase ? endY : startY)
        }
        .frame(width: 54, height: 38)
    }

    private var simulatedPage: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.8)
                )
                .frame(width: 54, height: 38)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(0..<5, id: \.self) { idx in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.primary.opacity(idx == 2 ? 0.55 : 0.25))
                        .frame(width: idx % 2 == 0 ? 30 : 22, height: 2.2)
                }
            }
            .frame(width: 42, alignment: .leading)
            .offset(x: -4, y: phase ? -6 : 6)
            .frame(width: 52, height: 34)
            .clipped()

            Capsule()
                .fill(Color.primary.opacity(0.65))
                .frame(width: 2.2, height: 9)
                .padding(.trailing, 3.5)
                .offset(y: phase ? 7 : -7)
        }
    }
}

private struct SegmentPill: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4.5)
                .background(
                    Group {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                                )
                        }
                    }
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Minimal Battery Row (AlDente Style)
private struct MinimalBatteryRow: View {
    @Bindable var batteryManager: BatteryManager
    let isIT: Bool
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header Row: Icon, Title, Badge & Quick Controls
            HStack(spacing: 7) {
                Image(systemName: batteryManager.batteryIconName)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(batteryManager.statusColor)
                    .frame(width: 16)

                HStack(spacing: 4) {
                    Text(isIT ? "Batteria" : "Battery")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text("AlDente")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule()
                                .fill(Color.orange.opacity(0.12))
                        )

                    if batteryManager.isHardwareHelperInstalled {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 8.5))
                            .foregroundStyle(Color(red: 0.25, green: 0.78, blue: 0.48))
                            .help(isIT ? "Controllo hardware SMC attivo" : "Hardware SMC control active")
                    }
                }

                Spacer()

                // Battery % & Status Badge
                HStack(spacing: 4) {
                    Text("\(batteryManager.level)%")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)

                    if batteryManager.isHardwareChargingBlocked {
                        Image(systemName: "pause.circle.fill")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Color(red: 0.25, green: 0.78, blue: 0.48))
                            .help(isIT ? "Ricarica arrestata fisicamente (Hardware)" : "Charging physically halted (Hardware)")
                    } else if batteryManager.isProtectionEnabled && batteryManager.isACConnected && batteryManager.level >= batteryManager.chargeLimit {
                        Image(systemName: "shield.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color(red: 0.25, green: 0.78, blue: 0.48))
                            .help(isIT ? "Batteria protetta da sovratensione" : "Battery protected from overvoltage")
                    }
                }

                // Top Up 100% Quick Button
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        batteryManager.toggleTopUp()
                    }
                } label: {
                    HStack(spacing: 2.5) {
                        Image(systemName: batteryManager.isTopUpActive ? "bolt.fill" : "bolt")
                            .font(.system(size: 8.5, weight: .bold))
                        Text("100%")
                            .font(.system(size: 8.5, weight: .semibold))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(batteryManager.isTopUpActive ? Color.blue.opacity(0.2) : Color.primary.opacity(0.06))
                    )
                    .foregroundStyle(batteryManager.isTopUpActive ? Color.blue : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(isIT ? "Top Up: Ricarica al 100% per viaggi/mobilità" : "Top Up: Charge to 100% for travel")

                // Expand/Collapse Chevron
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.secondary.opacity(0.7))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
            }

            // Charge Limit Slider & Preset Buttons
            VStack(spacing: 5) {
                HStack {
                    Text(isIT ? "Limite di Carica" : "Charge Limit")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(batteryManager.isTopUpActive ? "Top Up (100%)" : "\(batteryManager.chargeLimit)%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(batteryManager.isTopUpActive ? Color.blue : Color.primary)
                }

                HStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { Double(batteryManager.chargeLimit) },
                            set: { batteryManager.setLimit(Int($0)) }
                        ),
                        in: 60...100,
                        step: 5
                    )
                    .controlSize(.mini)
                    .tint(batteryManager.isTopUpActive ? .blue : .primary)
                    .disabled(batteryManager.isTopUpActive)

                    // Quick Preset Buttons: 70%, 80%, 90%
                    HStack(spacing: 3) {
                        ForEach([70, 80, 90], id: \.self) { preset in
                            Button {
                                batteryManager.setLimit(preset)
                            } label: {
                                Text("\(preset)")
                                    .font(.system(size: 8.5, weight: .semibold))
                                    .padding(.horizontal, 4.5)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .fill(batteryManager.chargeLimit == preset && !batteryManager.isTopUpActive ? Color.primary.opacity(0.12) : Color.primary.opacity(0.04))
                                    )
                                    .foregroundStyle(batteryManager.chargeLimit == preset && !batteryManager.isTopUpActive ? Color.primary : Color.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Subtitle Status
                HStack(spacing: 4) {
                    Circle()
                        .fill(batteryManager.statusColor)
                        .frame(width: 4.5, height: 4.5)

                    Text(batteryManager.statusDescription(isIT: isIT))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Hardware Helper Install Notice if not yet installed
            if !batteryManager.isHardwareHelperInstalled {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.shield.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(isIT ? "Blocco Ricarica Fisico" : "Physical Charge Halt")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text(isIT ? "Installa l'helper per arrestare la carica al limite" : "Install helper to halt charge at limit")
                            .font(.system(size: 8.5))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        _ = withAnimation(.snappy(duration: 0.22)) {
                            batteryManager.installHardwareHelper()
                        }
                    } label: {
                        Text(isIT ? "Abilita" : "Enable")
                            .font(.system(size: 9.5, weight: .bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(Color.orange.opacity(0.18))
                            )
                            .foregroundStyle(Color.orange)
                    }
                    .buttonStyle(.plain)
                }
                .padding(7)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.orange.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Color.orange.opacity(0.20), lineWidth: 0.8)
                        )
                )
            }

            // Expandable AlDente Settings & Diagnostics
            if isExpanded {
                VStack(spacing: 8) {
                    Divider()
                        .opacity(0.3)

                    // Hardware Helper Status in Expanded View
                    if batteryManager.isHardwareHelperInstalled {
                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.shield.fill")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(Color(red: 0.25, green: 0.78, blue: 0.48))
                                Text(isIT ? "Blocco Hardware SMC attivo" : "SMC Hardware Halt active")
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(isIT ? "Disinstalla helper" : "Uninstall helper") {
                                batteryManager.uninstallHardwareHelper()
                            }
                            .font(.system(size: 8.5))
                            .foregroundStyle(.tertiary)
                            .buttonStyle(.plain)
                        }
                    }

                    // Sailing Mode & Heat Protection Toggles
                    VStack(spacing: 5) {
                        Toggle(
                            isIT ? "Veleggiamento (Sailing 5%)" : "Sailing Mode (5% buffer)",
                            isOn: $batteryManager.isSailingEnabled
                        )
                        .font(.system(size: 10, weight: .medium))
                        .toggleStyle(.checkbox)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(isIT ? "Evita micro-ricariche consentendo alla batteria di oscillare" : "Prevents micro-charging by allowing battery to drift")

                        Toggle(
                            isIT ? "Protezione Termica (\(Int(batteryManager.maxTempThreshold))°C)" : "Heat Protection (\(Int(batteryManager.maxTempThreshold))°C)",
                            isOn: $batteryManager.isHeatProtectionEnabled
                        )
                        .font(.system(size: 10, weight: .medium))
                        .toggleStyle(.checkbox)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(isIT ? "Avvisa se la batteria supera la soglia di calore" : "Alerts if battery exceeds heat threshold")

                        Toggle(
                            isIT ? "Notifica & suono al limite" : "Notify & sound when limit reached",
                            isOn: $batteryManager.notifyOnLimit
                        )
                        .font(.system(size: 10, weight: .medium))
                        .toggleStyle(.checkbox)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Telemetry Diagnostic Tiles
                    HStack(spacing: 5) {
                        DiagnosticTile(
                            title: isIT ? "Salute" : "Health",
                            value: "\(batteryManager.healthPercentage)%",
                            subtitle: batteryManager.healthCondition(isIT: isIT)
                        )

                        DiagnosticTile(
                            title: isIT ? "Cicli" : "Cycles",
                            value: "\(batteryManager.cycleCount)",
                            subtitle: "/ \(batteryManager.maxDesignCycles)"
                        )

                        DiagnosticTile(
                            title: isIT ? "Temp." : "Temp.",
                            value: String(format: "%.1f°", batteryManager.temperatureCelsius),
                            subtitle: batteryManager.temperatureCelsius < 33 ? (isIT ? "Ottima" : "Cool") : (isIT ? "Calda" : "Warm")
                        )

                        DiagnosticTile(
                            title: isIT ? "Potenza" : "Power",
                            value: String(format: "%.1fW", batteryManager.wattage),
                            subtitle: batteryManager.isCharging ? (isIT ? "In carica" : "In") : (isIT ? "Assorb." : "Out")
                        )
                    }

                    // Hardware Details Footer
                    if batteryManager.rawMaxCapacity > 0 && batteryManager.designCapacity > 0 {
                        HStack {
                            Text(isIT ? "Capacità: \(batteryManager.rawMaxCapacity) / \(batteryManager.designCapacity) mAh" : "Capacity: \(batteryManager.rawMaxCapacity) / \(batteryManager.designCapacity) mAh")
                                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            Spacer()
                            if !batteryManager.deviceName.isEmpty {
                                Text(batteryManager.deviceName)
                                    .font(.system(size: 8.5))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.8)
                )
        )
    }
}

// MARK: - Diagnostic Tile
private struct DiagnosticTile: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.tertiary)

            Text(value)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.system(size: 7.5, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }
}

#Preview {
    ContentView(
        engine: ScrollEngine(),
        displayManager: DisplayManager(),
        caffeineManager: CaffeineManager.shared,
        captureManager: ScreenCaptureManager.shared,
        batteryManager: BatteryManager.shared
    )
}
