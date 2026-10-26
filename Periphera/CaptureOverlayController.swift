//
//  CaptureOverlayController.swift
//  Periphera
//
//  Created by Carlo Siccardi on 25/10/2026.
//

import Cocoa
import SwiftUI

final class CaptureOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class CaptureOverlayController {
    static let shared = CaptureOverlayController()

    private var window: CaptureOverlayPanel?
    private var localKeyMonitor: Any?
    var mode: CaptureOverlayMode = .toolbar

    var isVisible: Bool {
        window?.isVisible ?? false
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
        // 1. Close MenuBarExtra / Popovers
        dismissMenuBarPopovers()

        guard let screen = NSScreen.main else { return }

        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        mode = .toolbar

        let panel = CaptureOverlayPanel(
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

        let bindingMode = Binding<CaptureOverlayMode>(
            get: { self.mode },
            set: { self.mode = $0 }
        )

        let rootView = CaptureOverlayView(
            captureManager: ScreenCaptureManager.shared,
            isIT: isIT,
            mode: bindingMode
        ) { [weak self] in
            self?.hide()
        }

        panel.contentView = NSHostingView(rootView: rootView)
        panel.setFrame(screen.frame, display: true)

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        panel.animator().alphaValue = 1.0

        NSApp.activate(ignoringOtherApps: true)
        self.window = panel

        // 2. Install keyboard shortcuts
        installKeyMonitor(isIT: isIT)
    }

    func hide() {
        removeKeyMonitor()

        guard let win = window else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            win.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            win.orderOut(nil)
            self?.window = nil
        })
    }

    func hideImmediately() {
        removeKeyMonitor()
        if let win = window {
            win.orderOut(nil)
            self.window = nil
        }
    }

    private func installKeyMonitor(isIT: Bool) {
        removeKeyMonitor()

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }

            // Escape closes overlay
            if event.keyCode == 53 {
                self.hide()
                return nil
            }

            // In selection mode, Return or Space selects full screen
            if case .selection(_, let onSelected) = self.mode {
                if event.keyCode == 36 || event.keyCode == 49 { // Return or Space
                    self.hideImmediately()
                    if let screen = NSScreen.main {
                        onSelected(screen.frame)
                    }
                    return nil
                }
                return event
            }

            // Hotkeys while toolbar is visible
            switch event.characters {
            case "1":
                self.mode = .selection(
                    prompt: isIT ? "Trascina per selezionare l'area da catturare" : "Drag to select screenshot area",
                    onSelected: { rect in
                        self.hideImmediately()
                        if let rect {
                            ScreenCaptureManager.shared.captureAreaScreenshot(rect: rect)
                        }
                    }
                )
                return nil

            case "2":
                self.hideImmediately()
                ScreenCaptureManager.shared.captureFullScreenScreenshot()
                return nil

            case "3":
                self.mode = .selection(
                    prompt: isIT ? "Trascina per selezionare l'area di scorrimento (o Invio per tutto lo schermo)" : "Drag to select scroll area (or Enter for full screen)",
                    onSelected: { rect in
                        self.hideImmediately()
                        if let rect {
                            ScreenCaptureManager.shared.beginScrollingCaptureSession(rect: rect, isIT: isIT)
                        }
                    }
                )
                return nil

            case "4":
                if ScreenCaptureManager.shared.isRecordingVideo {
                    self.hideImmediately()
                    ScreenCaptureManager.shared.stopVideoRecording()
                } else {
                    self.mode = .selection(
                        prompt: isIT
                            ? "Trascina per selezionare l'area da registrare (o Invio per tutto lo schermo)"
                            : "Drag to select recording area (or Enter for full screen)",
                        onSelected: { rect in
                            self.hideImmediately()
                            if let rect {
                                if let screen = NSScreen.main,
                                   abs(rect.width - screen.frame.width) < 15 && abs(rect.height - screen.frame.height) < 15 {
                                    ScreenCaptureManager.shared.startVideoRecording(area: nil)
                                } else {
                                    ScreenCaptureManager.shared.startVideoRecording(area: rect)
                                }
                            }
                        }
                    )
                }
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
        for win in NSApp.windows where win !== self.window {
            let className = win.className
            if className.contains("MenuBarExtra") || className.contains("StatusBar") || className.contains("Popover") {
                win.orderOut(nil)
            }
        }
    }
}
