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

        // Give the window generous margins around the 260pt card so the soft drop shadow
        // never clips against window boundaries (which caused the dark edge residue).
        let windowW: CGFloat = 296
        let windowH: CGFloat = 360
        let margin: CGFloat = 16

        let x = screen.frame.maxX - windowW - margin
        let y = screen.visibleFrame.minY + margin

        let overlayPanel = QuickAccessPanel(
            contentRect: NSRect(x: x, y: y, width: windowW, height: windowH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        overlayPanel.level = .floating
        overlayPanel.isOpaque = false
        overlayPanel.backgroundColor = .clear
        overlayPanel.hasShadow = false // Handled cleanly with padding in SwiftUI to prevent double shadow artifacts
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

        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(x: 0, y: 0, width: windowW, height: windowH)
        overlayPanel.contentView = hosting
        overlayPanel.alphaValue = 0
        overlayPanel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.20
            overlayPanel.animator().alphaValue = 1.0
        }

        self.panel = overlayPanel

        // Auto-dismiss after 15 seconds
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
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
            context.duration = 0.16
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                p.close()
                self?.panel = nil
            }
        })
    }
}

// MARK: - Clean SwiftUI View for Quick Access Overlay
private struct QuickAccessOverlayView: View {
    let image: NSImage
    let fileURL: URL
    let dimensions: CGSize
    let isIT: Bool
    let onClose: () -> Void

    @State private var hasCopied: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11.5, weight: .bold))
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

            // Image Preview (Clean container with no black borders/residues)
            ScrollView(.vertical, showsIndicators: false) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                    )
            }
            .frame(maxHeight: 185)
            .padding(.horizontal, 10)
            .onDrag {
                NSItemProvider(contentsOf: fileURL) ?? NSItemProvider(object: image)
            }
            .help(isIT ? "Trascina l'immagine per condividerla" : "Drag image to share anywhere")

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
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.8)
                )
        )
        // Soft drop shadow with sufficient margin so it fades out without edge clipping
        .shadow(color: .black.opacity(0.22), radius: 14, x: 0, y: 6)
        .padding(18)
    }
}
