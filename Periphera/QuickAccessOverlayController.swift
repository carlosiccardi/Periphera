//
//  QuickAccessOverlayController.swift
//  Periphera
//
//  Created by Carlo Siccardi on 26/10/2026.
//

import Cocoa
import SwiftUI

final class QuickAccessPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class QuickAccessOverlayController {
    static let shared = QuickAccessOverlayController()

    private var panel: QuickAccessPanel?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(image: NSImage, fileURL: URL, dimensions: CGSize, isIT: Bool) {
        dismissTask?.cancel()
        panel?.close()

        guard let screen = NSScreen.main else { return }

        let panelW: CGFloat = 260
        let panelH: CGFloat = 320
        let padding: CGFloat = 20

        let x = screen.frame.maxX - panelW - padding
        let y = screen.visibleFrame.minY + padding

        let overlayPanel = QuickAccessPanel(
            contentRect: NSRect(x: x, y: y, width: panelW, height: panelH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        overlayPanel.level = .floating
        overlayPanel.isOpaque = false
        overlayPanel.backgroundColor = .clear
        overlayPanel.hasShadow = true
        overlayPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let rootView = QuickAccessOverlayView(
            image: image,
            fileURL: fileURL,
            dimensions: dimensions,
            isIT: isIT,
            onClose: { [weak self] in
                self?.hide()
            }
        )

        overlayPanel.contentView = NSHostingView(rootView: rootView)
        overlayPanel.alphaValue = 0
        overlayPanel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            overlayPanel.animator().alphaValue = 1.0
        }

        self.panel = overlayPanel

        // Auto-dismiss after 14 seconds
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 14_000_000_000)
            if !Task.isCancelled {
                self?.hide()
            }
        }
    }

    func hide() {
        dismissTask?.cancel()
        dismissTask = nil
        guard let p = panel else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                p.close()
                self?.panel = nil
            }
        })
    }
}

// MARK: - SwiftUI View for CleanShot X-Style Quick Access Overlay
private struct QuickAccessOverlayView: View {
    let image: NSImage
    let fileURL: URL
    let dimensions: CGSize
    let isIT: Bool
    let onClose: () -> Void

    @State private var hasCopied: Bool = false
    @State private var isHovered: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 1) {
                    Text(isIT ? "Cattura completata" : "Capture complete")
                        .font(.system(size: 11, weight: .semibold))
                    Text("\(Int(dimensions.width)) × \(Int(dimensions.height)) px")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)

            // Image Preview (Draggable into other apps)
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.05))

                ScrollView(.vertical, showsIndicators: true) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(4)
                }
                .frame(maxHeight: 185)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .onDrag {
                    NSItemProvider(contentsOf: fileURL) ?? NSItemProvider(object: image)
                }
                .help(isIT ? "Trascina l'immagine per condividerla" : "Drag image to share anywhere")
            }
            .padding(.horizontal, 10)

            // Action Buttons Bar
            HStack(spacing: 8) {
                // Copy Button
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.writeObjects([image])
                    hasCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        hasCopied = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: hasCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .medium))
                        Text(hasCopied ? (isIT ? "Copiato" : "Copied") : (isIT ? "Copia" : "Copy"))
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5.5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(hasCopied ? Color.green.opacity(0.18) : Color.primary.opacity(0.08))
                    )
                    .foregroundStyle(hasCopied ? Color.green : Color.primary)
                }
                .buttonStyle(.plain)

                // Finder Button
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 10, weight: .medium))
                        Text(isIT ? "Finder" : "Finder")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5.5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    )
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.8)
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 8)
        .frame(width: 260)
        .onHover { isHovered = $0 }
    }
}
