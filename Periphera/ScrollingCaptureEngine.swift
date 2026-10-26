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

    // Limit max composite height to 30,000px to prevent memory exhaustion
    private let maxCompositeHeight = 30_000

    // Minimum scroll shift required to commit a new slice.
    // Shifts under 6px are sub-pixel font hinting noise and must be accumulated to prevent venetian-blind artifacts.
    private let minScrollThreshold = 6

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

            guard let shift = detectConsensusVerticalShift(prev: previous, curr: frame) else {
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

    // MARK: - Robust Template-Based Vertical Shift Detection (CleanShot X Algorithm)
    private func detectConsensusVerticalShift(prev: CGImage, curr: CGImage) -> Int? {
        let w = prev.width
        let h = prev.height
        guard w >= 60, h >= 100 else { return nil }

        guard let dataPrev = prev.dataProvider?.data, let ptrPrev = CFDataGetBytePtr(dataPrev),
              let dataCurr = curr.dataProvider?.data, let ptrCurr = CFDataGetBytePtr(dataCurr) else {
            return nil
        }

        let lenPrev = CFDataGetLength(dataPrev)
        let lenCurr = CFDataGetLength(dataCurr)
        guard lenPrev > 0, lenCurr > 0 else { return nil }

        let bprPrev = prev.bytesPerRow
        let bprCurr = curr.bytesPerRow
        let bppPrev = max(3, prev.bitsPerPixel / 8)
        let bppCurr = max(3, curr.bitsPerPixel / 8)

        // Substantial band height (36-50px) to span multiple lines of text and unique features
        let bandH = min(50, max(32, h / 25))
        let stepX = 8

        // Search within the central 70% width to avoid scrollbars and sidebar noise
        let minX = Int(Double(w) * 0.15)
        let maxX = Int(Double(w) * 0.85)

        // 5 candidate anchors placed in the scrollable body (20% to 65% of viewport)
        let bandTargets = [
            Int(Double(h) * 0.20),
            Int(Double(h) * 0.32),
            Int(Double(h) * 0.44),
            Int(Double(h) * 0.56),
            Int(Double(h) * 0.68)
        ]

        var detectedShifts: [Int] = []

        for anchorY in bandTargets {
            guard anchorY + bandH < h else { continue }

            // 1. Check visual entropy/variance across this band; skip flat white/gray areas
            var variance = 0
            var sampleValues: [Int] = []
            for yOffset in stride(from: 4, to: bandH, by: 12) {
                let row = (anchorY + yOffset) * bprCurr
                for x in stride(from: minX, to: maxX, by: stepX * 2) {
                    let idx = row + x * bppCurr
                    if idx + 2 < lenCurr {
                        // Luminance
                        let lum = (Int(ptrCurr[idx]) * 299 + Int(ptrCurr[idx + 1]) * 587 + Int(ptrCurr[idx + 2]) * 114) / 1000
                        sampleValues.append(lum)
                    }
                }
            }
            if !sampleValues.isEmpty {
                let mean = sampleValues.reduce(0, +) / sampleValues.count
                let diffSum = sampleValues.reduce(0) { $0 + abs($1 - mean) }
                variance = diffSum / sampleValues.count
                if variance < 6 {
                    continue // Low contrast / plain white whitespace
                }
            }

            // 2. Check if this band is static (e.g. sticky header, fixed navigation, or paused screen)
            var zeroDiff = 0
            var zeroCount = 0
            for sy in stride(from: 0, to: bandH, by: 4) {
                let rowC = (anchorY + sy) * bprCurr
                let rowP = (anchorY + sy) * bprPrev
                for x in stride(from: minX, to: maxX, by: stepX) {
                    let idxC = rowC + x * bppCurr
                    let idxP = rowP + x * bppPrev
                    guard idxC + 2 < lenCurr, idxP + 2 < lenPrev else { continue }
                    zeroDiff += abs(Int(ptrCurr[idxC]) - Int(ptrPrev[idxP]))
                    zeroCount += 1
                }
            }

            if zeroCount > 0 && (zeroDiff / zeroCount) < 4 {
                // This band did not move at all
                detectedShifts.append(0)
                continue
            }

            // 3. For moving bands, search from s = minScrollThreshold through maxShift
            let maxShiftForBand = min(h - bandH - anchorY, 950)
            guard maxShiftForBand >= minScrollThreshold else { continue }

            // Phase 1: Coarse search (stride 4) starting at minScrollThreshold (skips subpixel noise 0..5)
            var bestCoarseS = -1
            var minCoarseDiff = Int.max

            for s in stride(from: minScrollThreshold, through: maxShiftForBand, by: 4) {
                let prevY = anchorY + s
                guard prevY + bandH < h else { break }

                var diff = 0
                var sampleCount = 0

                for sy in stride(from: 0, to: bandH, by: 4) {
                    let rowC = (anchorY + sy) * bprCurr
                    let rowP = (prevY + sy) * bprPrev

                    for x in stride(from: minX, to: maxX, by: stepX) {
                        let idxC = rowC + x * bppCurr
                        let idxP = rowP + x * bppPrev
                        guard idxC + 2 < lenCurr, idxP + 2 < lenPrev else { continue }

                        diff += abs(Int(ptrCurr[idxC]) - Int(ptrPrev[idxP]))
                        sampleCount += 1
                    }
                }

                if sampleCount > 0 {
                    let avg = diff / sampleCount
                    if avg < minCoarseDiff {
                        minCoarseDiff = avg
                        bestCoarseS = s
                    }
                }
            }

            guard bestCoarseS >= minScrollThreshold, minCoarseDiff < 42 else { continue }

            // Phase 2: Fine search around bestCoarseS (stride 1)
            let fineStart = max(minScrollThreshold, bestCoarseS - 4)
            let fineEnd = min(maxShiftForBand, bestCoarseS + 4)
            var bestFineS = bestCoarseS
            var minFineDiff = minCoarseDiff

            for s in fineStart...fineEnd {
                let prevY = anchorY + s
                guard prevY + bandH < h else { break }

                var diff = 0
                var sampleCount = 0

                for sy in stride(from: 0, to: bandH, by: 2) {
                    let rowC = (anchorY + sy) * bprCurr
                    let rowP = (prevY + sy) * bprPrev

                    for x in stride(from: minX, to: maxX, by: stepX) {
                        let idxC = rowC + x * bppCurr
                        let idxP = rowP + x * bppPrev
                        guard idxC + 2 < lenCurr, idxP + 2 < lenPrev else { continue }

                        diff += abs(Int(ptrCurr[idxC]) - Int(ptrPrev[idxP]))
                        sampleCount += 1
                    }
                }

                if sampleCount > 0 {
                    let avg = diff / sampleCount
                    if avg < minFineDiff {
                        minFineDiff = avg
                        bestFineS = s
                    }
                }
            }

            // Accept band if pixel difference satisfies subpixel threshold (< 38)
            if minFineDiff < 38 {
                detectedShifts.append(bestFineS)
            }
        }

        guard !detectedShifts.isEmpty else { return nil }

        // Filter out static / sticky elements (shift == 0)
        let positiveShifts = detectedShifts.filter { $0 >= minScrollThreshold }

        if positiveShifts.isEmpty {
            return 0 // The scrollable body did not move
        }

        // Consensus logic: find pair agreeing within 3 pixels
        if positiveShifts.count >= 2 {
            for i in 0..<positiveShifts.count {
                for j in (i + 1)..<positiveShifts.count {
                    if abs(positiveShifts[i] - positiveShifts[j]) <= 3 {
                        return (positiveShifts[i] + positiveShifts[j]) / 2
                    }
                }
            }
        }

        // If slight variance, take median
        let sorted = positiveShifts.sorted()
        return sorted[sorted.count / 2]
    }
}
