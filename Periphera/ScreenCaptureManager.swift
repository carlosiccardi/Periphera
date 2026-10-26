//
//  ScreenCaptureManager.swift
//  Periphera
//
//  Created by Carlo Siccardi on 25/10/2026.
//

import Cocoa
import SwiftUI
import Observation
import ScreenCaptureKit

@Observable
@MainActor
final class ScreenCaptureManager {
    static let shared = ScreenCaptureManager()

    // MARK: - State
    var isRecordingVideo: Bool = false
    var recordingSeconds: Int = 0
    var isScrollingCaptureActive: Bool = false
    var scrollingFramesCount: Int = 0
    var scrollingTotalHeight: Int = 0
    var scrollingLiveThumbnail: NSImage?
    var lastCapturedPath: String?

    // Subprocesses and Engines
    private var videoProcess: Process?
    private var recordingTask: Task<Void, Never>?
    private var currentVideoPath: String?

    private let scrollingEngine = ScrollingCaptureEngine()
    private var scrollingTask: Task<Void, Never>?
    private var scrollingRect: CGRect?
    private var isITLanguage: Bool = true
    private var recordingHUDWindow: NSWindow?

    // Fast-path cache for ScreenCaptureKit during active scrolling session
    private var cachedFilter: SCContentFilter?
    private var cachedConfig: SCStreamConfiguration?

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
    func captureAreaScreenshot(rect: CGRect? = nil, isIT: Bool = true) {
        CaptureOverlayController.shared.hideImmediately()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            let outputURL = Self.makeTimestampFilename(prefix: "Screenshot", ext: "png")
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")

            if let r = rect, NSScreen.main != nil {
                let scX = Int(r.origin.x)
                let scY = Int(r.origin.y)
                let scW = Int(r.width)
                let scH = Int(r.height)
                task.arguments = ["-x", "-R\(scX),\(scY),\(scW),\(scH)", outputURL.path]
            } else {
                task.arguments = ["-i", outputURL.path]
            }

            task.terminationHandler = { [weak self] proc in
                Task { @MainActor in
                    if proc.terminationStatus == 0, FileManager.default.fileExists(atPath: outputURL.path) {
                        self?.handleScreenshotSuccess(fileURL: outputURL, isIT: isIT)
                    }
                }
            }

            try? task.run()
        }
    }

    // MARK: - 2. Standard Screenshot (Full Screen)
    func captureFullScreenScreenshot(isIT: Bool = true) {
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
                        self?.handleScreenshotSuccess(fileURL: outputURL, isIT: isIT)
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
            if let rect = area {
                let scX = Int(rect.origin.x)
                let scY = Int(rect.origin.y)
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

    // MARK: - 4. Scrolling Capture Session (CleanShot X Architecture)
    func beginScrollingCaptureSession(rect: CGRect, isIT: Bool) {
        CaptureOverlayController.shared.hideImmediately()

        scrollingEngine.reset()
        scrollingRect = rect
        isITLanguage = isIT
        isScrollingCaptureActive = true
        scrollingFramesCount = 1
        scrollingTotalHeight = Int(rect.height)
        scrollingLiveThumbnail = nil

        // Present CleanShot X active scrolling frame & pass-through HUD
        ScrollingFrameOverlayController.shared.show(
            rect: rect,
            isIT: isIT,
            manager: self,
            onDone: { [weak self] in
                self?.finishAndStitchScrollingCapture()
            },
            onCancel: { [weak self] in
                self?.cancelScrollingCapture()
            }
        )

        // Capture initial baseline frame immediately
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.captureScrollingSliceAsync()

            // Continuous high-frequency capture loop (~60ms / 16.6 fps)
            self.scrollingTask = Task { @MainActor [weak self] in
                while let self, self.isScrollingCaptureActive {
                    try? await Task.sleep(nanoseconds: 60_000_000)
                    if Task.isCancelled || !self.isScrollingCaptureActive { break }
                    await self.captureScrollingSliceAsync()
                }
            }
        }
    }

    private func captureScrollingSliceAsync() async {
        guard isScrollingCaptureActive, let rect = scrollingRect else { return }

        guard let frame = await grabScreenRectCGImage(rect: rect) else { return }

        let result = scrollingEngine.processNewFrame(frame)
        if result.didAdd {
            self.scrollingFramesCount = self.scrollingEngine.capturedFrameCount
            self.scrollingTotalHeight = result.totalHeight
            if let thumb = result.thumbnail {
                self.scrollingLiveThumbnail = thumb
            }
        }
    }

    func finishAndStitchScrollingCapture() {
        guard isScrollingCaptureActive else { return }

        scrollingTask?.cancel()
        scrollingTask = nil
        isScrollingCaptureActive = false
        cachedFilter = nil
        cachedConfig = nil
        ScrollingFrameOverlayController.shared.hide()

        let isIT = isITLanguage
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
                self.handleScreenshotSuccess(fileURL: outputURL, image: nsImage, isIT: isIT)
            }
        }
    }

    func cancelScrollingCapture() {
        scrollingTask?.cancel()
        scrollingTask = nil
        isScrollingCaptureActive = false
        cachedFilter = nil
        cachedConfig = nil
        scrollingEngine.reset()
        scrollingLiveThumbnail = nil
        ScrollingFrameOverlayController.shared.hide()
    }

    // MARK: - Fast In-Memory Screen Capture (ScreenCaptureKit with screencapture Fallback)
    private func grabScreenRectCGImage(rect: CGRect) async -> CGImage? {
        // Fast-path: use cached filter and config for zero-overhead capture during scrolling
        if let filter = cachedFilter, let config = cachedConfig {
            do {
                return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            } catch {
                // Cache invalidated, fall through to re-query
            }
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return nil }

            // Exclude Periphera's own HUD and window frames
            let peripheraWindows = content.windows.filter {
                $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
            }

            let filter = SCContentFilter(display: display, excludingWindows: peripheraWindows)
            let config = SCStreamConfiguration()

            // In ScreenCaptureKit, sourceRect uses display coordinates (0,0 is top-left)
            config.sourceRect = rect
            let scale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2.0
            config.width = max(1, Int(rect.width * scale))
            config.height = max(1, Int(rect.height * scale))
            config.showsCursor = false

            if isScrollingCaptureActive {
                self.cachedFilter = filter
                self.cachedConfig = config
            }

            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            // Fallback via screencapture CLI if ScreenCaptureKit encounters any permission hitch
            return await fallbackGrabViaScreencapture(rect: rect)
        }
    }

    private func fallbackGrabViaScreencapture(rect: CGRect) async -> CGImage? {
        await Task.detached(priority: .userInitiated) { () -> CGImage? in
            let scX = Int(rect.origin.x)
            let scY = Int(rect.origin.y)
            let scW = Int(rect.width)
            let scH = Int(rect.height)
            guard scW > 20, scH > 20 else { return nil }

            let tempPath = NSTemporaryDirectory() + "periphera_scr_\(UUID().uuidString.prefix(6)).png"
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            task.arguments = ["-x", "-t", "png", "-R\(scX),\(scY),\(scW),\(scH)", tempPath]
            try? task.run()
            task.waitUntilExit()

            defer { try? FileManager.default.removeItem(atPath: tempPath) }

            guard FileManager.default.fileExists(atPath: tempPath),
                  let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: tempPath) as CFURL, nil),
                  let img = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return nil
            }
            return img
        }.value
    }

    // MARK: - CleanShot X Completion Handler
    private func handleScreenshotSuccess(fileURL: URL, image: NSImage? = nil, isIT: Bool = true) {
        lastCapturedPath = fileURL.path
        let finalImage = image ?? NSImage(contentsOf: fileURL)

        if let finalImage {
            // 1. Copy to Clipboard
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([finalImage])

            // 2. Play subtle macOS camera shutter sound
            NSSound(named: "Blow")?.play()

            // 3. Show CleanShot X-Style Quick Access Overlay
            let dimensions = finalImage.size
            QuickAccessOverlayController.shared.show(
                image: finalImage,
                fileURL: fileURL,
                dimensions: dimensions,
                isIT: isIT
            )
        }
    }

    // MARK: - Video Recording HUD
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

    private func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// MARK: - Video Recording Floating HUD View
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
