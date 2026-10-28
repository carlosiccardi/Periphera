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

                otherSectionHeader

                otherCard
            }

            Divider()
                .opacity(0.35)

            footerBar
        }
        .padding(14)
        .frame(width: 286)
        .animation(.snappy(duration: 0.22), value: engine.isEnabled)
        .animation(.snappy(duration: 0.22), value: showMouseSpeedTuning)
        .animation(.snappy(duration: 0.22), value: showTrackpadPreview)
        .animation(.snappy(duration: 0.22), value: showMousePreview)
        .animation(.snappy(duration: 0.22), value: showBatteryDetails)
        .animation(.snappy(duration: 0.22), value: caffeineManager.isActive)
        .animation(.snappy(duration: 0.22), value: engine.isAccessibilityGranted)
        .animation(.snappy(duration: 0.18), value: engine.language)
    }

    // MARK: - Penpot Header: Icon, Title & Switch Toggle
    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "slider.horizontal.2.square")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(.white.opacity(0.9))

            Text("Periphera")
                .font(.system(size: 14.5, weight: .regular))
                .foregroundStyle(.white)
                .tracking(-0.1)

            Spacer()

            Toggle("", isOn: $engine.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Penpot "Other" Section Header
    private var otherSectionHeader: some View {
        HStack(spacing: 7) {
            Text(isIT ? "Altro" : "Other")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.92))

            Spacer()
        }
        .padding(.horizontal, 2)
        .padding(.top, 4)
    }

    // MARK: - Penpot "Other" Card (Display, Battery, Coffee & Capture)
    private var otherCard: some View {
        VStack(spacing: 8) {
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

            // Quick Actions: Coffee & Capture Side-by-Side Pill Buttons
            HStack(spacing: 8) {
                // Coffee Button
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        caffeineManager.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: caffeineManager.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                            .font(.system(size: 11.5, weight: .light))
                        Text(isIT ? "Caffè" : "Coffee")
                            .font(.system(size: 11.5, weight: .regular))
                    }
                    .foregroundStyle(caffeineManager.isActive ? Color.orange : .white.opacity(0.9))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6.5)
                    .background(
                        RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                            .fill(caffeineManager.isActive ? Color.orange.opacity(0.18) : Color(red: 0.11, green: 0.11, blue: 0.11).opacity(0.25))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                                    .strokeBorder(caffeineManager.isActive ? Color.orange.opacity(0.35) : Color.white.opacity(0.06), lineWidth: 0.6)
                            )
                    )
                }
                .buttonStyle(.plain)
                .help(isIT ? (caffeineManager.isActive ? "Caffè attivo (anti-sospensione)" : "Attiva Caffè") : (caffeineManager.isActive ? "Caffeine active (keep awake)" : "Activate Caffeine"))

                // Capture Button
                Button {
                    CaptureOverlayController.shared.toggle(isIT: isIT)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 11.5, weight: .light))
                        Text(isIT ? "Cattura" : "Capture")
                            .font(.system(size: 11.5, weight: .regular))
                    }
                    .foregroundStyle(CaptureOverlayController.shared.isVisible ? Color.blue : .white.opacity(0.9))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6.5)
                    .background(
                        RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                            .fill(CaptureOverlayController.shared.isVisible ? Color.blue.opacity(0.20) : Color(red: 0.11, green: 0.11, blue: 0.11).opacity(0.25))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                                    .strokeBorder(CaptureOverlayController.shared.isVisible ? Color.blue.opacity(0.35) : Color.white.opacity(0.06), lineWidth: 0.6)
                            )
                    )
                }
                .buttonStyle(.plain)
                .help(isIT ? "Apri barra screenshot & video (⌘⇧6)" : "Open screenshot & video bar (⌘⇧6)")
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.11).opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.8)
                )
        )
    }

    // MARK: - Minimal Permission Notice
    private var permissionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)

            Text(isIT ? "Richiesto accesso Accessibilità" : "Accessibility access required")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)

            Spacer()

            Button(isIT ? "Abilita" : "Enable") {
                engine.requestAccessibilityPermission()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .regular))
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
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1fx", engine.mouseSpeedMultiplier))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.8))
            }

            Slider(value: $engine.mouseSpeedMultiplier, in: 0.5...2.5)
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

    // MARK: - Penpot Minimal Footer
    private var footerBar: some View {
        HStack(spacing: 8) {
            Button {
                engine.toggleLaunchAtLogin()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: engine.launchAtLogin ? "checkmark.circle" : "circle")
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(.white.opacity(0.8))
                    Text(isIT ? "Avvia al login" : "Launch at login")
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Minimal IT / EN language switch
            Button {
                engine.language = (engine.language == .it) ? .en : .it
            } label: {
                Text(engine.language.rawValue)
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .help(isIT ? "Switch to English" : "Passa all'Italiano")

            Button(isIT ? "Esci" : "Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .regular))
            .foregroundStyle(.white.opacity(0.65))
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Minimal External Display Brightness Row (Penpot Style)
private struct MinimalDisplayRow: View {
    @Bindable var displayManager: DisplayManager
    let isIT: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: "display")
                    .font(.system(size: 12.5, weight: .light))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 16)

                Text(isIT ? "Monitor" : "Display")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.92))

                Spacer()

                Text(displayManager.hasExternalDisplay ? (isIT ? "Connesso" : "Connected") : (isIT ? "Non connesso" : "Not connected"))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: true, vertical: false)
            }

            HStack(spacing: 8) {
                Image(systemName: "sun.min")
                    .font(.system(size: 10.5, weight: .light))
                    .foregroundStyle(.white.opacity(0.40))

                Slider(value: $displayManager.brightness, in: 10...100)
                    .controlSize(.mini)
                    .tint(.white.opacity(0.9))
                    .disabled(!displayManager.hasExternalDisplay)

                Image(systemName: "sun.max.fill")
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(.white.opacity(0.40))
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 9.5, style: .continuous)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.11).opacity(0.22))
                .overlay(
                    RoundedRectangle(cornerRadius: 9.5, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.05), lineWidth: 0.6)
                )
        )
        .opacity(displayManager.hasExternalDisplay ? 1.0 : 0.6)
    }
}

// MARK: - Device Row with Expandable (i) Simulator & Optional Inline Settings (Penpot Style)
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
                    .font(.system(size: 12.5, weight: .light))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.92))

                if isActiveNow {
                    Circle()
                        .fill(Color.white.opacity(0.75))
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
                        Image(systemName: isSettingsExpanded ? "gearshape.fill" : "gearshape")
                            .font(.system(size: 11.5, weight: .light))
                            .foregroundStyle(isSettingsExpanded ? .white : .white.opacity(0.45))
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
                        .font(.system(size: 11.5, weight: .light))
                        .foregroundStyle(showInfoPreview ? .white : .white.opacity(0.45))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(isIT ? "Mostra simulazione scorrimento" : "Show scroll simulation")
            }

            HStack(spacing: 3) {
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
            .padding(2.5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(red: 0.11, green: 0.11, blue: 0.11).opacity(0.25))
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
                .fill(Color(red: 0.11, green: 0.11, blue: 0.11).opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(isActiveNow ? 0.22 : 0.06), lineWidth: 0.8)
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
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.tertiary)
                .offset(y: -7)

            VStack(spacing: 4) {
                simulatedPage

                Text(pageCaption)
                    .font(.system(size: 9.5, weight: .regular))
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
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.65))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4.5)
                .background(
                    Group {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(red: 0.694, green: 0.698, blue: 0.710).opacity(0.35))
                        }
                    }
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Minimal Battery Row (Penpot & AlDente Style)
private struct MinimalBatteryRow: View {
    @Bindable var batteryManager: BatteryManager
    let isIT: Bool
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header Row: Icon, Title & % (Penpot Style)
            HStack(spacing: 7) {
                // Dynamic Battery Icon: Clean battery when limit reached/blocked, Bolt when charging/below limit
                Group {
                    if batteryManager.isChargingTowardsLimit {
                        // Battery with bolt (actively charging towards limit)
                        Image(systemName: "battery.100percent.bolt")
                            .font(.system(size: 12.5, weight: .light))
                    } else {
                        // Clean, serene battery outline (limit reached or discharging)
                        Image(systemName: "battery.100")
                            .font(.system(size: 12.5, weight: .light))
                    }
                }
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 16)

                Text(isIT ? "Batteria" : "Battery")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.92))

                Spacer()

                // Battery Set Charge Limit % (Penpot Style)
                Text("\(batteryManager.chargeLimit)%")
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: true, vertical: false)

                // Expand/Collapse Chevron for AlDente Details
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .regular))
                        .foregroundStyle(.white.opacity(0.45))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .help(isIT ? "Mostra/nascondi diagnostica" : "Show/hide diagnostics")
            }

            // Charge Limit Slider (Penpot Style)
            HStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { Double(batteryManager.chargeLimit) },
                        set: { batteryManager.setLimit(Int(round($0 / 5.0) * 5.0)) }
                    ),
                    in: 60...100
                )
                .controlSize(.mini)
                .tint(.white.opacity(0.9))
                .disabled(batteryManager.isTopUpActive)
            }

            // Expandable Diagnostics: ONLY Health, Cycles, Temp, Power
            if isExpanded {
                VStack(spacing: 6) {
                    Divider()
                        .opacity(0.2)

                    // Telemetry Diagnostic Tiles: Health, Cycles, Temp, Power
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
                }
                .padding(.top, 2)
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 9.5, style: .continuous)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.11).opacity(0.22))
                .overlay(
                    RoundedRectangle(cornerRadius: 9.5, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.05), lineWidth: 0.6)
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
                .font(.system(size: 8.5, weight: .regular))
                .foregroundStyle(.white.opacity(0.55))

            Text(value)
                .font(.system(size: 9.5, weight: .regular))
                .foregroundStyle(.white)

            Text(subtitle)
                .font(.system(size: 7.5, weight: .regular))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.04))
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
