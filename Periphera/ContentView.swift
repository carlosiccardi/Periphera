//
//  ContentView.swift
//  Periphera
//
//  Created by Carlo Siccardi on 19/10/2026.
//

import SwiftUI

struct ContentView: View {
    @Bindable var engine: ScrollEngine
    @Bindable var displayManager: DisplayManager
    @State private var showSpeedTuning: Bool = false
    @State private var showTrackpadPreview: Bool = false
    @State private var showMousePreview: Bool = false

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
                    isEnabled: engine.isEnabled
                )

                MinimalDisplayRow(
                    displayManager: displayManager,
                    isIT: isIT
                )
            }

            if showSpeedTuning {
                speedBar
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()
                .opacity(0.35)

            footerBar
        }
        .padding(14)
        .frame(width: 288)
        .animation(.snappy(duration: 0.22), value: engine.isEnabled)
        .animation(.snappy(duration: 0.22), value: showSpeedTuning)
        .animation(.snappy(duration: 0.22), value: showTrackpadPreview)
        .animation(.snappy(duration: 0.22), value: showMousePreview)
        .animation(.snappy(duration: 0.22), value: engine.isAccessibilityGranted)
        .animation(.snappy(duration: 0.18), value: engine.language)
    }

    // MARK: - Compact Header
    private var headerBar: some View {
        HStack(spacing: 9) {
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

    // MARK: - Compact Mouse Speed Row
    private var speedBar: some View {
        VStack(spacing: 7) {
            HStack {
                Text(isIT ? "Velocità rotella" : "Wheel speed")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1fx", engine.mouseSpeedMultiplier))
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.8))
            }

            Slider(value: $engine.mouseSpeedMultiplier, in: 0.5...2.5, step: 0.1)
                .controlSize(.mini)
                .tint(.primary)

            Toggle(
                isIT ? "Inverti anche scorrimento orizzontale" : "Also invert horizontal scroll",
                isOn: $engine.invertMouseHorizontal
            )
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.035))
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

            Button {
                showSpeedTuning.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(showSpeedTuning ? .primary : .secondary)
                    .frame(width: 22, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.primary.opacity(showSpeedTuning ? 0.10 : 0.0))
                    )
            }
            .buttonStyle(.plain)
            .help(isIT ? "Opzioni mouse" : "Mouse options")

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

// MARK: - Ultra-Clean Device Row with Expandable (i) Simulator
private struct MinimalDeviceRow: View {
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

                // Minimal "i" in a circle button
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

            // Minimal Segmented Control
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

            // Expandable Simulated Trackpad / Mouse + Page Effect
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

// MARK: - Compact Animated Simulation View (Device -> Page Effect)
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

#Preview {
    ContentView(engine: ScrollEngine(), displayManager: DisplayManager())
}
