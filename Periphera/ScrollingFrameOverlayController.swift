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
        let margin: CGFloat = 20
        let cardW: CGFloat = 490
        let cardH: CGFloat = 48
        let windowW: CGFloat = cardW + (margin * 2)
        let windowH: CGFloat = cardH + (margin * 2)

        // Position pill bar centered relative to the capture rect, below it or at top if near bottom
        var pillX = rect.midX - (windowW / 2.0)
        pillX = max(8, min(screen.frame.width - windowW - 8, pillX))

        // Convert SwiftUI top-left Y to Cocoa bottom-left Y
        var pillY = screen.frame.height - rect.maxY - windowH - 8
        if pillY < 20 {
            let topY = screen.frame.height - rect.minY + 8
            pillY = (topY + windowH < screen.frame.height - 30) ? topY : 20
        }

        let pPanel = NonActivatingFloatingPanel(
            contentRect: NSRect(x: pillX, y: pillY, width: windowW, height: windowH),
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
        pillHosting.frame = NSRect(x: 0, y: 0, width: windowW, height: windowH)
        pPanel.contentView = pillHosting
        pPanel.alphaValue = 0
        pPanel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            pPanel.animator().alphaValue = 1.0
        }
        self.pillPanel = pPanel

        // --- 3. Install Global & Local Key Monitors for Enter (Done), Esc (Cancel), and Space (Auto Scroll) ---
        installKeyMonitors(manager: manager, onDone: onDone, onCancel: onCancel)
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

    private func installKeyMonitors(manager: ScreenCaptureManager, onDone: @escaping () -> Void, onCancel: @escaping () -> Void) {
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
            if event.keyCode == 49 { // Space: toggle auto scroll
                manager.toggleAutoScroll()
                return nil
            }
            return event
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 36 { // Return / Enter
                Task { @MainActor in onDone() }
            } else if event.keyCode == 53 { // Esc
                Task { @MainActor in onCancel() }
            } else if event.keyCode == 49 { // Space
                Task { @MainActor in manager.toggleAutoScroll() }
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
                Text(manager.isAutoScrolling
                     ? (isIT ? "Scorrimento in corso..." : "Auto scrolling...")
                     : (isIT ? "Scorri o premi Auto..." : "Scroll or click Auto..."))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(manager.isAutoScrolling ? Color.orange : Color.primary)

                Text(isIT
                     ? "\(manager.scrollingTotalHeight) px • \(manager.scrollingFramesCount) sezioni"
                     : "\(manager.scrollingTotalHeight) px • \(manager.scrollingFramesCount) slices")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Auto Scroll Button (Play / Pause)
            Button {
                manager.toggleAutoScroll()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: manager.isAutoScrolling ? "pause.fill" : "play.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(manager.isAutoScrolling
                         ? (isIT ? "Pausa" : "Pause")
                         : (isIT ? "Auto Scroll" : "Auto Scroll"))
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 5.5)
                .background(
                    Capsule()
                        .fill(manager.isAutoScrolling ? Color.orange : Color.primary.opacity(0.10))
                )
                .foregroundStyle(manager.isAutoScrolling ? Color.white : Color.primary)
            }
            .buttonStyle(.plain)
            .help(isIT ? "Avvia/Pausa lo scorrimento automatico (Spazio)" : "Start/Pause automatic scrolling (Space)")

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
        .frame(width: 490, height: 48)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8)
                )
        )
        // Soft natural shadow that fades out well within the 20pt window margin
        .shadow(color: .black.opacity(0.20), radius: 12, x: 0, y: 5)
        .padding(20)
    }
}
