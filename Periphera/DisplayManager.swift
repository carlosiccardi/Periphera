//
//  DisplayManager.swift
//  Periphera
//
//  Created by Carlo Siccardi on 20/10/2026.
//

import Foundation
import AppKit
import CoreGraphics
import IOKit
import Observation

private typealias IOAVServiceRef = CFTypeRef

@_silgen_name("IOAVServiceCreateWithService")
private nonisolated func IOAVServiceCreateWithService(
    _ allocator: CFAllocator?,
    _ service: io_service_t
) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOAVServiceWriteI2C")
private nonisolated func IOAVServiceWriteI2C(
    _ service: IOAVServiceRef,
    _ chipAddress: UInt32,
    _ dataAddress: UInt32,
    _ inputBuffer: UnsafeMutableRawPointer,
    _ inputBufferSize: UInt32
) -> IOReturn

struct ExternalDisplayInfo: Identifiable, Equatable, Sendable {
    let id: CGDirectDisplayID
    let name: String
}

@Observable
@MainActor
final class DisplayManager {
    private(set) var externalDisplays: [ExternalDisplayInfo] = []

    /// Brightness percentage (10% ... 100%)
    var brightness: Double {
        didSet {
            let clamped = min(max(brightness, 10.0), 100.0)
            if clamped != brightness {
                brightness = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: Self.brightnessKey)
            applyBrightness(clamped)
        }
    }

    var hasExternalDisplay: Bool {
        !externalDisplays.isEmpty
    }

    var primaryExternalName: String? {
        externalDisplays.first?.name
    }

    private static let brightnessKey = "periphera.externalBrightness"
    private var ddcQueue = DispatchQueue(label: "com.paolosiccardi.Periphera.ddc", qos: .userInteractive)
    private var lastDDCWriteTime: CFAbsoluteTime = 0

    init() {
        let saved = UserDefaults.standard.double(forKey: Self.brightnessKey)
        self.brightness = (saved >= 10.0 && saved <= 100.0) ? saved : 100.0

        refreshDisplays()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshDisplays()
            }
        }
    }

    func refreshDisplays() {
        var found: [ExternalDisplayInfo] = []
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                continue
            }
            if CGDisplayIsBuiltin(id) == 0 {
                found.append(ExternalDisplayInfo(id: id, name: screen.localizedName))
            }
        }
        externalDisplays = found
        if !found.isEmpty && brightness < 99.5 {
            applyBrightness(brightness)
        }
    }

    private func applyBrightness(_ percent: Double) {
        guard !externalDisplays.isEmpty else { return }

        // 1. Apply immediate hardware LUT gamma scaling via CoreGraphics for 100% universal compatibility (HDMI/DP/USB-C)
        let normalized = Float(min(max(percent / 100.0, 0.12), 1.0))
        for display in externalDisplays {
            // Map 10%..100% to 0.18..1.0 gain so the screen never turns completely black
            let gain = Float(0.10 + 0.90 * Double(normalized))
            CGSetDisplayTransferByFormula(
                display.id,
                0.0, gain, 1.0,
                0.0, gain, 1.0,
                0.0, gain, 1.0
            )
        }

        // 2. Also send hardware DDC/CI VCP 0x10 command (throttled to avoid saturating I2C bus)
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastDDCWriteTime > 0.04 || percent == 100.0 || percent == 10.0 {
            lastDDCWriteTime = now
            let ddcValue = UInt16(percent.rounded())
            ddcQueue.async {
                Self.sendHardwareDDCBrightness(ddcValue)
            }
        }
    }

    private nonisolated static func sendHardwareDDCBrightness(_ value: UInt16) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("DCPAVServiceProxy"),
            &iterator
        ) == KERN_SUCCESS else {
            return
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            guard let loc = IORegistryEntryCreateCFProperty(
                service,
                "Location" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? String,
            loc == "External",
            let avService = IOAVServiceCreateWithService(kCFAllocatorDefault, service)?.takeRetainedValue() else {
                continue
            }

            var packet: [UInt8] = [
                0x84,
                0x03,
                0x10, // VCP 0x10 = Luminance
                UInt8((value >> 8) & 0xFF),
                UInt8(value & 0xFF),
                0x00
            ]
            packet[5] = 0x6E ^ 0x51 ^ packet[0] ^ packet[1] ^ packet[2] ^ packet[3] ^ packet[4]

            _ = IOAVServiceWriteI2C(avService, 0x37, 0x51, &packet, UInt32(packet.count))
        }
    }
}
