//
//  ScrollingFrameOverlayController.swift
//  Periphera
//
//  Created by Carlo Siccardi on 26/10/2026.
//

import Cocoa
import SwiftUI

final class NonActivatingFloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ScrollingFrameOverlayController {
    static let shared = ScrollingFrameOverlayController()

    // 1. Passive Border Frame Window (ignoresMouseEvents = true so scrolling goes straight to the page)
    private var borderPanel: NonActivatingFloatingPanel?

    // 2. Interactive Floating Pill HUD Window (placed below the area, size: 380x54)
    private var pillPanel: NonActivatingFloatingPanel?

    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?

    private init() {}

    func show(
        rect: CGRect,
        isIT: Bool,
        manager: ScreenCaptureManager,
        onDone: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        hide()

        guard let screen = NSScreen.main else { return }

        // --- 1. Create Passive Border Window (100% Click-Through & Scroll-Through) ---
        let bPanel = NonActivatingFloatingPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        bPanel.level = .floating
        bPanel.isOpaque = false
        bPanel.backgroundColor = .clear
        bPanel.hasShadow = false
        bPanel.ignoresMouseEvents = true // CRITICAL: mouse & trackpad events pass right through to Safari / Chrome!
        bPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let borderView = ScrollingBorderFrameView(rect: rect, isIT: isIT)
        let borderHosting = NSHostingView(rootView: borderView)
        borderHosting.frame = screen.frame
        bPanel.contentView = borderHosting
        bPanel.setFrame(screen.frame, display: true)
        bPanel.orderFrontRegardless()
        self.borderPanel = bPanel

        // --- 2. Create Floating Pill HUD Window (Outside capture area, fully clickable) ---
        let pillW: CGFloat = 380
        let pillH: CGFloat = 54

        // Position pill bar centered relative to the capture rect, 16pt below it (or bottom of screen)
        var pillX = rect.midX - (pillW / 2.0)
        pillX = max(16, min(screen.frame.width - pillW - 16, pillX))

        // Convert SwiftUI top-left Y to Cocoa bottom-left Y
        // SwiftUI: rect.maxY is distance from top of screen
        // Cocoa: y = screenH - rect.maxY - pillH - 16
        var pillY = screen.frame.height - rect.maxY - pillH - 16
        if pillY < 24 {
            // If rect reaches the bottom of the screen, place pill bar above rect or 24pt from bottom
            let topY = screen.frame.height - rect.minY + 16
            pillY = (topY + pillH < screen.frame.height - 30) ? topY : 24
        }

        let pPanel = NonActivatingFloatingPanel(
            contentRect: NSRect(x: pillX, y: pillY, width: pillW, height: pillH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        pPanel.level = .floating
        pPanel.isOpaque = false
        pPanel.backgroundColor = .clear
        pPanel.hasShadow = false
        pPanel.ignoresMouseEvents = false
        pPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let pillView = ScrollingControlBarView(
            rect: rect,
            isIT: isIT,
            manager: manager,
            onDone: onDone,
            onCancel: onCancel
        )
        let pillHosting = NSHostingView(rootView: pillView)
        pillHosting.frame = NSRect(x: 0, y: 0, width: pillW, height: pillH)
        pPanel.contentView = pillHosting
        pPanel.alphaValue = 0
        pPanel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            pPanel.animator().alphaValue = 1.0
        }
        self.pillPanel = pPanel

        // --- 3. Install Global & Local Key Monitors for Enter (Done) & Esc (Cancel) ---
        installKeyMonitors(onDone: onDone, onCancel: onCancel)
    }

    func hide() {
        removeKeyMonitors()

        if let b = borderPanel {
            b.orderOut(nil)
            borderPanel = nil
        }

        if let p = pillPanel {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.12
                p.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    p.close()
                    self?.pillPanel = nil
                }
            })
        }
    }

    private func installKeyMonitors(onDone: @escaping () -> Void, onCancel: @escaping () -> Void) {
        removeKeyMonitors()

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 36 { // Return / Enter
                onDone()
                return nil
            }
            if event.keyCode == 53 { // Esc
                onCancel()
                return nil
            }
            return event
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 36 { // Return / Enter
                Task { @MainActor in onDone() }
            } else if event.keyCode == 53 { // Esc
                Task { @MainActor in onCancel() }
            }
        }
    }

    private func removeKeyMonitors() {
        if let local = localKeyMonitor {
            NSEvent.removeMonitor(local)
            localKeyMonitor = nil
        }
        if let global = globalKeyMonitor {
            NSEvent.removeMonitor(global)
            globalKeyMonitor = nil
        }
    }
}

// MARK: - Passive Border Frame View (Drawn on ignoresMouseEvents panel)
private struct ScrollingBorderFrameView: View {
    let rect: CGRect
    let isIT: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // Subtle focus backdrop
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geometry.size))
                    path.addRoundedRect(in: rect, cornerSize: CGSize(width: 4, height: 4))
                }
                .fill(Color.black.opacity(0.18), style: FillStyle(eoFill: true))

                // Frame Outline
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.blue.opacity(0.9), lineWidth: 2.0)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)

                // Dimensions badge
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.and.down")
                        .font(.system(size: 8.5, weight: .bold))
                    Text("\(Int(rect.width)) × \(Int(rect.height)) px")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.blue.opacity(0.85)))
                .position(x: rect.minX + 55, y: max(20, rect.minY - 14))
            }
        }
    }
}

// MARK: - Floating Control Bar View (CleanShot X Style Pill)
private struct ScrollingControlBarView: View {
    let rect: CGRect
    let isIT: Bool
    @Bindable var manager: ScreenCaptureManager
    let onDone: () -> Void
    let onCancel: () -> Void

    @State private var pulse: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Live Thumbnail if available
            if let thumb = manager.scrollingLiveThumbnail {
                Image(nsImage: thumb)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.25), lineWidth: 0.5))
            } else {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulse ? 1.25 : 0.85)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                    .onAppear { pulse = true }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(isIT ? "Scorri verso il basso..." : "Scroll down slowly...")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(isIT
                     ? "Altezza: \(manager.scrollingTotalHeight) px • \(manager.scrollingFramesCount) sezioni"
                     : "Height: \(manager.scrollingTotalHeight) px • \(manager.scrollingFramesCount) slices")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Done Button
            Button(action: onDone) {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    Text(isIT ? "Fine (Invio)" : "Done (Enter)")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 5.5)
                .background(
                    Capsule()
                        .fill(Color.blue)
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            // Cancel Button
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help(isIT ? "Annulla (Esc)" : "Cancel (Esc)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8)
                )
        )
        .shadow(color: .black.opacity(0.30), radius: 18, x: 0, y: 8)
        .frame(width: 380, height: 50)
    }
}
