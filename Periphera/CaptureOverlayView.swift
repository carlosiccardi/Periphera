//
//  CaptureOverlayView.swift
//  Periphera
//
//  Created by Carlo Siccardi on 25/10/2026.
//

import SwiftUI
import AppKit

// MARK: - Native AppKit Drag Handle
final class WindowDragHandleView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}

struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragHandleView {
        WindowDragHandleView()
    }
    func updateNSView(_ nsView: WindowDragHandleView, context: Context) {}
}

// MARK: - Floating Toolbar View
struct CaptureToolbarView: View {
    let isIT: Bool
    let isRecording: Bool
    let onSelectArea: () -> Void
    let onFullScreen: () -> Void
    let onScrolling: () -> Void
    let onToggleRecord: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Drag Handle: uses native WindowServer performDrag for silky-smooth 100% crash-proof movement
            WindowDragHandle()
                .frame(width: 24, height: 36)
                .overlay(
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                )
                .help(isIT ? "Trascina per spostare la barra" : "Drag to move toolbar")

            // 1. Ritaglio Area
            ToolbarButton(
                title: isIT ? "Ritaglio Area" : "Select Area",
                icon: "crop",
                shortcutKey: "1",
                action: onSelectArea
            )

            // 2. Schermo Intero
            ToolbarButton(
                title: isIT ? "Schermo Intero" : "Full Screen",
                icon: "display",
                shortcutKey: "2",
                action: onFullScreen
            )

            // 3. Screenshot a Scorrimento
            ToolbarButton(
                title: isIT ? "Screenshot a Scorrimento" : "Scrolling Screenshot",
                icon: "arrow.up.and.down.text.horizontal",
                accentColor: .blue,
                shortcutKey: "3",
                action: onScrolling
            )

            // 4. Registra Schermo
            ToolbarButton(
                title: isRecording
                    ? (isIT ? "Ferma REC" : "Stop REC")
                    : (isIT ? "Registra Schermo" : "Record Screen"),
                icon: isRecording ? "stop.circle.fill" : "record.circle",
                accentColor: .red,
                isHighlighted: isRecording,
                shortcutKey: "4",
                action: onToggleRecord
            )

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
        .padding(14)
    }
}

// MARK: - Fullscreen Selection Overlay View
struct SelectionOverlayView: View {
    let prompt: String
    let isIT: Bool
    let onSelected: (CGRect) -> Void
    let onCancel: () -> Void

    @State private var startPoint: CGPoint?
    @State private var currentPoint: CGPoint?

    private var selectionRect: CGRect? {
        guard let s = startPoint, let c = currentPoint else { return nil }
        let x = min(s.x, c.x)
        let y = min(s.y, c.y)
        let w = abs(c.x - s.x)
        let h = abs(c.y - s.y)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // Dimmed backdrop with cutout for the selection rect
                if let rect = selectionRect, rect.width > 2 && rect.height > 2 {
                    // Dim surrounding area
                    Path { path in
                        path.addRect(CGRect(origin: .zero, size: geometry.size))
                        path.addRect(rect)
                    }
                    .fill(Color.black.opacity(0.40), style: FillStyle(eoFill: true))

                    // Selection Border
                    Rectangle()
                        .strokeBorder(Color.white, lineWidth: 1.5)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)

                    // Dimensions Badge
                    HStack(spacing: 3) {
                        Text("\(Int(rect.width)) × \(Int(rect.height)) px")
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.black.opacity(0.85))
                    )
                    .offset(x: rect.minX, y: max(0, rect.minY - 24))
                } else {
                    Color.black.opacity(0.35)
                        .edgesIgnoringSafeArea(.all)
                }

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
                        if startPoint == nil {
                            startPoint = value.startLocation
                        }
                        currentPoint = value.location
                    }
                    .onEnded { _ in
                        guard let rect = selectionRect, rect.width > 12, rect.height > 12 else {
                            // If just clicked without drag, select full screen
                            onSelected(CGRect(origin: .zero, size: geometry.size))
                            return
                        }
                        onSelected(rect)
                    }
            )
        }
    }
}

// MARK: - Reusable Toolbar Button
struct ToolbarButton: View {
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
