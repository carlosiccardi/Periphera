//
//  GlobalHotKeyManager.swift
//  Periphera
//
//  Created by Carlo Siccardi on 25/10/2026.
//

import Cocoa
import Carbon

final class GlobalHotKeyManager: @unchecked Sendable {
    static let shared = GlobalHotKeyManager()

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?

    private init() {}

    func registerDefaultHotKeys() {
        unregisterAll()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, _) -> OSStatus in
                Task { @MainActor in
                    CaptureOverlayController.shared.toggle()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )

        guard handlerStatus == noErr else {
            print("Failed to install Carbon event handler: \(handlerStatus)")
            return
        }

        // Register Cmd + Shift + 6 (Key code for '6' is 22 / 0x16)
        registerHotKey(keyCode: 22, modifiers: UInt32(cmdKey | shiftKey), id: 1)

        // Register Cmd + Shift + P (Key code for 'P' is 35 / 0x23)
        registerHotKey(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey | shiftKey), id: 2)
    }

    private func registerHotKey(keyCode: UInt32, modifiers: UInt32, id: UInt32) {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x50455249), id: id) // "PERI"
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr, let ref = hotKeyRef {
            hotKeyRefs.append(ref)
        }
    }

    func unregisterAll() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()

        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    deinit {
        unregisterAll()
    }
}
