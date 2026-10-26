//
//  CaptureOverlayView.swift
//  Periphera
//
//  Created by Carlo Siccardi on 25/10/2026.
//

import SwiftUI

enum CaptureOverlayMode {
    case toolbar
    case selection(prompt: String, onSelected: (CGRect?) -> Void)
}

struct CaptureOverlayView: View {
    @Bindable var captureManager: ScreenCaptureManager
    let isIT: Bool
    @Binding var mode: CaptureOverlayMode
    let onClose: () -> Void

    // Drag position for the floating toolbar
    @State private var barOffset: CGSize = .zero
    @State private var dragStartOffset: CGSize = .zero

    // Selection mode drag coordinates
    @State private var selStart: CGPoint?
    @State private var selCurrent: CGPoint?

    private var currentSelectionRect: CGRect? {
        guard let start = selStart, let current = selCurrent else { return nil }
        let x = min(start.x, current.x)
        let y = min(start.y, current.y)
        let w = abs(current.x - start.x)
        let h = abs(current.y - start.y)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 1. Dark dimmed backdrop
                Color.black.opacity(0.42)
                    .edgesIgnoringSafeArea(.all)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if case .toolbar = mode {
                            onClose()
                        }
                    }

                // 2. Main Content based on Mode
                switch mode {
                case .toolbar:
                    floatingToolbar
                        .offset(x: barOffset.width, y: barOffset.height)
                        // Absorb clicks so toolbar clicks don't hit the dark backdrop
                        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

                case .selection(let prompt, let onSelected):
                    selectionLayer(prompt: prompt, geometry: geometry, onSelected: onSelected)
                }
            }
        }
    }

    // MARK: - Floating Toolbar
    private var floatingToolbar: some View {
        HStack(spacing: 8) {
            // Drag Handle: only this grip has DragGesture so buttons receive clicks freely
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 24, height: 36)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            barOffset = CGSize(
                                width: dragStartOffset.width + value.translation.width,
                                height: dragStartOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            dragStartOffset = barOffset
                        }
                )
                .onHover { isHover in
                    if isHover {
                        NSCursor.openHand.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                }
                .help(isIT ? "Trascina per spostare la barra" : "Drag to move toolbar")

            // 1. Ritaglio Area: immediate interactive crosshairs capture
            ToolbarButton(
                title: isIT ? "Ritaglio Area" : "Select Area",
                icon: "crop",
                shortcutKey: "1"
            ) {
                onClose()
                captureManager.captureAreaScreenshot()
            }

            // 2. Schermo Intero: immediate fullscreen screenshot
            ToolbarButton(
                title: isIT ? "Schermo Intero" : "Full Screen",
                icon: "display",
                shortcutKey: "2"
            ) {
                onClose()
                captureManager.captureFullScreenScreenshot()
            }

            // 3. Screenshot a Scorrimento: choose area, then scroll & stitch into PNG
            ToolbarButton(
                title: isIT ? "Screenshot a Scorrimento" : "Scrolling Screenshot",
                icon: "arrow.up.and.down.text.horizontal",
                accentColor: .blue,
                shortcutKey: "3"
            ) {
                NSCursor.crosshair.set()
                mode = .selection(
                    prompt: isIT
                        ? "Trascina per selezionare l'area di scorrimento (o Invio per tutto lo schermo)"
                        : "Drag to select scroll area (or Enter for full screen)",
                    onSelected: { rect in
                        CaptureOverlayController.shared.hideImmediately()
                        if let rect {
                            captureManager.beginScrollingCaptureSession(rect: rect, isIT: isIT)
                        }
                    }
                )
            }

            // 4. Registra Schermo (Scelta Schermo Intero o Porzione)
            ToolbarButton(
                title: captureManager.isRecordingVideo
                    ? (isIT ? "Ferma REC" : "Stop REC")
                    : (isIT ? "Registra Schermo" : "Record Screen"),
                icon: captureManager.isRecordingVideo ? "stop.circle.fill" : "record.circle",
                accentColor: .red,
                isHighlighted: captureManager.isRecordingVideo,
                shortcutKey: "4"
            ) {
                if captureManager.isRecordingVideo {
                    onClose()
                    captureManager.stopVideoRecording()
                } else {
                    NSCursor.crosshair.set()
                    mode = .selection(
                        prompt: isIT
                            ? "Trascina per selezionare l'area da registrare (o Invio per tutto lo schermo)"
                            : "Drag to select recording area (or Enter for full screen)",
                        onSelected: { rect in
                            CaptureOverlayController.shared.hideImmediately()
                            if let rect {
                                if let screen = NSScreen.main,
                                   abs(rect.width - screen.frame.width) < 15 && abs(rect.height - screen.frame.height) < 15 {
                                    captureManager.startVideoRecording(area: nil)
                                } else {
                                    captureManager.startVideoRecording(area: rect)
                                }
                            }
                        }
                    )
                }
            }

            Divider()
                .frame(height: 20)
                .opacity(0.35)

            // Close (Esc)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            .help(isIT ? "Chiudi (Esc)" : "Close (Esc)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                )
        )
        .shadow(color: .black.opacity(0.28), radius: 24, x: 0, y: 10)
        .frame(height: 52)
    }

    // MARK: - Interactive Selection Layer
    private func selectionLayer(prompt: String, geometry: GeometryProxy, onSelected: @escaping (CGRect?) -> Void) -> some View {
        ZStack(alignment: .topLeading) {
            // Instruction Banner at Top
            HStack(spacing: 8) {
                Image(systemName: "crop")
                    .font(.system(size: 12.5, weight: .semibold))
                Text(prompt)
                    .font(.system(size: 12.5, weight: .medium))
                Text("•")
                    .foregroundStyle(.secondary)
                Text(isIT ? "Invio: Schermo intero  |  Esc: Annulla" : "Enter: Full screen  |  Esc: Cancel")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.8)
                    )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 40)

            // Selection box cutout & dimensions badge
            if let rect = currentSelectionRect, rect.width > 2 && rect.height > 2 {
                Rectangle()
                    .fill(Color.white.opacity(0.04))
                    .frame(width: rect.width, height: rect.height)
                    .overlay(
                        Rectangle()
                            .strokeBorder(Color.white, lineWidth: 1.5)
                    )
                    .offset(x: rect.minX, y: rect.minY)

                Text("\(Int(rect.width)) × \(Int(rect.height)) px")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.black.opacity(0.80))
                    )
                    .offset(x: rect.minX, y: max(0, rect.minY - 24))
            }
        }
        .contentShape(Rectangle())
        .onAppear {
            NSCursor.crosshair.push()
        }
        .onDisappear {
            NSCursor.pop()
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if selStart == nil {
                        selStart = value.startLocation
                    }
                    selCurrent = value.location
                }
                .onEnded { value in
                    guard let rect = currentSelectionRect, rect.width > 12, rect.height > 12 else {
                        completeWithFullScreen(geometry: geometry, onSelected: onSelected)
                        return
                    }

                    if let screen = NSScreen.main {
                        let screenH = screen.frame.height
                        let cocoaY = screenH - (rect.origin.y + rect.height)
                        let finalRect = CGRect(x: rect.origin.x, y: cocoaY, width: rect.width, height: rect.height)
                        CaptureOverlayController.shared.hideImmediately()
                        onSelected(finalRect)
                    } else {
                        CaptureOverlayController.shared.hideImmediately()
                        onSelected(rect)
                    }
                }
        )
    }

    private func completeWithFullScreen(geometry: GeometryProxy, onSelected: (CGRect?) -> Void) {
        CaptureOverlayController.shared.hideImmediately()
        if let screen = NSScreen.main {
            onSelected(screen.frame)
        } else {
            onSelected(CGRect(origin: .zero, size: geometry.size))
        }
    }
}

// MARK: - Reusable Toolbar Button
private struct ToolbarButton: View {
    let title: String
    let icon: String
    var accentColor: Color = .primary
    var isHighlighted: Bool = false
    var shortcutKey: String? = nil
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(isHighlighted ? accentColor : (isHovered ? .primary : .secondary))

                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(isHighlighted ? accentColor : (isHovered ? .primary : .secondary))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if let shortcut = shortcutKey {
                    Text(shortcut)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHighlighted ? accentColor.opacity(0.14) : (isHovered ? Color.primary.opacity(0.08) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
