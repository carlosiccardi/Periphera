//
//  PeripheraApp.swift
//  Periphera
//
//  Created by Carlo Siccardi on 19/10/2026.
//

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--generate-previews") {
            DocsPreviewGenerator.generateAll()
            NSApp.terminate(nil)
            return
        }

        // Ensure the app never appears in the Dock or Cmd+Tab app switcher
        NSApp.setActivationPolicy(.accessory)

        // Register global shortcuts: ⌘ + ⇧ + 6 and ⌘ + ⇧ + P
        GlobalHotKeyManager.shared.registerDefaultHotKeys()
    }
}

@main
struct PeripheraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var engine = ScrollEngine()
    @State private var displayManager = DisplayManager()
    @State private var caffeineManager = CaffeineManager.shared
    @State private var captureManager = ScreenCaptureManager.shared
    @State private var batteryManager = BatteryManager.shared

    var body: some Scene {
        MenuBarExtra {
            ContentView(
                engine: engine,
                displayManager: displayManager,
                caffeineManager: caffeineManager,
                captureManager: captureManager,
                batteryManager: batteryManager
            )
        } label: {
            Image(
                nsImage: Self.makeMenuBarIcon(
                    isEnabled: engine.isEnabled,
                    isTrusted: engine.isAccessibilityGranted,
                    isCaffeineActive: caffeineManager.isActive,
                    isRecording: captureManager.isRecordingVideo
                )
            )
        }
        .menuBarExtraStyle(.window)
    }

    private static func makeMenuBarIcon(
        isEnabled: Bool,
        isTrusted: Bool,
        isCaffeineActive: Bool,
        isRecording: Bool
    ) -> NSImage {
        let symbolName: String
        if !isTrusted {
            symbolName = "exclamationmark.shield"
        } else if isRecording {
            symbolName = "record.circle.fill"
        } else if isCaffeineActive {
            symbolName = "cup.and.saucer.fill"
        } else {
            symbolName = "slider.horizontal.2.square"
        }

        let canvasSize = NSSize(width: 18, height: 18)
        let config = NSImage.SymbolConfiguration(pointSize: 13.5, weight: .medium, scale: .medium)
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Periphera")?
            .withSymbolConfiguration(config) else {
            return NSImage()
        }

        let image = NSImage(size: canvasSize, flipped: false) { rect in
            let maxDim: CGFloat = 15.5
            let symSize = symbol.size
            let scale = min(maxDim / max(symSize.width, 1), maxDim / max(symSize.height, 1))
            let drawW = symSize.width * scale
            let drawH = symSize.height * scale
            let drawRect = NSRect(
                x: (rect.width - drawW) / 2.0,
                y: (rect.height - drawH) / 2.0,
                width: drawW,
                height: drawH
            )
            symbol.draw(
                in: drawRect,
                from: .zero,
                operation: .sourceOver,
                fraction: isEnabled ? 1.0 : 0.45
            )
            return true
        }
        image.isTemplate = true
        return image
    }
}
