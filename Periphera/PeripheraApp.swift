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

        let canvasSize = NSSize(width: 18, height: 18)
        let config = NSImage.SymbolConfiguration(pointSize: 13.5, weight: .medium, scale: .medium)
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Periphera")?
            .withSymbolConfiguration(config) else {
            return NSImage()
        }

        let image = NSImage(size: canvasSize, flipped: false) { rect in
            // Fit proportionally inside a 15.5 x 15.5 box centered in the 18 x 18 Menu Bar canvas
            // so the top and bottom borders are never clipped by macOS MenuBarExtra.
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
