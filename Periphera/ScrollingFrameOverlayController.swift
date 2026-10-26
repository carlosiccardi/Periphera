//
//  ScrollingFrameOverlayController.swift
//  Periphera
//
//  Created by Carlo Siccardi on 26/10/2026.
//

import Cocoa
import SwiftUI

final class ScrollingFramePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Custom NSView that allows mouse and scroll wheel events to pass through directly
/// to whatever window is behind the selection box, while keeping the HUD control bar fully interactive.
final class ScrollingFramePassThroughView: NSView {
    var captureRect: CGRect = .zero
    var pillHostingView: NSView?

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let pill = pillHostingView {
            let localToPill = pill.convert(point, from: self)
            if pill.bounds.contains(localToPill) {
                return pill.hitTest(point)
            }
        }

        // Inside the capture box or anywhere on the backdrop:
        // Return nil so mouse and trackpad scroll events reach the underlying web page or application!
        return nil
    }
}

@MainActor
final class ScrollingFrameOverlayController {
    static let shared = ScrollingFrameOverlayController()

    private var panel: ScrollingFramePanel?
    private var keyMonitor: Any?

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

        let framePanel = ScrollingFramePanel(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        framePanel.level = .floating
        framePanel.isOpaque = false
        framePanel.backgroundColor = .clear
        framePanel.hasShadow = false
        framePanel.ignoresMouseEvents = false
        framePanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let containerView = ScrollingFramePassThroughView(frame: screen.frame)
        containerView.captureRect = rect

        // Overlay View drawing frame cutout and floating control pill
        let hudView = ScrollingCaptureSessionHUD(
            rect: rect,
            isIT: isIT,
            manager: manager,
            onDone: onDone,
            onCancel: onCancel
        )

        let hostingView = NSHostingView(rootView: hudView)
        hostingView.frame = screen.frame
        containerView.pillHostingView = hostingView
        containerView.addSubview(hostingView)

        framePanel.contentView = containerView
        framePanel.setFrame(screen.frame, display: true)
        framePanel.alphaValue = 0
        framePanel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            framePanel.animator().alphaValue = 1.0
        }

        self.panel = framePanel

        // Keyboard monitor for Enter (Done) and Esc (Cancel)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
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
    }

    func hide() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }

        guard let p = panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                p.close()
                self?.panel = nil
            }
        })
    }
}

// MARK: - Active Scrolling Capture HUD (CleanShot X Style)
private struct ScrollingCaptureSessionHUD: View {
    let rect: CGRect
    let isIT: Bool
    @Bindable var manager: ScreenCaptureManager
    let onDone: () -> Void
    let onCancel: () -> Void

    @State private var pulse: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // 1. Subtle dark vignette outside the captured rect to focus user attention
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geometry.size))
                    path.addRoundedRect(in: rect, cornerSize: CGSize(width: 4, height: 4))
                }
                .fill(Color.black.opacity(0.18), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

                // 2. Glowing frame border around the active capture rectangle
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.blue.opacity(0.9), lineWidth: 2.0)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)

                // 3. Size badge at top corner of frame
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
                .allowsHitTesting(false)

                // 4. CleanShot X-Style Floating Control Pill Bar
                floatingPillBar(geometry: geometry)
            }
        }
    }

    private func floatingPillBar(geometry: GeometryProxy) -> some View {
        // Position pill bar right below the capture rect, or at bottom-center if rect touches bottom
        let barY: CGFloat = min(geometry.size.height - 40, rect.maxY + 36)
        let barX: CGFloat = min(max(rect.midX, 220), geometry.size.width - 220)

        return HStack(spacing: 12) {
            // Live Thumbnail if available
            if let thumb = manager.scrollingLiveThumbnail {
                Image(nsImage: thumb)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.2), lineWidth: 0.5))
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
        .shadow(color: .black.opacity(0.32), radius: 20, x: 0, y: 8)
        .frame(width: 380, height: 50)
        .position(x: barX, y: barY)
    }
}
