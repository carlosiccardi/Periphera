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
        // Ensure the app never appears in the Dock or Cmd+Tab app switcher
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct PeripheraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var engine = ScrollEngine()
    @State private var displayManager = DisplayManager()

    var body: some Scene {
        MenuBarExtra {
            ContentView(engine: engine, displayManager: displayManager)
        } label: {
            Image(
                nsImage: Self.makeMenuBarIcon(
                    isEnabled: engine.isEnabled,
                    isTrusted: engine.isAccessibilityGranted
                )
            )
        }
        .menuBarExtraStyle(.window)
    }

    private static func makeMenuBarIcon(isEnabled: Bool, isTrusted: Bool) -> NSImage {
        let symbolName = !isTrusted
            ? "exclamationmark.shield"
            : "slider.horizontal.2.square"

        let config = NSImage.SymbolConfiguration(pointSize: 16.5, weight: .medium, scale: .large)
        guard let baseImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Periphera")?
            .withSymbolConfiguration(config) else {
            return NSImage()
        }

        if isEnabled {
            baseImage.isTemplate = true
            return baseImage
        } else {
            let size = baseImage.size
            let dimmed = NSImage(size: size, flipped: false) { rect in
                baseImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.45)
                return true
            }
            dimmed.isTemplate = true
            return dimmed
        }
    }
}
