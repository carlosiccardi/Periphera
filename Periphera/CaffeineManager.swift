//
//  CaffeineManager.swift
//  Periphera
//
//  Created by Carlo Siccardi on 25/10/2026.
//

import Foundation
import IOKit.pwr_mgt
import Observation

enum CaffeineDuration: Int, CaseIterable, Identifiable, Sendable {
    case indefinite = 0
    case minutes15 = 900
    case minutes30 = 1800
    case hours1 = 3600
    case hours2 = 7200

    var id: Int { rawValue }

    func label(isIT: Bool) -> String {
        switch self {
        case .indefinite:
            return isIT ? "Sempre attivo" : "Indefinitely"
        case .minutes15:
            return "15 min"
        case .minutes30:
            return "30 min"
        case .hours1:
            return isIT ? "1 ora" : "1 hour"
        case .hours2:
            return isIT ? "2 ore" : "2 hours"
        }
    }
}

@Observable
@MainActor
final class CaffeineManager {
    static let shared = CaffeineManager()

    var isActive: Bool = false
    var selectedDuration: CaffeineDuration = .indefinite
    var remainingSeconds: Int = 0

    private var assertionID: IOPMAssertionID = 0
    private var countdownTask: Task<Void, Never>?

    private init() {}

    func toggle() {
        if isActive {
            deactivate()
        } else {
            activate(duration: selectedDuration)
        }
    }

    func activate(duration: CaffeineDuration) {
        // Release any existing assertion before creating a new one
        deactivate()

        selectedDuration = duration
        let reason = "Periphera Keep Awake (Caffeinate)" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )

        if result == kIOReturnSuccess {
            isActive = true
            if duration != .indefinite {
                remainingSeconds = duration.rawValue
                countdownTask = Task { @MainActor [weak self] in
                    while let self, self.isActive && self.remainingSeconds > 0 {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        if Task.isCancelled { break }
                        if self.remainingSeconds > 1 {
                            self.remainingSeconds -= 1
                        } else {
                            self.deactivate()
                            break
                        }
                    }
                }
            } else {
                remainingSeconds = 0
            }
        }
    }

    func deactivate() {
        if isActive && assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
        countdownTask?.cancel()
        countdownTask = nil
        isActive = false
        remainingSeconds = 0
    }

    var formattedRemainingTime: String? {
        guard isActive, selectedDuration != .indefinite, remainingSeconds > 0 else { return nil }
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
}
