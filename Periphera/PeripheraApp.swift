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
            MenuBarStatusIcon(
                isEnabled: engine.isEnabled,
                isTrusted: engine.isAccessibilityGranted
            )
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarStatusIcon: View {
    let isEnabled: Bool
    let isTrusted: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(
                systemName: !isTrusted
                    ? "exclamationmark.shield"
                    : "slider.horizontal.2.square"
            )
            .symbolRenderingMode(.hierarchical)
            .opacity(isEnabled ? 1.0 : 0.45)
        }
    }
}
