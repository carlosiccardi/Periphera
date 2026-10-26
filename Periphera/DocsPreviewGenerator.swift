//
//  DocsPreviewGenerator.swift
//  Periphera
//
//  Created by Carlo Siccardi on 26/10/2026.
//

import Cocoa
import SwiftUI

@MainActor
enum DocsPreviewGenerator {
    static func generateAll() {
        let docsURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("docs")
        try? FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)

        let engine = ScrollEngine()
        engine.setAccessibilityGrantedForPreview(true)
        engine.language = .en
        engine.trackpadNatural = true
        engine.mouseNatural = false
        engine.isEnabled = true

        let displayManager = DisplayManager()
        displayManager.setExternalDisplaysForPreview([
            ExternalDisplayInfo(id: 1, name: "LG UltraFine 4K")
        ])
        displayManager.brightness = 75.0

        let caffeineManager = CaffeineManager.shared
        let captureManager = ScreenCaptureManager.shared

        // 1. Minimal Popover View (v5)
        let minimalView = ContentView(
            engine: engine,
            displayManager: displayManager,
            caffeineManager: caffeineManager,
            captureManager: captureManager,
            batteryManager: BatteryManager.shared,
            showMouseSpeedTuning: false,
            showTrackpadPreview: false,
            showMousePreview: false,
            showBatteryDetails: false
        )
        saveRenderedView(
            view: PopoverCardWrapper { minimalView },
            to: docsURL.appendingPathComponent("preview-minimal-v5.png")
        )

        // 1b. Battery AlDente Expanded View (v5)
        let batteryExpandedView = ContentView(
            engine: engine,
            displayManager: displayManager,
            caffeineManager: caffeineManager,
            captureManager: captureManager,
            batteryManager: BatteryManager.shared,
            showMouseSpeedTuning: false,
            showTrackpadPreview: false,
            showMousePreview: false,
            showBatteryDetails: true
        )
        saveRenderedView(
            view: PopoverCardWrapper { batteryExpandedView },
            to: docsURL.appendingPathComponent("preview-battery-aldente-v5.png")
        )

        // 2. Interactive Simulator View (v5)
        let simulatorView = ContentView(
            engine: engine,
            displayManager: displayManager,
            caffeineManager: caffeineManager,
            captureManager: captureManager,
            batteryManager: BatteryManager.shared,
            showMouseSpeedTuning: false,
            showTrackpadPreview: true,
            showMousePreview: false,
            showBatteryDetails: false
        )
        saveRenderedView(
            view: PopoverCardWrapper { simulatorView },
            to: docsURL.appendingPathComponent("preview-simulator-v5.png")
        )

        // 3. Floating Draggable Capture Bar (v5)
        let captureBarView = FloatingCaptureBarMockView()
        saveRenderedView(
            view: PopoverCardWrapper { captureBarView },
            to: docsURL.appendingPathComponent("preview-capture-bar-v5.png")
        )

        // 4. CleanShot X-Style Scrolling Screenshot & Quick Access Overlay (v5)
        let quickAccessView = QuickAccessMockView()
        saveRenderedView(
            view: PopoverCardWrapper { quickAccessView },
            to: docsURL.appendingPathComponent("preview-quick-access-v5.png")
        )

        print("📸 All docs preview images generated successfully in \(docsURL.path)!")
    }

    private static func saveRenderedView<V: View>(view: V, to url: URL) {
        let hostingView = NSHostingView(rootView: view)
        let fittingSize = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: fittingSize)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: fittingSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            print("Failed to cache display for \(url.lastPathComponent)")
            return
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            print("Failed to get PNG data for \(url.lastPathComponent)")
            return
        }

        do {
            try pngData.write(to: url)
            print("Saved: \(url.lastPathComponent) (\(bitmap.pixelsWide) × \(bitmap.pixelsHigh) px)")
        } catch {
            print("Error writing \(url.lastPathComponent): \(error)")
        }
    }
}

// MARK: - Wrappers and Mock Views for Documentation
private struct PopoverCardWrapper<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                    )
            )
            .shadow(color: .black.opacity(0.28), radius: 24, x: 0, y: 12)
            .padding(24)
            .preferredColorScheme(.dark)
    }
}

private struct FloatingCaptureBarMockView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 24, height: 36)

            MockToolbarButton(title: "Select Area", icon: "crop", shortcut: "1")
            MockToolbarButton(title: "Full Screen", icon: "display", shortcut: "2")
            MockToolbarButton(title: "Scrolling Screenshot", icon: "arrow.up.and.down.text.horizontal", shortcut: "3", accent: .blue)
            MockToolbarButton(title: "Record Screen", icon: "record.circle", shortcut: "4", accent: .red)

            Divider()
                .frame(height: 20)
                .opacity(0.35)

            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary.opacity(0.06)))
                .padding(.trailing, 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                )
        )
        .frame(height: 52)
    }
}

private struct MockToolbarButton: View {
    let title: String
    let icon: String
    let shortcut: String
    var accent: Color = .primary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(accent == .primary ? .secondary : accent)

            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(accent == .primary ? .primary : accent)

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
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accent == .primary ? Color.clear : accent.opacity(0.12))
        )
    }
}

private struct QuickAccessMockView: View {
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Capture complete")
                        .font(.system(size: 11, weight: .semibold))
                    Text("1440 × 3820 px")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)

            // Simulated web page preview
            ZStack {
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue.opacity(0.7))
                        .frame(height: 20)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.15))
                        .frame(height: 12)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.10))
                        .frame(height: 35)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.teal.opacity(0.4))
                        .frame(height: 45)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.10))
                        .frame(height: 25)
                }
                .padding(8)
            }
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
            )
            .padding(.horizontal, 10)

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .medium))
                    Text("Copied")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5.5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.green.opacity(0.18)))
                .foregroundStyle(Color.green)

                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 10, weight: .medium))
                    Text("Finder")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5.5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
                .foregroundStyle(.primary)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .frame(width: 250)
    }
}
