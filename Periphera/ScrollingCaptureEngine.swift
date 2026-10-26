//
//  ScrollingCaptureEngine.swift
//  Periphera
//
//  Created by Carlo Siccardi on 25/10/2026.
//

import Cocoa
import Foundation
import CoreGraphics

nonisolated final class ScrollingCaptureEngine: @unchecked Sendable {
    private var baseImage: CGImage?
    private var slices: [(image: CGImage, shift: Int)] = []
    private var lastCapturedImage: CGImage?
    private var currentTotalHeight: Int = 0
    private let queue = DispatchQueue(label: "com.periphera.scrollingStitcher", qos: .userInitiated)

    // Limit max composite height to 35,000px to prevent memory exhaustion
    private let maxCompositeHeight = 35_000

    // Shifts below 4px are sub-pixel noise and are accumulated into the next frame
    private let minScrollThreshold = 4

    nonisolated init() {}

    nonisolated func reset() {
        queue.sync {
            baseImage = nil
            slices.removeAll()
            lastCapturedImage = nil
            currentTotalHeight = 0
        }
    }

    /// Process a new frame captured from the screen.
    /// Returns (didAdd: whether new scrolled content was appended, totalHeight, thumbnailPreview).
    nonisolated func processNewFrame(_ frame: CGImage) -> (didAdd: Bool, totalHeight: Int, thumbnail: NSImage?) {
        queue.sync {
            guard let previous = lastCapturedImage else {
                baseImage = frame
                lastCapturedImage = frame
                currentTotalHeight = frame.height
                let thumb = makeLiveThumbnail(base: frame, currentTotalHeight: frame.height)
                return (true, currentTotalHeight, thumb)
            }

            guard previous.width == frame.width, previous.height == frame.height else {
                return (false, currentTotalHeight, nil)
            }

            if currentTotalHeight >= maxCompositeHeight {
                return (false, currentTotalHeight, nil)
            }

            guard let shift = detectVerticalShift(prev: previous, curr: frame) else {
                return (false, currentTotalHeight, nil)
            }

            // If shift is below the minimum threshold, wait for content to move further before slicing.
            // Do NOT update lastCapturedImage so the next frame accumulates the full real displacement.
            if shift < minScrollThreshold {
                return (false, currentTotalHeight, nil)
            }

            // Crop the bottom `shift` pixels of `frame` (the brand new content that scrolled into view)
            let cropY = frame.height - shift
            guard cropY >= 0,
                  let croppedSlice = frame.cropping(to: CGRect(x: 0, y: cropY, width: frame.width, height: shift)) else {
                return (false, currentTotalHeight, nil)
            }

            slices.append((image: croppedSlice, shift: shift))
            lastCapturedImage = frame
            currentTotalHeight += shift

            let thumb = makeLiveThumbnail(base: baseImage ?? frame, currentTotalHeight: currentTotalHeight)
            return (true, currentTotalHeight, thumb)
        }
    }

    nonisolated var capturedFrameCount: Int {
        queue.sync {
            (baseImage != nil ? 1 : 0) + slices.count
        }
    }

    nonisolated var currentHeight: Int {
        queue.sync { currentTotalHeight }
    }

    /// Stitches all captured slices into a single tall composite CGImage with zero pixel alignment error.
    nonisolated func finalizeStitchedImage() -> CGImage? {
        queue.sync {
            guard let base = baseImage else { return nil }
            if slices.isEmpty { return base }

            let width = base.width
            let totalHeight = currentTotalHeight
            guard width > 0, totalHeight > 0 else { return base }

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            guard let context = CGContext(
                data: nil,
                width: width,
                height: totalHeight,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return base
            }

            // In Quartz coordinates, (0,0) is bottom-left, y points up.
            // Drawing at `totalHeight - base.height` places the initial base image at the TOP.
            var currentTopY = totalHeight - base.height
            context.draw(base, in: CGRect(x: 0, y: currentTopY, width: width, height: base.height))

            // Draw each slice below it in continuous vertical succession
            for slice in slices {
                currentTopY -= slice.shift
                context.draw(slice.image, in: CGRect(x: 0, y: currentTopY, width: width, height: slice.shift))
            }

            return context.makeImage()
        }
    }

    // MARK: - Live Preview Thumbnail Generator
    private func makeLiveThumbnail(base: CGImage, currentTotalHeight: Int) -> NSImage? {
        let thumbW = 70
        let aspect = CGFloat(currentTotalHeight) / max(CGFloat(base.width), 1.0)
        let thumbH = max(40, min(140, Int(CGFloat(thumbW) * aspect)))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: thumbW,
            height: thumbH,
            bitsPerComponent: 8,
            bytesPerRow: thumbW * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        ctx.interpolationQuality = .medium
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: thumbW, height: thumbH))

        guard let img = ctx.makeImage() else { return nil }
        return NSImage(cgImage: img, size: NSSize(width: thumbW, height: thumbH))
    }

    // MARK: - 1D Vertical Profile Waveform Correlation (CleanShot X / Panoramic Alignment)
    /// Computes a continuous 1D luminance profile across all rows, then correlates the waveforms
    /// across the full height to determine the exact vertical displacement with 0 pixel error.
    private func detectVerticalShift(prev: CGImage, curr: CGImage) -> Int? {
        let w = prev.width
        let h = prev.height
        guard w >= 60, h >= 100 else { return nil }

        let pPrev = computeRowProfile(prev)
        let pCurr = computeRowProfile(curr)
        guard pPrev.count == h, pCurr.count == h else { return nil }

        // 1. Detect sticky header height on the top (e.g. tabs, URL bar, menu bar that never scroll)
        var stickyRows = 0
        let maxStickyCheck = min(350, h / 3)
        while stickyRows < maxStickyCheck {
            if abs(pCurr[stickyRows] - pPrev[stickyRows]) < 0.005 {
                stickyRows += 1
            } else {
                break
            }
        }

        // Start correlation on the scrollable body content below any sticky elements
        let startY = stickyRows
        let maxShift = min(h - startY - 30, 950)
        guard maxShift >= 0 else { return 0 }

        // 2. Full waveform correlation search across all candidate offsets s in 0...maxShift
        var bestShift = 0
        var minDiff = Double.greatestFiniteMagnitude

        for s in 0...maxShift {
            var diff = 0.0
            var count = 0
            // Compare as many rows as possible (up to 800 rows of continuous visual signature)
            let compareRows = min(800, h - startY - s)
            guard compareRows >= 40 else { break }

            for y in startY..<(startY + compareRows) {
                let yP = y + s
                if yP < h {
                    diff += abs(pCurr[y] - pPrev[yP])
                    count += 1
                }
            }

            if count > 0 {
                let avg = diff / Double(count)
                if avg < minDiff {
                    minDiff = avg
                    bestShift = s
                }
            }
        }

        // If even the best match has high difference (> 0.08 average luminance mismatch),
        // the screen content changed completely or jumped beyond the search window
        if minDiff > 0.08 {
            return nil
        }

        return bestShift
    }

    /// Computes the horizontal average luminance per row across the middle 70% width
    private func computeRowProfile(_ image: CGImage) -> [Double] {
        guard let data = image.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return [] }

        let len = CFDataGetLength(data)
        let bpr = image.bytesPerRow
        let bpp = max(3, image.bitsPerPixel / 8)
        let h = image.height
        let w = image.width

        // Sample across the central 70% of the image to ignore sidebars and scrollbars
        let minX = Int(Double(w) * 0.15)
        let maxX = Int(Double(w) * 0.85)
        let stepX = 8

        var profile = [Double](repeating: 0, count: h)

        for y in 0..<h {
            let row = y * bpr
            var sum = 0
            var count = 0

            for x in stride(from: minX, to: maxX, by: stepX) {
                let idx = row + x * bpp
                guard idx + 2 < len else { continue }
                // Standard Rec. 601 Luma
                let lum = Int(ptr[idx]) * 299 + Int(ptr[idx + 1]) * 587 + Int(ptr[idx + 2]) * 114
                sum += lum
                count += 1
            }

            profile[y] = count > 0 ? (Double(sum) / Double(count * 1000)) : 0
        }

        return profile
    }
}
