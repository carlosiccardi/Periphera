//
//  CaptureOverlayController.swift
//  Periphera
//
//  Created by Carlo Siccardi on 25/10/2026.
//

import Cocoa
import SwiftUI
import Observation

final class CaptureToolbarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class SelectionOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@Observable
@MainActor
final class CaptureOverlayController {
    static let shared = CaptureOverlayController()

    @ObservationIgnored private var toolbarPanel: CaptureToolbarPanel?
    @ObservationIgnored private var selectionPanel: SelectionOverlayPanel?
    @ObservationIgnored private var localKeyMonitor: Any?

    var isVisible: Bool {
        (toolbarPanel?.isVisible ?? false) || (selectionPanel?.isVisible ?? false)
    }

    private init() {}

    func toggle(isIT: Bool = true) {
        if isVisible {
            hide()
        } else {
            show(isIT: isIT)
        }
    }

    func show(isIT: Bool = true) {
        dismissMenuBarPopovers()
        hideImmediately()

        guard let screen = NSScreen.main else { return }

        let barW: CGFloat = 490
        let barH: CGFloat = 80
        let barX = screen.frame.midX - (barW / 2.0)
        let barY = screen.visibleFrame.minY + 60

        let panel = CaptureToolbarPanel(
            contentRect: NSRect(x: barX, y: barY, width: barW, height: barH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true // Native AppKit dragging: 100% crash-proof & smooth
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let rootView = CaptureToolbarView(
            isIT: isIT,
            isRecording: ScreenCaptureManager.shared.isRecordingVideo,
            onSelectArea: { [weak self] in
                self?.presentAreaSelection(isIT: isIT)
            },
            onFullScreen: { [weak self] in
                self?.hideImmediately()
                ScreenCaptureManager.shared.captureFullScreenScreenshot(isIT: isIT)
            },
            onScrolling: { [weak self] in
                self?.presentScrollingSelection(isIT: isIT)
            },
            onToggleRecord: { [weak self] in
                self?.handleToggleRecord(isIT: isIT)
            },
            onClose: { [weak self] in
                self?.hide()
            }
        )

        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(x: 0, y: 0, width: barW, height: barH)
        panel.contentView = hosting

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        panel.animator().alphaValue = 1.0

        NSApp.activate(ignoringOtherApps: true)
        self.toolbarPanel = panel

        installToolbarKeyMonitor(isIT: isIT)
    }

    func hide() {
        removeKeyMonitor()
        if let p = toolbarPanel {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                p.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    p.orderOut(nil)
                    self?.toolbarPanel = nil
                }
            })
        }
        if let s = selectionPanel {
            s.orderOut(nil)
            selectionPanel = nil
        }
    }

    func hideImmediately() {
        removeKeyMonitor()
        toolbarPanel?.orderOut(nil)
        toolbarPanel = nil
        selectionPanel?.orderOut(nil)
        selectionPanel = nil
    }

    // MARK: - Actions
    func presentAreaSelection(isIT: Bool) {
        toolbarPanel?.orderOut(nil)
        toolbarPanel = nil
        removeKeyMonitor()

        presentSelection(
            prompt: isIT ? "Trascina per selezionare l'area da catturare" : "Drag to select screenshot area",
            isIT: isIT
        ) { rect in
            ScreenCaptureManager.shared.captureAreaScreenshot(rect: rect, isIT: isIT)
        }
    }

    func presentScrollingSelection(isIT: Bool) {
        toolbarPanel?.orderOut(nil)
        toolbarPanel = nil
        removeKeyMonitor()

        presentSelection(
            prompt: isIT ? "Trascina per selezionare l'area di scorrimento (o Invio per tutto lo schermo)" : "Drag to select scroll area (or Enter for full screen)",
            isIT: isIT
        ) { rect in
            ScreenCaptureManager.shared.beginScrollingCaptureSession(rect: rect, isIT: isIT)
        }
    }

    func handleToggleRecord(isIT: Bool) {
        if ScreenCaptureManager.shared.isRecordingVideo {
            hideImmediately()
            ScreenCaptureManager.shared.stopVideoRecording()
        } else {
            toolbarPanel?.orderOut(nil)
            toolbarPanel = nil
            removeKeyMonitor()

            presentSelection(
                prompt: isIT ? "Trascina per selezionare l'area da registrare (o Invio per tutto lo schermo)" : "Drag to select recording area (or Enter for full screen)",
                isIT: isIT
            ) { rect in
                if let screen = NSScreen.main,
                   abs(rect.width - screen.frame.width) < 15 && abs(rect.height - screen.frame.height) < 15 {
                    ScreenCaptureManager.shared.startVideoRecording(area: nil)
                } else {
                    ScreenCaptureManager.shared.startVideoRecording(area: rect)
                }
            }
        }
    }

    private func presentSelection(prompt: String, isIT: Bool, onSelected: @escaping (CGRect) -> Void) {
        guard let screen = NSScreen.main else { return }

        let panel = SelectionOverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let rootView = SelectionOverlayView(
            prompt: prompt,
            isIT: isIT,
            onSelected: { [weak self] rect in
                self?.hideImmediately()
                onSelected(rect)
            },
            onCancel: { [weak self] in
                self?.hideImmediately()
                self?.show(isIT: isIT)
            }
        )

        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = screen.frame
        panel.contentView = hosting
        panel.setFrame(screen.frame, display: true)

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.selectionPanel = panel

        removeKeyMonitor()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.selectionPanel != nil else { return event }

            if event.keyCode == 53 { // Esc: cancel back to toolbar
                self.hideImmediately()
                self.show(isIT: isIT)
                return nil
            }
            if event.keyCode == 36 || event.keyCode == 49 { // Return or Space: full screen
                self.hideImmediately()
                if let s = NSScreen.main {
                    onSelected(s.frame)
                }
                return nil
            }
            return event
        }
    }

    private func installToolbarKeyMonitor(isIT: Bool) {
        removeKeyMonitor()

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.toolbarPanel != nil else { return event }

            if event.keyCode == 53 { // Escape
                self.hide()
                return nil
            }

            switch event.characters {
            case "1":
                self.presentAreaSelection(isIT: isIT)
                return nil
            case "2":
                self.hideImmediately()
                ScreenCaptureManager.shared.captureFullScreenScreenshot(isIT: isIT)
                return nil
            case "3":
                self.presentScrollingSelection(isIT: isIT)
                return nil
            case "4":
                self.handleToggleRecord(isIT: isIT)
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }

    private func dismissMenuBarPopovers() {
        for win in NSApp.windows where win !== self.toolbarPanel && win !== self.selectionPanel {
            let className = win.className
            if className.contains("MenuBarExtra") || className.contains("StatusBar") || className.contains("Popover") {
                win.orderOut(nil)
            }
        }
    }
}
