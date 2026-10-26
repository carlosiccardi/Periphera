//
//  ScreenCaptureManager.swift
//  Periphera
//
//  Created by Carlo Siccardi on 25/10/2026.
//

import Cocoa
import SwiftUI
import Observation

@Observable
@MainActor
final class ScreenCaptureManager {
    static let shared = ScreenCaptureManager()

    // MARK: - State
    var isRecordingVideo: Bool = false
    var recordingSeconds: Int = 0
    var isScrollingCaptureActive: Bool = false
    var scrollingFramesCount: Int = 0
    var lastCapturedPath: String?

    // Subprocesses and Engines
    private var videoProcess: Process?
    private var recordingTask: Task<Void, Never>?
    private var currentVideoPath: String?

    private let scrollingEngine = ScrollingCaptureEngine()
    private var scrollingTask: Task<Void, Never>?
    private var scrollingRect: CGRect?
    private var scrollingHUDWindow: NSWindow?
    private var scrollingKeyMonitor: Any?
    private var recordingHUDWindow: NSWindow?

    private init() {}

    // MARK: - Helper paths
    private nonisolated static var desktopDirectory: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
    }

    private nonisolated static func makeTimestampFilename(prefix: String, ext: String) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'alle' HH.mm.ss"
        let timestamp = formatter.string(from: Date())
        let filename = "\(prefix) \(timestamp).\(ext)"
        return desktopDirectory.appendingPathComponent(filename)
    }

    // MARK: - 1. Standard Screenshot (Interactive or Pre-selected Area)
    func captureAreaScreenshot(rect: CGRect? = nil) {
        CaptureOverlayController.shared.hideImmediately()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            let outputURL = Self.makeTimestampFilename(prefix: "Screenshot", ext: "png")
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")

            if let r = rect, let screen = NSScreen.main {
                let screenH = screen.frame.height
                let scY = Int(screenH - (r.origin.y + r.height))
                let scX = Int(r.origin.x)
                let scW = Int(r.width)
                let scH = Int(r.height)
                task.arguments = ["-x", "-R\(scX),\(scY),\(scW),\(scH)", outputURL.path]
            } else {
                task.arguments = ["-i", outputURL.path]
            }

            task.terminationHandler = { [weak self] proc in
                Task { @MainActor in
                    if proc.terminationStatus == 0, FileManager.default.fileExists(atPath: outputURL.path) {
                        self?.lastCapturedPath = outputURL.path
                        self?.copyImageToClipboard(from: outputURL)
                        NSSound(named: "Blow")?.play()
                        self?.revealInFinder(url: outputURL)
                    }
                }
            }

            try? task.run()
        }
    }

    // MARK: - 2. Standard Screenshot (Full Screen)
    func captureFullScreenScreenshot() {
        CaptureOverlayController.shared.hideImmediately()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            let outputURL = Self.makeTimestampFilename(prefix: "Screenshot", ext: "png")
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            task.arguments = ["-x", outputURL.path]

            task.terminationHandler = { [weak self] proc in
                Task { @MainActor in
                    if proc.terminationStatus == 0, FileManager.default.fileExists(atPath: outputURL.path) {
                        self?.lastCapturedPath = outputURL.path
                        self?.copyImageToClipboard(from: outputURL)
                        NSSound(named: "Blow")?.play()
                        self?.revealInFinder(url: outputURL)
                    }
                }
            }

            try? task.run()
        }
    }

    // MARK: - 3. Screen Video Recording
    func startVideoRecording(area: CGRect? = nil) {
        guard !isRecordingVideo else { return }
        CaptureOverlayController.shared.hideImmediately()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            guard let self, !self.isRecordingVideo else { return }
            let outputURL = Self.makeTimestampFilename(prefix: "Registrazione Schermo", ext: "mov")
            self.currentVideoPath = outputURL.path

            var args = ["-v"]
            if let rect = area, let screen = NSScreen.main {
                let screenH = screen.frame.height
                let scY = Int(screenH - (rect.origin.y + rect.height))
                let scX = Int(rect.origin.x)
                let scW = Int(rect.width)
                let scH = Int(rect.height)
                if scW > 20 && scH > 20 {
                    args.append("-R\(scX),\(scY),\(scW),\(scH)")
                }
            }
            args.append(outputURL.path)

            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            task.arguments = args
            self.videoProcess = task

            do {
                try task.run()
                self.isRecordingVideo = true
                self.recordingSeconds = 0
                self.showRecordingHUD()

                self.recordingTask = Task { @MainActor [weak self] in
                    while let self, self.isRecordingVideo {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        if Task.isCancelled { break }
                        self.recordingSeconds += 1
                    }
                }
            } catch {
                print("Failed to start video recording: \(error)")
            }
        }
    }

    func stopVideoRecording() {
        guard isRecordingVideo, let process = videoProcess else { return }

        // Send SIGINT to cleanly close the .mov container
        kill(process.processIdentifier, SIGINT)

        recordingTask?.cancel()
        recordingTask = nil
        isRecordingVideo = false
        hideRecordingHUD()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, let path = self.currentVideoPath else { return }
            if FileManager.default.fileExists(atPath: path) {
                let url = URL(fileURLWithPath: path)
                self.revealInFinder(url: url)
            }
        }
    }

    // MARK: - 4. Scrolling Capture Session
    func beginScrollingCaptureSession(rect: CGRect, isIT: Bool) {
        CaptureOverlayController.shared.hideImmediately()

        scrollingEngine.reset()
        scrollingRect = rect
        isScrollingCaptureActive = true
        scrollingFramesCount = 1

        // Wait 0.08s for window server to clear the dark overlay, then start capturing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self, self.isScrollingCaptureActive else { return }

            self.showScrollingHUD(isIT: isIT)

            // Capture initial frame
            Task { @MainActor in
                await self.captureScrollingSliceAsync()

                // Continuous loop
                self.scrollingTask = Task { @MainActor [weak self] in
                    while let self, self.isScrollingCaptureActive {
                        try? await Task.sleep(nanoseconds: 240_000_000)
                        if Task.isCancelled || !self.isScrollingCaptureActive { break }
                        await self.captureScrollingSliceAsync()
                    }
                }
            }
        }
    }

    private func captureScrollingSliceAsync() async {
        guard isScrollingCaptureActive, let rect = scrollingRect, let screen = NSScreen.main else { return }

        let screenH = screen.frame.height
        let scY = Int(screenH - (rect.origin.y + rect.height))
        let scX = Int(rect.origin.x)
        let scW = Int(rect.width)
        let scH = Int(rect.height)

        guard scW > 20, scH > 20 else { return }

        let tempPath = NSTemporaryDirectory() + "periphera_scroll_\(UUID().uuidString.prefix(6)).png"

        let engine = scrollingEngine
        let didAdd = await Task.detached(priority: .userInitiated) { () -> Bool in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            task.arguments = ["-x", "-t", "png", "-R\(scX),\(scY),\(scW),\(scH)", tempPath]
            try? task.run()
            task.waitUntilExit()

            defer {
                try? FileManager.default.removeItem(atPath: tempPath)
            }

            guard FileManager.default.fileExists(atPath: tempPath),
                  let imageSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: tempPath) as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                return false
            }

            return engine.processNewFrame(cgImage)
        }.value

        if didAdd {
            scrollingFramesCount = scrollingEngine.capturedFrameCount
        }
    }

    func finishAndStitchScrollingCapture() {
        guard isScrollingCaptureActive else { return }

        scrollingTask?.cancel()
        scrollingTask = nil
        isScrollingCaptureActive = false
        hideScrollingHUD()

        let engine = scrollingEngine
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let stitchedCG = engine.finalizeStitchedImage() else {
                return
            }

            let outputURL = Self.makeTimestampFilename(prefix: "Screenshot Scorrimento", ext: "png")
            let nsImage = NSImage(cgImage: stitchedCG, size: NSSize(width: stitchedCG.width, height: stitchedCG.height))

            guard let tiffData = nsImage.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else {
                return
            }

            try? pngData.write(to: outputURL)

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.copyImageToClipboard(from: outputURL)
                self.lastCapturedPath = outputURL.path
                NSSound(named: "Blow")?.play()
                self.revealInFinder(url: outputURL)
            }
        }
    }

    func cancelScrollingCapture() {
        scrollingTask?.cancel()
        scrollingTask = nil
        isScrollingCaptureActive = false
        scrollingEngine.reset()
        hideScrollingHUD()
    }

    // MARK: - Minimal HUD Overlays
    private func showRecordingHUD() {
        hideRecordingHUD()
        let hud = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 230, height: 46),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        hud.level = .floating
        hud.isOpaque = false
        hud.backgroundColor = .clear
        hud.isMovableByWindowBackground = true
        hud.hasShadow = true
        hud.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = RecordingHUDView(manager: self)
        hud.contentView = NSHostingView(rootView: view)

        if let screen = NSScreen.main {
            let x = (screen.frame.width - 230) / 2.0
            let y = screen.frame.height - 75
            hud.setFrameOrigin(NSPoint(x: x, y: y))
        }

        hud.makeKeyAndOrderFront(nil)
        self.recordingHUDWindow = hud
    }

    private func hideRecordingHUD() {
        recordingHUDWindow?.close()
        recordingHUDWindow = nil
    }

    private func showScrollingHUD(isIT: Bool) {
        hideScrollingHUD()
        let hud = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 46),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        hud.level = .floating
        hud.isOpaque = false
        hud.backgroundColor = .clear
        hud.isMovableByWindowBackground = true
        hud.hasShadow = true
        hud.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = ScrollingHUDView(manager: self, isIT: isIT)
        hud.contentView = NSHostingView(rootView: view)

        if let screen = NSScreen.main {
            let x = (screen.frame.width - 340) / 2.0
            let y = screen.frame.height - 75
            hud.setFrameOrigin(NSPoint(x: x, y: y))
        }

        hud.makeKeyAndOrderFront(nil)
        self.scrollingHUDWindow = hud

        // Listen for Return / Enter key to finish and Esc to cancel
        installScrollingKeyMonitor()
    }

    private func hideScrollingHUD() {
        removeScrollingKeyMonitor()
        scrollingHUDWindow?.close()
        scrollingHUDWindow = nil
    }

    private func installScrollingKeyMonitor() {
        removeScrollingKeyMonitor()
        scrollingKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isScrollingCaptureActive else { return event }
            if event.keyCode == 36 { // Return / Enter
                self.finishAndStitchScrollingCapture()
                return nil
            }
            if event.keyCode == 53 { // Esc
                self.cancelScrollingCapture()
                return nil
            }
            return event
        }
    }

    private func removeScrollingKeyMonitor() {
        if let monitor = scrollingKeyMonitor {
            NSEvent.removeMonitor(monitor)
            scrollingKeyMonitor = nil
        }
    }

    // MARK: - Helpers
    private func copyImageToClipboard(from url: URL) {
        if let image = NSImage(contentsOf: url) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
        }
    }

    private func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// MARK: - Minimal Floating Recording HUD
private struct RecordingHUDView: View {
    @Bindable var manager: ScreenCaptureManager

    private var timeString: String {
        let mins = manager.recordingSeconds / 60
        let secs = manager.recordingSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.red)
                .frame(width: 9, height: 9)

            Text("REC \(timeString)")
                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)

            Spacer()

            Button("Ferma") {
                manager.stopVideoRecording()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4.5)
            .background(
                Capsule()
                    .fill(Color.red.opacity(0.18))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.red.opacity(0.4), lineWidth: 0.8)
                    )
            )
            .foregroundStyle(.red)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 23, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.8)
                )
        )
    }
}

// MARK: - Minimal Floating Scrolling HUD
private struct ScrollingHUDView: View {
    @Bindable var manager: ScreenCaptureManager
    let isIT: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.and.down.text.horizontal")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 1) {
                Text(isIT ? "Scorri verso il basso..." : "Scroll down slowly...")
                    .font(.system(size: 11, weight: .semibold))
                Text(isIT ? "\(manager.scrollingFramesCount) sezioni unite" : "\(manager.scrollingFramesCount) slices stitched")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Button "Fatto" / "Done"
            Button(isIT ? "Fatto (Invio)" : "Done (Enter)") {
                manager.finishAndStitchScrollingCapture()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4.5)
            .background(
                Capsule()
                    .fill(Color.green.opacity(0.20))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.green.opacity(0.4), lineWidth: 0.8)
                    )
            )
            .foregroundStyle(.green)

            Button {
                manager.cancelScrollingCapture()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 23, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.8)
                )
        )
    }
}
